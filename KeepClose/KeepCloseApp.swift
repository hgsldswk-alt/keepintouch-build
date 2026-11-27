import StoreKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

extension UTType {
    static let keepClose = UTType(exportedAs: "com.hgsldswk.keepintouch.settings", conformingTo: .plainText)
}

@main
struct KeepCloseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        KeepCloseShortcuts.updateAppShortcutParameters()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

struct EditorRoute: Identifiable {
    let id = UUID()
    let person: Person?
}

struct ShareRoute: Identifiable {
    let id = UUID()
    let personID: UUID?
    var milestone = false
}

struct ImportRoute: Identifiable {
    let id = UUID()
    let prefs: Preferences
}

@MainActor
struct RootView: View {
    @StateObject private var model = AppModel()
    @ObservedObject private var purchases = Purchases.shared
    @ObservedObject private var router = IntentRouter.shared
    @Environment(\.scenePhase) private var phase
    @Environment(\.requestReview) private var requestReview

    @State private var selection: UUID?
    @State private var editor: EditorRoute?
    @State private var share: ShareRoute?
    @State private var imported: ImportRoute?
    @State private var more = false
    @State private var paywall = false
    @State private var pendingURL: URL?
    @State private var afterMore: (() -> Void)?
    @State private var photos = PhotoPickerState()
    @State private var pickingContact = false
    @State private var starting = true
    @State private var refreshing = false
    @State private var homeActivity = 0
    @State private var showingExpiryNotice = false

    var body: some View {
        content
            .foregroundStyle(Palette.ink)
            .background(Palette.paper.ignoresSafeArea())
            .tint(Palette.accentText)
            .task {
                if model.testing, let code = Launch.value("-paste-code") { UIPasteboard.general.string = code }
                await model.start()
                await purchases.start(now: model.now, testing: model.testing, expired: model.expired)
                if let pendingURL { self.pendingURL = nil; open(pendingURL) }
                if model.arguments.contains("-paywall") { paywall = true }
                if let id = Launch.value("-open").flatMap(UUID.init(uuidString:)) { selection = id }
                if let dial = router.dial { router.dial = nil; dialFromShortcut(dial) }
                starting = false
            }
            .onChange(of: phase) { _, value in
                if value == .active {
                    refreshing = true
                    Task {
                        await model.activate()
                        await purchases.refresh()
                        refreshing = false
                    }
                } else {
                    model.leaveApp()
                }
            }
            .onChange(of: purchases.entitlement) {
                if model.ready { model.refreshReminders() }
            }
            .onChange(of: selection) { _, _ in model.clearPhotoPrompt() }
            .task(id: reviewEligible ? homeActivity : nil) {
                guard reviewEligible else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, reviewEligible, model.reserveReview() else { return }
                requestReview()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                Task { await model.activate() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .CNContactStoreDidChangeCompat)) { _ in
                Task { await model.refreshContacts() }
            }
            .onChange(of: router.dial) { _, value in
                guard let value, model.ready else { return }
                router.dial = nil
                dialFromShortcut(value)
            }
            .onOpenURL { url in
                if model.ready { open(url) } else { pendingURL = url }
            }
            .sheet(item: $editor) { route in
                PersonEditor(model: model, purchases: purchases, person: route.person) { deleted in
                    if deleted { selection = nil }
                }
            }
            .sheet(item: $share) { route in
                ShareSheet(model: model, purchases: purchases, personID: route.personID,
                           milestone: route.milestone, unlock: { paywall = true })
            }
            .sheet(item: $imported) { route in
                ImportPreview(prefs: route.prefs) {
                    if model.applyCode(route.prefs) { model.showToast(L.t("import.done")) }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $more, onDismiss: finishMore) {
                MoreView(model: model, purchases: purchases,
                         unlock: { leaveMore { paywall = true } },
                         summary: { leaveMore { share = ShareRoute(personID: nil) } },
                         importCode: { prefs in leaveMore { imported = ImportRoute(prefs: prefs) } })
            }
            .sheet(isPresented: $paywall) { PaywallView(purchases: purchases, now: model.now) }
            .modifier(PhotoPicker(model: model, state: $photos))
            .alert(L.t("notice.title"), isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button(L.t("common.ok"), role: .cancel) { model.message = nil }
            } message: {
                Text(model.message ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if !model.ready {
            if model.loadFailed {
                HeroCard {
                    VStack(spacing: 12) {
                        EmptyIllustration(symbol: "externaldrive.fill")
                        Text(L.t("error.read")).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        Button { Task { await model.start() } } label: {
                            Label(L.t("common.retry"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(PrimaryButton())
                    }
                }
                .padding(18)
            } else {
                ProgressView().tint(Palette.accentText).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let selection, let person = model.person(selection) {
            PersonDetail(model: model, person: person, back: { self.selection = nil },
                         edit: { editor = EditorRoute(person: person) },
                         share: { milestone in share = ShareRoute(personID: person.id, milestone: milestone) },
                         addPhoto: { photos.open(for: person.id) },
                         takePhoto: { photos.requestCamera(for: person.id) })
        } else {
            HomeView(model: model, open: { selection = $0.id }, manual: { editor = EditorRoute(person: nil) },
                     more: { more = true }, addPhoto: { photos.open(for: $0.id) }, pickingContact: $pickingContact,
                     showExpiryNotice: showExpiryNotice, expiryNoticeAppeared: {
                         showingExpiryNotice = true
                         purchases.markExpiryNoticeShown()
                     }, dismissExpiryNotice: { showingExpiryNotice = false }, unlock: {
                         showingExpiryNotice = false
                         paywall = true
                     })
                .simultaneousGesture(DragGesture().onChanged { _ in
                    if reviewEligible { homeActivity += 1 }
                })
        }
    }

    private var showExpiryNotice: Bool {
        guard purchases.entitlement?.hasExpiredTrial(at: model.now) == true else { return false }
        if showingExpiryNotice { return true }
        return phase == .active && !starting && !refreshing && !purchases.hasShownExpiryNotice &&
            editor == nil && share == nil && imported == nil && !more && !paywall &&
            !pickingContact && !photos.busy && model.message == nil
    }

    private var reviewEligible: Bool {
        phase == .active && model.ready && model.reviewReady && !starting && !refreshing &&
            selection == nil && editor == nil && share == nil && imported == nil && !more && !paywall &&
            pendingURL == nil && afterMore == nil && !photos.busy && !pickingContact &&
            model.candidate == nil && model.pendingFaceTime == nil && !model.dialing &&
            model.toast == nil && model.message == nil && purchases.message == nil && !purchases.busy && !showExpiryNotice
    }

    private func leaveMore(_ next: @escaping () -> Void) {
        afterMore = next
        more = false
    }

    private func finishMore() {
        let next = afterMore
        afterMore = nil
        next?()
    }

    private func dialFromShortcut(_ id: UUID) {
        guard let person = model.person(id) else { return }
        selection = nil
        model.call(person)
    }

    private func open(_ url: URL) {
        if url.isFileURL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if let prefs = SettingsCode.decode(String(text.prefix(200))) { imported = ImportRoute(prefs: prefs) }
            else { model.message = L.t("import.invalid") }
            return
        }
        guard url.scheme == "keepclose", let id = UUID(uuidString: url.lastPathComponent), let person = model.person(id) else { return }
        if url.host == "call", !model.phones(person).isEmpty {
            selection = nil
            model.call(person)
        } else {
            selection = person.id
        }
    }

}

extension Notification.Name {
    static let CNContactStoreDidChangeCompat = Notification.Name("CNContactStoreDidChangeNotification")
}
