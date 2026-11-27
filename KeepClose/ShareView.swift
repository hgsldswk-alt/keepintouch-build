import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum ShareQR {
    static let appStoreID = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String

    static var url: URL {
        if let id = appStoreID, !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) {
            return URL(string: "https://apps.apple.com/app/id" + id)!
        }
        return URL(string: "https://example.invalid/keepclose")!
    }

    static var placeholder: Bool { url.host == "example.invalid" }

    static func image() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let raw = filter.outputImage else { return nil }
        let bounds = raw.extent.insetBy(dx: -4, dy: -4)
        let quiet = raw.composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: bounds))
            .transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = CIContext().createCGImage(quiet, from: quiet.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct ShareSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var purchases: Purchases
    let personID: UUID?
    let milestone: Bool
    let unlock: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selected: [UUID] = []
    @State private var customTitle = ""
    @State private var hideDates = false
    @State private var dark = false
    @State private var showPrivateDetails = false
    @State private var payload: SharePayload?
    @State private var requested = false

    private var person: Person? { personID.flatMap(model.person) }
    private var pro: Bool { purchases.hasPro(at: model.now) }
    private var limit: Int { pro ? 6 : 3 }
    private var all: [PhotoEntry] { person.map(model.photos) ?? [] }
    private var summary: MonthlySummary { MonthlySummary(data: model.data, now: model.now, calendar: model.calendar) }
    private var artworkHeight: CGFloat {
        guard person == nil else { return 450 }
        let rows = (summary.people.count + 1) / 2
        return max(450, 410 + CGFloat(rows) * 32)
    }
    private var titleKey: String { milestone ? "share.milestone-title" : "share.default-title" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    GeometryReader { layout in
                        artwork
                            .scaleEffect(layout.size.width / 360, anchor: .topLeading)
                            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                    }
                        .aspectRatio(360 / artworkHeight, contentMode: .fit)
                        .frame(maxWidth: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("share.preview")
                    Toggle(isOn: $showPrivateDetails) {
                        IconRow(title: L.t(person == nil ? "share.show-names" : "share.show-details"),
                                symbol: "lock.fill", color: Palette.sage)
                    }
                        .cardStyle()
                        .accessibilityIdentifier("share.show-details")
                    Button { share() } label: { Label(L.t("share.go"), systemImage: "square.and.arrow.up") }
                        .buttonStyle(PrimaryButton())
                        .accessibilityIdentifier("share.go")
                    if requested {
                        Text(L.t("share.requested")).font(.caption).foregroundStyle(Palette.muted)
                            .accessibilityIdentifier("share.requested")
                    }
                    if person != nil { controls }
                    Text(L.t("share.private")).font(.caption).foregroundStyle(Palette.muted)
                }
                .padding(20)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(L.t(person == nil ? "summary.title" : "share.timeline"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("common.close")) { dismiss() } } }
            .onAppear {
                selected = Array(all.prefix(3).map(\.id))
            }
            .sheet(item: $payload) { item in
                ActivitySheet(payload: item) { _ in payload = nil }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let person {
                TextField(L.t("share.title.field"), text: $customTitle,
                          prompt: Text(L.f(titleKey, displayName(person))))
                    .textFieldStyle(.roundedBorder)
            }
            Text(L.f("share.pick", limit)).sectionTitle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(all) { entry in
                        Button { toggle(entry.id) } label: {
                            PhotoTile(image: model.image(entry), height: 72).frame(width: 72)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Palette.onAccent, Palette.accent).font(.title3).padding(4)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("share.photo")
                    }
                }
            }
            Toggle(L.t("share.hide-dates"), isOn: $hideDates)
            if pro {
                Toggle(L.t("share.dark"), isOn: $dark)
            } else {
                Button { dismiss(); unlock() } label: { Label(L.t("share.more-pro"), systemImage: "sparkles") }
                    .buttonStyle(PrimaryButton(filled: false))
            }
        }
        .cardStyle()
    }

    private func toggle(_ id: UUID) {
        if let index = selected.firstIndex(of: id) { selected.remove(at: index); return }
        if selected.count >= limit {
            if !pro { model.message = L.t("share.limit.free") }
            return
        }
        selected.append(id)
    }

    @ViewBuilder
    private var artwork: some View {
        if let person {
            TimelineArtwork(title: customTitle.isEmpty ? L.f(titleKey, displayName(person)) : customTitle,
                            photos: all.filter { selected.contains($0.id) }.prefix(limit).map { ($0, model.image($0, thumbnail: false)) },
                            hideDates: hideDates, dark: dark, phone: showPrivateDetails ? model.phones(person).first : nil)
        } else {
            SummaryArtwork(date: model.now, summary: summary, height: artworkHeight, displayName: displayName)
        }
    }

    private func displayName(_ person: Person) -> String {
        let fullName = model.info(person)?.name
        if showPrivateDetails { return fullName.flatMap { $0.isEmpty ? nil : $0 } ?? person.displayName }
        if let fullName, !fullName.isEmpty, person.shareName.caseInsensitiveCompare(fullName) == .orderedSame {
            return person.relation.callName
        }
        return person.shareName
    }

    @MainActor
    private func share() {
        let renderer = ImageRenderer(content: artwork.frame(width: 360, height: artworkHeight))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let bytes = image.pngData() else { model.message = L.t("error.share"); return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(L.t("file.card") + ".png")
        do { try bytes.write(to: url, options: .atomic) } catch { model.message = L.t("error.share"); return }
        if model.testing { requested = true; return }
        payload = SharePayload(items: [url, L.t(person == nil ? "summary.caption" : "share.caption")])
    }
}

