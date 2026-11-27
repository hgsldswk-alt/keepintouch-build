import StoreKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PersonEditor: View {
    @ObservedObject var model: AppModel
    @ObservedObject var purchases: Purchases
    let person: Person?
    let finished: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relation: Relation = .mother
    @State private var cycle = 7
    @State private var customCycle = false
    @State private var note = ""
    @State private var phone = ""
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var extraHour: Int?
    @State private var movesReminderToWeekend = false
    @State private var unlocking = false
    @State private var confirmDelete = false

    private var linked: Bool { person?.contactID != nil }
    private var hasPro: Bool { purchases.hasPro(at: model.now) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.t("editor.name"), text: $name).accessibilityIdentifier("editor.name")
                    Picker(selection: Binding(get: { relation }, set: { newRelation in
                        relation = newRelation
                        if !customCycle { cycle = model.data.prefs.cycle(for: newRelation) }
                    })) {
                        ForEach(Relation.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label(L.t("editor.relation"), systemImage: "person.2")
                    }
                    Stepper(value: Binding(get: { cycle }, set: { newCycle in
                        cycle = newCycle
                        customCycle = true
                    }), in: 1...365) {
                        Label(L.f("editor.cycle", cycle), systemImage: "clock")
                    }
                    TextField(L.t("editor.note"), text: $note, axis: .vertical).accessibilityIdentifier("editor.note")
                }
                if !linked {
                    Section {
                        TextField(L.t("editor.phone"), text: $phone).keyboardType(.phonePad).accessibilityIdentifier("editor.phone")
                        Toggle(isOn: $hasBirthday) { Label(L.t("editor.birthday"), systemImage: "gift") }
                        if hasBirthday { DatePicker(L.t("editor.birthday.date"), selection: $birthday, displayedComponents: .date) }
                    }
                } else if let info = person.flatMap(model.info) {
                    Section(L.t("editor.linked")) {
                        Text(info.name)
                        ForEach(info.phones, id: \.self) { Text($0).foregroundStyle(Palette.muted) }
                    }
                }
                Section {
                    if hasPro {
                        Picker(L.t("editor.extra"), selection: $extraHour) {
                            Text(L.t("editor.extra.off")).tag(Int?.none)
                            ForEach([8, 10, 12, 15, 18, 20, 21], id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(Int?.some(hour))
                            }
                        }
                    } else {
                        Text(L.t("editor.extra.pro")).foregroundStyle(Palette.muted)
                    }
                    Toggle(isOn: hasPro ? $movesReminderToWeekend : .constant(person?.movesReminderToWeekend == true)) {
                        Label(L.t("editor.weekend"), systemImage: "calendar")
                    }
                    .disabled(!hasPro)
                    .accessibilityIdentifier("editor.weekend")
                    if !hasPro {
                        Button { unlocking = true } label: {
                            IconRow(title: L.t("more.unlock"), symbol: "sparkles", color: Palette.butter)
                        }
                        .accessibilityIdentifier("editor.unlock")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("editor.extra.footer"))
                        Text(L.t("editor.weekend.footer"))
                    }
                }
                if person != nil {
                    Section {
                        Button(L.t("editor.delete"), role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .tint(Palette.accentText)
            .navigationTitle(L.t(person == nil ? "add.manual" : "common.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.save")) { save() }.accessibilityIdentifier("editor.save")
                }
            }
            .confirmationDialog(L.t("editor.delete.confirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L.t("editor.delete"), role: .destructive) {
                    if let person { model.delete(person) }
                    finished(true)
                    dismiss()
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $unlocking) { PaywallView(purchases: purchases, now: model.now) }
        }
    }

    private func load() {
        guard let person else {
            relation = .mother
            cycle = model.data.prefs.cycle(for: .mother)
            return
        }
        name = person.nickname
        relation = person.relation
        cycle = person.cycleDays
        customCycle = person.hasCustomCycle(in: model.data.prefs)
        note = person.note
        phone = person.phone ?? ""
        extraHour = person.extraHour
        movesReminderToWeekend = person.movesReminderToWeekend == true
        if let month = person.birthMonth, let day = person.birthDay {
            hasBirthday = true
            birthday = Calendar.current.date(from: DateComponents(year: 2000, month: month, day: day)) ?? Date()
        }
    }

    private func save() {
        var value = person ?? model.newPerson(name: "", relation: relation)
        let nickname = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if linked, nickname != value.nickname {
            value.usesContactName = model.info(value)?.name.caseInsensitiveCompare(nickname) == .orderedSame
        }
        value.nickname = nickname
        value.relation = relation
        value.cycleDays = cycle
        value.customCycle = customCycle
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasPro {
            value.extraHour = extraHour
            value.movesReminderToWeekend = movesReminderToWeekend
        }
        if !linked {
            let digits = phone.trimmingCharacters(in: .whitespacesAndNewlines)
            value.phone = digits.isEmpty ? nil : digits
            if hasBirthday {
                let parts = Calendar.current.dateComponents([.month, .day], from: birthday)
                value.birthMonth = parts.month
                value.birthDay = parts.day
            } else {
                value.birthMonth = nil
                value.birthDay = nil
            }
        }
        model.save(value)
        finished(false)
        dismiss()
    }
}

