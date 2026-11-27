import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

struct Toast: Equatable {
    let text: String
    let undoEvent: UUID?
}

struct Candidate: Equatable {
    let personID: UUID
    let method: ContactMethod
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var data = AppData()
    @Published private(set) var ready = false
    @Published private(set) var loadFailed = false
    @Published private(set) var contacts: [String: ContactInfo] = [:]
    @Published var suggestions: [Suggestion] = []
    @Published var toast: Toast?
    @Published var candidate: Candidate?
    @Published var message: String?
    @Published private(set) var photoPrompt: ContactEvent?
    @Published private(set) var clock = Date()
    @Published private(set) var pendingFaceTime: Candidate?
    @Published private(set) var dialing = false

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    let arguments = ProcessInfo.processInfo.arguments
    var testing: Bool { arguments.contains("-ui-testing") }
    var expired: Bool { arguments.contains("-expired") }
    var calendar: Calendar { .current }
    var now: Date {
        if let fixed = Launch.value("-now").flatMap({ ISO8601DateFormatter.fixture.date(from: $0) }) {
            return fixed.addingTimeInterval(clock.timeIntervalSince(started))
        }
        return clock
    }

    private let started = Date()
    private var toastTask: Task<Void, Never>?
    private var reminderTask: Task<Void, Never>?
    private var leftForFaceTime = false
    private var photoLibraryRevision = UUID()
    private let reminders = ReminderService()
    let dialer = CallWatcher()