private struct QRFooter: View {
    var dark = false

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("share.hashtag")).font(.system(size: 11, weight: .semibold))
                Text(L.t("share.footer")).font(.system(size: 10)).opacity(0.75)
            }
            Spacer()
            VStack(spacing: 2) {
                if let qr = ShareQR.image() {
                    Image(uiImage: qr).interpolation(.none).resizable().frame(width: 54, height: 54)
                }
                Text(L.t(ShareQR.placeholder ? "share.qr.placeholder" : "share.qr")).font(.system(size: 7)).opacity(0.75)
            }
        }
        .foregroundStyle(dark ? Palette.onDarkPanel : Palette.artworkInk)
    }
}

struct TimelineArtwork: View {
    let title: String
    let photos: [(PhotoEntry, UIImage?)]
    let hideDates: Bool
    let dark: Bool
    let phone: String?

    var body: some View {
        let sorted = photos.sorted { $0.0.takenAt > $1.0.takenAt }
        let dense = sorted.count > 4
        VStack(alignment: .leading, spacing: 7) {
            if let first = sorted.last?.0.takenAt, let last = sorted.first?.0.takenAt, !hideDates {
                let a = Calendar.current.component(.year, from: first)
                let b = Calendar.current.component(.year, from: last)
                Text(a == b ? String(a) : "\(a) — \(b)").font(.system(size: 11, weight: .semibold)).opacity(0.7)
            }
            HStack(alignment: .center, spacing: 8) {
                Text(title).font(.system(size: 22, weight: .bold, design: .serif)).lineLimit(2).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("share.artwork.title")
                Spacer(minLength: 0)
                EmptyIllustration(symbol: "photo.on.rectangle.angled", scale: 0.46)
            }
            if let phone {
                Text(phone).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    .accessibilityIdentifier("share.artwork.phone")
            }
            if let cover = sorted.first {
                framed(cover, height: dense ? 96 : (sorted.count > 1 ? 130 : 210))
            } else {
                EmptyIllustration(symbol: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(Palette.pale, in: RoundedRectangle(cornerRadius: 16))
            }
            let rest = Array(sorted.dropFirst().prefix(5))
            if !rest.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: rest.count > 2 ? 3 : rest.count), spacing: 6) {
                    ForEach(rest.indices, id: \.self) { index in framed(rest[index], height: dense ? 38 : 64) }
                }
            }
            Spacer(minLength: 0)
            QRFooter(dark: dark)
        }
        .padding(18)
        .frame(width: 360, height: 450, alignment: .topLeading)
        .foregroundStyle(dark ? Palette.onDarkPanel : Palette.artworkInk)
        .background(dark ? Palette.darkPanel : Palette.artworkPaper)
        .artworkBorder()
        .environment(\.colorScheme, .light)
    }

    private func framed(_ item: (PhotoEntry, UIImage?), height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Color.clear.frame(height: height)
                .overlay { if let image = item.1 { Image(uiImage: image).resizable().scaledToFill() } else { Palette.pale } }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            if !hideDates {
                Text(L.day(item.0.takenAt, "yMMMd")).font(.system(size: 9, weight: .medium)).opacity(0.75)
            }
        }
    }
}

struct SummaryArtwork: View {
    let date: Date
    let summary: MonthlySummary
    let height: CGFloat
    let displayName: (Person) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.day(date, "yMMMM")).font(.system(size: 12, weight: .semibold)).opacity(0.7)
                    Text(L.t("summary.heading")).font(.system(size: 24, weight: .bold, design: .serif)).lineLimit(2)
                }
                Spacer(minLength: 0)
                EmptyIllustration(symbol: "chart.bar.fill", scale: 0.58)
            }
            HStack(spacing: 10) {
                stat(summary.people.count, L.t("summary.people"), color: Palette.sage)
                stat(summary.calls, L.t("summary.calls"), color: Palette.mist)
                stat(summary.visits, L.t("summary.visits"), color: Palette.butter)
            }
            if !summary.people.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("summary.contacted")).font(.system(size: 13, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 2) {
                        ForEach(summary.people) { person in
                            Text(displayName(person)).font(.system(size: 12))
                                .lineLimit(2)
                                .frame(height: 30, alignment: .leading)
                                .accessibilityIdentifier("summary.person")
                        }
                    }
                }
            }
            if let longest = summary.longest {
                Text(L.f("summary.longest", displayName(longest.person), longest.days)).font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.warm, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("summary.longest")
            }
            Text(L.t("summary.line")).font(.system(size: 13)).opacity(0.8)
            Spacer(minLength: 0)
            QRFooter()
        }
        .padding(20)
        .frame(width: 360, height: height, alignment: .topLeading)
        .foregroundStyle(Palette.artworkInk)
        .background(Palette.artworkPaper)
        .artworkBorder()
        .environment(\.colorScheme, .light)
    }

    private func stat(_ value: Int, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 11))
        }
        .foregroundStyle(Palette.onAccent)
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ActivitySheet: UIViewControllerRepresentable {
    let payload: SharePayload
    let completed: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: payload.items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, success, _, _ in DispatchQueue.main.async { completed(success) } }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