struct MoreView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var purchases: Purchases
    let unlock: () -> Void
    let summary: () -> Void
    let importCode: (Preferences) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var prefs = Preferences()
    @State private var initialPrefs: Preferences?
    @State private var code = ""
    @State private var time = Date()
    @State private var backupBusy = false
    @State private var chooseBackup = false
    @State private var previewBackup = false
    @State private var pendingBackup: BackupArchive?
    @State private var backupPayload: SharePayload?
    @State private var backupURL: URL?
    @State private var notice: String?

    private var backupFixture: Bool { model.testing && model.arguments.contains("-backup-fixture") }

    var body: some View {
        NavigationStack {
            Form {
                Section(L.t("more.reminders")) {
                    Toggle(isOn: $prefs.remindersOn) { Label(L.t("more.reminders.on"), systemImage: "bell") }
                        .accessibilityIdentifier("more.reminders")
                    DatePicker(selection: $time, displayedComponents: .hourAndMinute) {
                        Label(L.t("more.reminders.time"), systemImage: "clock")
                    }
                    Toggle(isOn: $prefs.holidaysOn) { Label(L.t("more.holidays"), systemImage: "calendar") }
                }
                Section {
                    ForEach(Relation.allCases) { relation in
                        Stepper(L.f("more.cycle.row", relation.label, prefs.cycle(for: relation)),
                                value: Binding(get: { prefs.cycle(for: relation) },
                                               set: { prefs.cycles[relation.rawValue] = $0 }), in: 1...365)
                    }
                } header: { Text(L.t("more.cycles")) } footer: { Text(L.t("more.cycles.footer")) }
                Section(L.t("more.share")) {
                    Button(action: summary) {
                        IconRow(title: L.t("more.summary"), symbol: "chart.bar.fill", color: Palette.butter)
                    }
                    .accessibilityIdentifier("more.summary")
                    Button {
                        UIPasteboard.general.string = SettingsCode.encode(currentPrefs)
                        model.showToast(L.t("more.copied"))
                    } label: {
                        IconRow(title: L.t("more.copy-code"), symbol: "doc.on.doc", color: Palette.sage)
                    }
                    .accessibilityIdentifier("more.copy-code")
                    if let file = settingsFile() {
                        ShareLink(item: file) {
                            IconRow(title: L.t("more.share-file"), symbol: "square.and.arrow.up", color: Palette.mist)
                        }
                    }
                }
                Section(L.t("import.title")) {
                    Button { validateCode(UIPasteboard.general.string ?? "") } label: {
                        IconRow(title: L.t("more.paste-code"), symbol: "doc.on.clipboard", color: Palette.mist)
                    }
                        .accessibilityIdentifier("more.paste-code")
                    HStack {
                        TextField(L.t("more.code.placeholder"), text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("more.code")
                        Button {
                            validateCode(code)
                        } label: {
                            Label(L.t("more.import"), systemImage: "arrow.down.circle")
                        }
                        .disabled(code.isEmpty)
                        .accessibilityIdentifier("more.import")
                    }
                }
                Section(L.t("more.widget")) {
                    Toggle(isOn: Binding(get: { prefs.hideWidgetNames == true }, set: { hide in
                        prefs.hideWidgetNames = hide
                        commit()
                    })) {
                        Label(L.t("more.widget.hide-names"), systemImage: "lock")
                    }
                    .accessibilityIdentifier("more.widget.hide-names")
                }
                Section {
                    Button { exportBackup() } label: {
                        IconRow(title: L.t("backup.export"), symbol: "square.and.arrow.up", color: Palette.sage)
                    }
                        .accessibilityIdentifier("backup.export")
                    Button {
                        if backupFixture, let backupURL { readBackup(backupURL) }
                        else { chooseBackup = true }
                    } label: {
                        IconRow(title: L.t("backup.restore"), symbol: "arrow.clockwise", color: Palette.butter)
                    }
                    .accessibilityIdentifier("backup.restore")
                    if backupBusy { ProgressView() }
                    if backupFixture && backupURL != nil {
                        Text(L.t("backup.export")).accessibilityIdentifier("backup.exported")
                    }
                } header: {
                    Text(L.t("backup.title"))
                } footer: {
                    Text(L.t("backup.privacy"))
                }
                Section(L.t("more.purchase")) {
                    Text(purchaseStatus).foregroundStyle(Palette.muted)
                    if !purchases.hasPro(at: model.now) || !(purchases.entitlement?.purchasedPro ?? false) {
                        if !Launch.isFree {
                            Button(action: unlock) {
                                IconRow(title: L.t("more.unlock"), symbol: "sparkles", color: Palette.butter)
                            }
                            .accessibilityIdentifier("more.unlock")
                        }
                    }
                    if !Launch.isFree {
                        Button { Task { await purchases.restore() } } label: {
                            IconRow(title: L.t("more.restore"), symbol: "arrow.clockwise", color: Palette.mist)
                        }
                    }
                }
                Section(L.t("more.about")) {
                    Text(L.t("more.calllog")).font(.footnote).foregroundStyle(Palette.muted)
                    Text(L.t("more.privacy")).font(.footnote).foregroundStyle(Palette.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .tint(Palette.accentText)
            .disabled(backupBusy)
            .navigationTitle(L.t("home.more"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.done")) { commit(); dismiss() }
                        .disabled(backupBusy)
                        .accessibilityIdentifier("more.done")
                }
            }
            .onAppear { if initialPrefs == nil { loadPreferences() } }
            .onDisappear { commit(); cleanBackupExport() }
            .interactiveDismissDisabled(backupBusy)
            .fileImporter(isPresented: $chooseBackup, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): readBackup(url)
                case .failure: notice = L.t("backup.invalid")
                }
            }
            .sheet(item: $backupPayload, onDismiss: cleanBackupExport) { item in
                ActivitySheet(payload: item) { _ in backupPayload = nil }
            }
            .sheet(isPresented: $previewBackup, onDismiss: { pendingBackup = nil }) {
                if let pendingBackup {
                    BackupPreview(archive: pendingBackup) {
                        previewBackup = false
                        restoreBackup(pendingBackup)
                    }
                    .presentationDetents([.medium])
                }
            }
            .alert(L.t("notice.title"), isPresented: Binding(
                get: { notice != nil || purchases.message != nil },
                set: { if !$0 { notice = nil; purchases.message = nil } }
            )) {
                Button(L.t("common.ok"), role: .cancel) { notice = nil; purchases.message = nil }
            } message: { Text(notice ?? purchases.message ?? "") }
        }
    }

    private var purchaseStatus: String {
        if Launch.isFree { return L.t("purchase.free") }
        guard let e = purchases.entitlement else { return "" }
        if e.purchasedPro { return L.t("purchase.owned") }
        if e.hasPro(at: model.now) { return L.f("purchase.trial", e.trialDaysLeft(at: model.now)) }
        return L.t("purchase.expired")
    }

    private var currentPrefs: Preferences {
        var value = prefs
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        value.hour = parts.hour ?? 19
        value.minute = parts.minute ?? 0
        return value
    }

    private func loadPreferences() {
        prefs = model.data.prefs
        initialPrefs = prefs
        time = Calendar.current.date(bySettingHour: prefs.hour, minute: prefs.minute, second: 0, of: Date()) ?? Date()
    }

    private func commit() {
        guard let initialPrefs, currentPrefs != initialPrefs else { return }
        model.setPrefs(currentPrefs)
        if model.data.prefs == currentPrefs { self.initialPrefs = currentPrefs }
    }

    private func validateCode(_ input: String) {
        guard let value = SettingsCode.decode(input) else { notice = L.t("import.invalid"); return }
        commit()
        importCode(value)
    }

    private func exportBackup() {
        cleanBackupExport()
        commit()
        backupBusy = true
        Task {
            defer { backupBusy = false }
            do {
                let url = try await model.exportBackup()
                backupURL = url
                if !backupFixture { backupPayload = SharePayload(items: [url]) }
            } catch { notice = L.t("backup.export-error") }
        }
    }

    private func readBackup(_ url: URL) {
        backupBusy = true
        Task {
            defer { backupBusy = false }
            do {
                pendingBackup = try await Task.detached(priority: .userInitiated) { try BackupArchive.read(url) }.value
                previewBackup = true
            } catch { notice = L.t("backup.invalid") }
        }
    }

    private func restoreBackup(_ archive: BackupArchive) {
        backupBusy = true
        Task {
            defer { backupBusy = false }
            do {
                try await model.restoreBackup(archive)
                loadPreferences()
                model.showToast(L.t("backup.done"))
                dismiss()
            } catch { notice = L.t("backup.restore-error") }
        }
    }

    private func cleanBackupExport() {
        if let backupURL {
            try? FileManager.default.removeItem(at: backupURL.deletingLastPathComponent())
            self.backupURL = nil
        }
    }

    private func settingsFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(L.t("file.settings") + ".keepclose")
        do { try SettingsCode.encode(currentPrefs).write(to: url, atomically: true, encoding: .utf8); return url }
        catch { return nil }
    }
}