    let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeepClose", isDirectory: true)
    }()
    var photosDirectory: URL { directory.appendingPathComponent("photos", isDirectory: true) }
    private var file: URL { directory.appendingPathComponent("data.json") }

    init() {
        dialer.onConnected = { [weak self] person, session, date in
            Task { @MainActor in self?.record(person, method: .call, at: date, automatic: true, session: session) }
        }
    }


    func start() async {
        loadFailed = false
        clock = Date()
        do {
            try prepareDirectory()
            if testing && arguments.contains("-reset") { try? FileManager.default.removeItem(at: file) }
            if FileManager.default.fileExists(atPath: file.path) {
                data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: file))
            } else {
                data = AppData()
            }
            if testing, let seed = Launch.value("-seed") { try Seed.apply(seed, to: self) }
            clock = Date()
            if data.review.installedAt == nil {
                let created = try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate
                data.review.installedAt = min(created ?? now, now)
                data.review.records = max(data.review.records, data.events.count)
            }
            if data.review.lastRequest != nil, data.review.requestedVersions == nil {
                data.review.requested(Launch.legacyReviewVersion)
            }
            removeUnreferencedPhotos()
            persist()
            ready = true
            await refreshContacts()
            await loadSuggestions()
            persist()
        } catch {
            loadFailed = true
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
        for leftover in (try? FileManager.default.contentsOfDirectory(at: photosDirectory, includingPropertiesForKeys: nil)) ?? []
        where leftover.pathExtension == "tmp" {
            try? FileManager.default.removeItem(at: leftover)
        }
    }

    func activate() async {
        clock = Date()
        guard ready else { return }
        if leftForFaceTime {
            if let pendingFaceTime, person(pendingFaceTime.personID) != nil { candidate = pendingFaceTime }
            self.pendingFaceTime = nil
            leftForFaceTime = false
        }
        if let person = dialer.resume(now: now) { candidate = Candidate(personID: person, method: .call) }
        dialing = false
        await refreshContacts()
        persist()
    }

    func leaveApp() {
        if pendingFaceTime != nil { leftForFaceTime = true }
    }

    func replace(_ value: AppData) {
        data = value
    }

    @discardableResult
    private func persist() -> Bool { commit(data) }

    @discardableResult
    private func commit(_ snapshot: AppData) -> Bool {
        do {
            let bytes = try JSONEncoder().encode(snapshot)
            try bytes.write(to: file, options: .atomic)
        } catch {
            message = L.t("error.save")
            return false
        }
        if data != snapshot { data = snapshot }
        let showNames = snapshot.prefs.hideWidgetNames != true
        let cards = ordered.map { person in
            WidgetSnapshot.Card(id: person.id, name: showNames ? person.displayName : String(person.displayName.prefix(1)),
                                last: Schedule.lastEvent(person, snapshot.events)?.occurredAt,
                                created: person.createdAt, cycle: person.cycleDays)
        }
        try? WidgetSnapshot(cards: cards, showNames: showNames).write()
        WidgetCenter.shared.reloadAllTimelines()
        refreshReminders()
        return true
    }

    func refreshReminders() {
        let snapshot = data, now = now, calendar = calendar, testing = testing
        let previous = reminderTask
        previous?.cancel()
        reminderTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await reminders.reconcile(data: snapshot, now: now, calendar: calendar, testing: testing)
        }
    }


    var ordered: [Person] { Schedule.ordered(data.people, events: data.events, now: now, calendar: calendar) }

    func person(_ id: UUID) -> Person? { data.people.first { $0.id == id } }

    func standing(_ person: Person) -> Standing { Schedule.standing(person, events: data.events, now: now, calendar: calendar) }

    func events(of person: Person) -> [ContactEvent] {
        data.events.filter { $0.personID == person.id }.sorted { $0.occurredAt > $1.occurredAt }
    }

    func photos(of person: Person) -> [PhotoEntry] { Schedule.photos(of: person, in: data.photos) }

    func info(_ person: Person) -> ContactInfo? { person.contactID.flatMap { contacts[$0] } }

    func phones(_ person: Person) -> [String] {
        if let info = info(person), !info.phones.isEmpty { return info.phones }
        if person.contactID == nil, let phone = person.phone, phone.contains(where: \.isNumber) { return [phone] }
        return []
    }

    func avatar(_ person: Person) -> UIImage? { info(person)?.thumbnail.flatMap(UIImage.init(data:)) }

    func image(_ entry: PhotoEntry, thumbnail: Bool = true) -> UIImage? {
        let name = thumbnail ? PhotoFiles.thumbnailName(entry.file) : entry.file
        return UIImage(contentsOfFile: photosDirectory.appendingPathComponent(name).path)
            ?? UIImage(contentsOfFile: photosDirectory.appendingPathComponent(entry.file).path)
    }

    func statusLine(_ person: Person) -> String {
        let s = standing(person)
        guard let days = s.daysSince else { return L.t("status.never") }
        if days <= 0 { return L.t("status.today") }
        return L.f(days == 1 ? "status.days.one" : "status.days", days)
    }

    func lastLine(_ person: Person) -> String {
        guard let last = standing(person).last else { return L.t("status.no-record") }
        return L.f("status.last", L.day(last.occurredAt), last.method.label)
    }

    func dueLine(_ person: Person) -> String {
        let s = standing(person)
        if s.overdue > 0 { return L.f(s.overdue == 1 ? "due.over.one" : "due.over", s.overdue) }
        if s.overdue == 0 { return L.t("due.today") }
        return L.f(-s.overdue == 1 ? "due.in.one" : "due.in", -s.overdue)
    }

    func photoLine(_ latest: PhotoEntry?) -> String {
        guard let latest else { return L.t("photo.last.none") }
        let months = Schedule.months(from: latest.takenAt, to: now, calendar: calendar)
        return L.f(months == 1 ? "photo.last.months.one" : "photo.last.months", months)
    }

    var summaryLine: String {
        let list = data.people.map(standing)
        let over = list.filter { $0.overdue > 0 }.count, today = list.filter { $0.overdue == 0 }.count
        return L.f("home.summary", L.day(now, "MMMMdEEE"), over, today)
    }


    func record(_ personID: UUID, method: ContactMethod, at date: Date? = nil, automatic: Bool = false, session: UUID? = nil) {
        guard let index = data.people.firstIndex(where: { $0.id == personID }) else { return }
        if let session, data.events.contains(where: { $0.session == session }) { return }
        let event = ContactEvent(personID: personID, occurredAt: date ?? now, method: method, automatic: automatic, session: session)
        var snapshot = data
        snapshot.events.append(event)
        snapshot.review.records += 1
        snapshot.people[index].snoozedUntil = nil
        guard commit(snapshot) else { return }
        if candidate?.personID == personID { candidate = nil }
        if method == .visit, date == nil, snapshot.people[index].allowsPhotoPrompt(at: now, calendar: calendar) {
            photoPrompt = event
        }
        showToast(L.f(automatic ? "toast.auto" : "toast.saved", snapshot.people[index].displayName), undo: event.id)
    }

    func undo(_ eventID: UUID) {
        guard data.events.contains(where: { $0.id == eventID }) else { return }
        var snapshot = data
        snapshot.events.removeAll { $0.id == eventID }
        snapshot.review.records = max(0, snapshot.review.records - 1)
        guard commit(snapshot) else { return }
        if photoPrompt?.id == eventID { photoPrompt = nil }
        toast = nil
    }

    func updateEvent(_ event: ContactEvent) {
        guard let index = data.events.firstIndex(where: { $0.id == event.id }) else { return }
        data.events[index] = event
        persist()
    }

    func deleteEvent(_ id: UUID) {
        var snapshot = data
        snapshot.events.removeAll { $0.id == id }
        if commit(snapshot), photoPrompt?.id == id { photoPrompt = nil }
    }

    func showToast(_ text: String, undo: UUID? = nil) {
        toast = Toast(text: text, undoEvent: undo)
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    func save(_ person: Person) {
        if let index = data.people.firstIndex(where: { $0.id == person.id }) { data.people[index] = person }
        else { data.people.append(person) }
        persist()
    }

    func delete(_ person: Person) {
        var snapshot = data
        let photos = photos(of: person)
        snapshot.people.removeAll { $0.id == person.id }
        snapshot.events.removeAll { $0.personID == person.id }
        snapshot.photos.removeAll { $0.personID == person.id }
        if commit(snapshot) {
            if photoPrompt?.personID == person.id { photoPrompt = nil }
            for photo in photos { removeFiles(photo) }
        }
    }

    func newPerson(name: String, relation: Relation, contactID: String? = nil, phone: String? = nil,
                   usesContactName: Bool? = nil) -> Person {
        Person(nickname: name, relation: relation, cycleDays: data.prefs.cycle(for: relation), contactID: contactID,
               phone: phone, createdAt: now, customCycle: false, usesContactName: usesContactName)
    }

    func addSuggestions(_ picked: [Suggestion]) {
        for item in picked where !data.people.contains(where: { $0.contactID == item.id }) {
            let usesContactName = ![.mother, .father].contains(item.relation)
            var person = newPerson(name: usesContactName ? item.name : item.relation.callName,
                                   relation: item.relation, contactID: item.id, usesContactName: usesContactName)
            if let b = item.birthday { person.birthMonth = b.month; person.birthDay = b.day }
            data.people.append(person)
        }
        suggestions = []
        data.dismissedSuggestions = true
        persist()
        Task { await refreshContacts() }
    }

    func dismissSuggestions() {
        suggestions = []
        data.dismissedSuggestions = true
        persist()
    }

    func snooze(_ person: Person) {
        var value = person
        value.snoozedUntil = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        save(value)
        showToast(L.f("toast.snoozed", person.displayName))
    }

    func setPrefs(_ prefs: Preferences) {
        var snapshot = data
        for index in snapshot.people.indices where snapshot.people[index].customCycle == nil {
            snapshot.people[index].customCycle = snapshot.people[index].hasCustomCycle(in: data.prefs)
        }
        snapshot.prefs = prefs
        guard commit(snapshot) else { return }
        if prefs.remindersOn { Task { await reminders.requestIfNeeded() } }
    }

    func applyCode(_ prefs: Preferences) -> Bool {
        var snapshot = data
        snapshot.applySettingsCode(prefs)
        return commit(snapshot)
    }

    func markMilestone(_ key: String) {
        guard !data.milestones.contains(key) else { return }
        var snapshot = data
        snapshot.milestones.append(key)
        commit(snapshot)
    }

    var reviewReady: Bool { !testing && data.review.ready(at: Date(), version: Self.version) }

    func reserveReview() -> Bool {
        guard reviewReady else { return false }
        var snapshot = data
        snapshot.review.requested(Self.version)
        return commit(snapshot)
    }


    func dismissPhotoPrompt(for personID: UUID) {
        guard photoPrompt?.personID == personID,
              let index = data.people.firstIndex(where: { $0.id == personID }) else { return }
        var snapshot = data
        snapshot.people[index].photoPromptDismissedAt = now
        if commit(snapshot) { photoPrompt = nil }
    }

    func clearPhotoPrompt() { photoPrompt = nil }

    func addPhoto(_ bytes: Data, to personID: UUID, taken: Date? = nil) async {
        let id = UUID()
        let revision = photoLibraryRevision
        let directory = photosDirectory
        let fileDate = PhotoFiles.takenDate(bytes)
        let entry = PhotoEntry(id: id, personID: personID, takenAt: taken ?? fileDate ?? now,
                               dateFromFile: taken == nil && fileDate != nil, addedAt: now, file: id.uuidString + ".jpg")
        do {
            try await Task.detached(priority: .userInitiated) {
                try PhotoFiles.store(bytes, id: id, in: directory)
            }.value
        } catch {
            removeFiles(entry)
            message = L.t("error.photo")
            return
        }
        guard revision == photoLibraryRevision, person(personID) != nil else { removeFiles(entry); return }
        var snapshot = data
        snapshot.photos.append(entry)
        guard commit(snapshot) else { removeFiles(entry); return }
        if photoPrompt?.personID == personID { photoPrompt = nil }
    }

    func addPhoto(_ image: UIImage, to personID: UUID, taken: Date? = nil) async {
        guard let bytes = image.jpegData(compressionQuality: 0.9) else { message = L.t("error.photo"); return }
        await addPhoto(bytes, to: personID, taken: taken)
    }

    func setPhotoDate(_ entry: PhotoEntry, _ date: Date) {
        guard let index = data.photos.firstIndex(where: { $0.id == entry.id }) else { return }
        data.photos[index].takenAt = date
        data.photos[index].dateFromFile = false
        persist()
    }

    func deletePhoto(_ entry: PhotoEntry) {
        var snapshot = data
        snapshot.photos.removeAll { $0.id == entry.id }
        if commit(snapshot) { removeFiles(entry) }
    }

    private func removeFiles(_ entry: PhotoEntry) {
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(entry.file))
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(PhotoFiles.thumbnailName(entry.file)))
    }


    func exportBackup() async throws -> URL {
        let snapshot = data
        let source = photosDirectory
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(L.t("file.backup") + ".json")
        return try await Task.detached(priority: .userInitiated) {
            let photos = try Dictionary(snapshot.photos.map { entry -> (String, Data) in
                guard PhotoFiles.validName(entry.file) else { throw CocoaError(.fileReadCorruptFile) }
                return (entry.file, try Data(contentsOf: source.appendingPathComponent(entry.file)))
            }, uniquingKeysWith: { _, _ in throw CocoaError(.fileReadCorruptFile) })
            let archive = BackupArchive(data: snapshot, photoBytes: photos)
            try archive.validate()
            let bytes = try JSONEncoder().encode(archive)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do { try bytes.write(to: url, options: [.atomic, .completeFileProtection]) }
            catch { try? FileManager.default.removeItem(at: folder); throw error }
            return url
        }.value
    }

    func restoreBackup(_ archive: BackupArchive) async throws {
        try archive.validate()
        var snapshot = archive.data
        let originals = snapshot.photos.map(\.file)
        for index in snapshot.photos.indices { snapshot.photos[index].file = UUID().uuidString + ".jpg" }
        let staged = snapshot.photos
        let directory = photosDirectory
        do {
            try await Task.detached(priority: .userInitiated) {
                for (entry, original) in zip(staged, originals) {
                    guard let bytes = archive.photoBytes[original] else { throw CocoaError(.fileReadCorruptFile) }
                    try PhotoFiles.restore(bytes, file: entry.file, in: directory)
                }
            }.value
            snapshot.review = data.review
            snapshot.milestones = Set(snapshot.milestones).union(data.milestones).sorted()
            let dismissals = Dictionary(data.people.compactMap { person in
                person.photoPromptDismissedAt.map { (person.id, $0) }
            }, uniquingKeysWith: max)
            for index in snapshot.people.indices {
                if let dismissed = dismissals[snapshot.people[index].id],
                   dismissed > (snapshot.people[index].photoPromptDismissedAt ?? .distantPast) {
                    snapshot.people[index].photoPromptDismissedAt = dismissed
                }
            }
            let previous = data.photos
            guard commit(snapshot) else {
                message = nil
                throw CocoaError(.fileWriteUnknown)
            }
            photoLibraryRevision = UUID()
            for entry in previous { removeFiles(entry) }
            toast = nil
            candidate = nil
            pendingFaceTime = nil
            leftForFaceTime = false
            photoPrompt = nil
            dialer.cancel()
            dialing = false
            await refreshContacts()
            await loadSuggestions()
        } catch {
            for entry in staged { removeFiles(entry) }
            throw error
        }
    }

    private func removeUnreferencedPhotos() {
        let keep = Set(data.photos.flatMap { [$0.file, PhotoFiles.thumbnailName($0.file)] })
        for leftover in (try? FileManager.default.contentsOfDirectory(at: photosDirectory, includingPropertiesForKeys: nil)) ?? [] {
            let name = leftover.lastPathComponent
            if !keep.contains(name), PhotoFiles.validName(name.replacingOccurrences(of: "_t.jpg", with: ".jpg")) {
                try? FileManager.default.removeItem(at: leftover)
            }
        }
    }


    func refreshContacts() async {
        if testing { contacts = Seed.contacts(for: data.people); return }
        let ids = data.people.compactMap(\.contactID)
        guard !ids.isEmpty, ContactsService.authorized else { contacts = [:]; return }
        let found = await ContactsService.info(ids)
        contacts = found
        var changed = false
        for index in data.people.indices {
            guard let id = data.people[index].contactID, let info = found[id], let birthday = info.birthday,
                  data.people[index].birthMonth != birthday.month || data.people[index].birthDay != birthday.day else { continue }
            data.people[index].birthMonth = birthday.month
            data.people[index].birthDay = birthday.day
            changed = true
        }
        if changed { persist() }
    }

    func loadSuggestions() async {
        guard !data.dismissedSuggestions, data.people.isEmpty else { suggestions = []; return }
        if testing {
            suggestions = arguments.contains("-suggest") ? Seed.suggestions() : []
            return
        }
        guard ContactsService.authorized else { return }
        suggestions = await ContactsService.suggestions(excluding: Set(data.people.compactMap(\.contactID)))
    }

    func requestContacts() async {
        if testing { suggestions = Seed.suggestions(); return }
        let granted = await ContactsService.request()
        if granted { await loadSuggestions() }
        if !granted || suggestions.isEmpty { message = L.t(granted ? "contacts.none" : "contacts.denied") }
    }


    func call(_ person: Person, number: String? = nil) {
        guard let raw = number ?? phones(person).first else { message = L.t("call.no-number"); return }
        if testing {
            record(person.id, method: .call, automatic: true, session: UUID())
            return
        }
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard digits.contains(where: \.isNumber), let url = URL(string: "tel://" + digits) else { return }
        dialing = true
        dialer.begin(person: person.id, now: now)
        UIApplication.shared.open(url) { [weak self] ok in
            if !ok {
                Task { @MainActor in
                    self?.dialer.cancel()
                    self?.dialing = false
                }
            }
        }
    }

    func faceTime(_ person: Person) {
        let digits = phones(person).first?.filter { $0.isNumber || $0 == "+" } ?? ""
        guard digits.contains(where: \.isNumber), let url = URL(string: "facetime://" + digits) else {
            message = L.t("call.no-number")
            return
        }
        let next = Candidate(personID: person.id, method: .faceTime)
        dialer.cancel()
        dialing = false
        pendingFaceTime = next
        leftForFaceTime = false
        guard !testing else { return }
        UIApplication.shared.open(url) { [weak self] ok in
            guard !ok else { return }
            Task { @MainActor in
                if self?.pendingFaceTime == next { self?.pendingFaceTime = nil; self?.leftForFaceTime = false }
                if self?.candidate == next { self?.candidate = nil }
                self?.message = L.t("error.open")
            }
        }
    }

    func openExternal(_ person: Person, method: ContactMethod) {
        candidate = Candidate(personID: person.id, method: method)
        guard !testing else { return }
        let url: URL?
        switch method {
        case .wechat: url = URL(string: "weixin://")
        case .sms: url = phones(person).first.flatMap { URL(string: "sms:" + $0.filter { $0.isNumber || $0 == "+" }) }
        default: url = nil
        }
        guard let url else { return }
        UIApplication.shared.open(url) { [weak self] ok in
            if !ok { Task { @MainActor in self?.message = L.t(method == .wechat ? "wechat.missing" : "error.open") } }
        }
    }
}