struct BackupPreview: View {
    let archive: BackupArchive
    let restore: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HeroCard {
                    VStack(alignment: .leading, spacing: 10) {
                        IconBadge(symbol: "archivebox.fill", color: Palette.mist)
                        Text(L.t("backup.preview")).font(.title2.bold())
                        Text(L.f("backup.counts", archive.data.people.count, archive.data.events.count, archive.data.photos.count))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .accessibilityIdentifier("backup.counts")
                        Text(L.t("backup.replace")).font(.footnote).foregroundStyle(Palette.muted)
                    }
                }
                Button(action: restore) { Label(L.t("backup.confirm"), systemImage: "arrow.down.circle.fill") }
                    .buttonStyle(PrimaryButton())
                    .accessibilityIdentifier("backup.confirm")
                Button { dismiss() } label: { Label(L.t("common.cancel"), systemImage: "xmark") }
                    .buttonStyle(PrimaryButton(filled: false))
            }
            .padding(22)
        }
        .background(Palette.paper.ignoresSafeArea())
    }
}

struct ImportPreview: View {
    let prefs: Preferences
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HeroCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("import.title")).font(.title2.bold())
                        Text(Self.describe(prefs)).font(.body).accessibilityIdentifier("import.summary")
                        Text(L.t("import.note")).font(.footnote).foregroundStyle(Palette.muted)
                    }
                }
                Button { apply(); dismiss() } label: { Label(L.t("import.apply"), systemImage: "arrow.down.circle.fill") }
                    .buttonStyle(PrimaryButton())
                    .accessibilityIdentifier("import.apply")
                Button { dismiss() } label: { Label(L.t("common.cancel"), systemImage: "xmark") }
                    .buttonStyle(PrimaryButton(filled: false))
            }
            .padding(22)
        }
        .background(Palette.paper.ignoresSafeArea())
    }

    static func describe(_ prefs: Preferences) -> String {
        let groups: [Relation] = [.mother, .grandparent, .sibling, .child, .friend, .other]
        let parts = groups.map { relation -> String in
            let label = relation == .mother ? L.t("relation.parents") : relation.label
            return L.f("import.every", label, prefs.cycle(for: relation))
        }
        let time = Calendar.current.date(bySettingHour: prefs.hour, minute: prefs.minute, second: 0, of: Date()) ?? Date()
        return parts.joined(separator: " · ") + " · " + time.formatted(date: .omitted, time: .shortened)
    }
}

struct PaywallView: View {
    @ObservedObject var purchases: Purchases
    let now: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HeroCard {
                        VStack(alignment: .leading, spacing: 8) {
                            EmptyIllustration(symbol: "heart.text.square.fill", scale: 0.8)
                            Text(L.t("paywall.title")).font(.title2.bold()).accessibilityIdentifier("paywall.title")
                            Text(L.t("paywall.body")).font(.body).foregroundStyle(Palette.muted)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(["paywall.f1", "paywall.f2", "paywall.f3"], id: \.self) { key in
                            IconRow(title: L.t(key), symbol: "checkmark", color: Palette.sage)
                        }
                    }
                    .cardStyle()
                    Text(L.t("paywall.free")).font(.footnote).foregroundStyle(Palette.muted)
                    if let product = purchases.products.first(where: { $0.id == purchases.proID }) {
                        Button { Task { await purchases.purchase(product) } } label: {
                            Label(L.f("paywall.buy", product.displayPrice), systemImage: "sparkles")
                        }
                            .buttonStyle(PrimaryButton())
                            .disabled(purchases.busy)
                    } else if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                        Button {} label: {
                            Label(L.f("paywall.buy", L.t("paywall.price.sample")), systemImage: "sparkles")
                        }
                        .buttonStyle(PrimaryButton())
                    } else {
                        Button {} label: { Label(L.t("paywall.buy.loading"), systemImage: "clock") }
                            .buttonStyle(PrimaryButton()).disabled(true)
                    }
                    if let entitlement = purchases.entitlement, !entitlement.purchasedPro, entitlement.hasPro(at: now),
                       entitlement.trialClaimedAt == nil,
                       let trial = purchases.products.first(where: { $0.id == purchases.trialID }), trial.price == 0 {
                        Button { Task { await purchases.purchase(trial) } } label: {
                            Label(L.t("paywall.trial-receipt"), systemImage: "doc.text")
                        }
                            .buttonStyle(PrimaryButton(filled: false))
                            .disabled(purchases.busy)
                    }
                    Button { Task { await purchases.restore() } } label: {
                        Label(L.t("more.restore"), systemImage: "arrow.clockwise")
                    }
                        .buttonStyle(PrimaryButton(filled: false))
                        .accessibilityIdentifier("paywall.restore")
                    Text(L.t("paywall.once")).font(.caption).foregroundStyle(Palette.muted)
                }
                .padding(22)
            }
            .background(Palette.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.close")) { dismiss() }.accessibilityIdentifier("paywall.close")
                }
            }
            .task { await purchases.loadProducts() }
            .onChange(of: purchases.entitlement?.purchasedPro) { _, value in if value == true { dismiss() } }
            .alert(L.t("notice.title"), isPresented: Binding(get: { purchases.message != nil }, set: { if !$0 { purchases.message = nil } })) {
                Button(L.t("common.ok"), role: .cancel) { purchases.message = nil }
            } message: { Text(purchases.message ?? "") }
        }
    }
}