extension ISO8601DateFormatter {
    static let fixture: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        formatter.timeZone = .current
        return formatter
    }()
}

enum PhotoFiles {
    static func thumbnailName(_ file: String) -> String {
        String(file.dropLast(4)) + "_t.jpg"
    }

    static func validName(_ file: String) -> Bool {
        file.hasSuffix(".jpg") && UUID(uuidString: String(file.dropLast(4))) != nil
    }

    static func takenDate(_ bytes: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    static func downscale(_ bytes: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.86)
    }

    static func store(_ bytes: Data, id: UUID, in directory: URL) throws {
        guard let full = downscale(bytes, maxPixel: 2400), let thumb = downscale(bytes, maxPixel: 480) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try write(full, thumbnail: thumb, file: id.uuidString + ".jpg", in: directory)
    }

    static func restore(_ bytes: Data, file: String, in directory: URL) throws {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let type = CGImageSourceGetType(source), type as String == UTType.jpeg.identifier,
              let thumb = downscale(bytes, maxPixel: 480)
        else { throw CocoaError(.fileReadCorruptFile) }
        try write(bytes, thumbnail: thumb, file: file, in: directory)
    }

    private static func write(_ full: Data, thumbnail: Data, file: String, in directory: URL) throws {
        try full.write(to: directory.appendingPathComponent(file), options: .atomic)
        try thumbnail.write(to: directory.appendingPathComponent(thumbnailName(file)), options: .atomic)
    }
}
