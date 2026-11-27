import Foundation

enum Relation: String, Codable, CaseIterable, Identifiable, Sendable {
    case mother, father, grandparent, sibling, child, friend, other

    var id: String { rawValue }
    var defaultCycle: Int {
        switch self {
        case .mother, .father, .child: return 7
        case .grandparent, .sibling: return 14
        case .friend, .other: return 30
        }
    }
    var isFamily: Bool { self != .friend && self != .other }
    var label: String { L.t("relation." + rawValue) }
    var callName: String { L.t("relation.call." + rawValue) }
    var codeLetter: Character {
        switch self {
        case .mother, .father: return "P"
        case .grandparent: return "G"
        case .sibling: return "S"
        case .child: return "K"
        case .friend: return "F"
        case .other: return "O"
        }
    }
}

enum ContactMethod: String, Codable, CaseIterable, Sendable {
    case call
    case faceTime = "facetime"
    case sms, wechat, visit, other

    var label: String { L.t("method." + rawValue) }
    var symbol: String {
        switch self {
        case .call: return "phone.fill"
        case .faceTime: return "video.fill"
        case .sms: return "message.fill"
        case .wechat: return "bubble.left.and.bubble.right.fill"
        case .visit: return "person.2.fill"
        case .other: return "checkmark"
        }
    }
}

struct ContactEvent: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var personID: UUID
    var occurredAt: Date
    var method: ContactMethod
    var automatic = false
    var session: UUID?
}

struct PhotoEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var personID: UUID
    var takenAt: Date
    var dateFromFile: Bool
    var addedAt: Date
    var file: String
}

struct Person: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var nickname: String
    var relation: Relation
    var note = ""
    var cycleDays: Int
    var contactID: String?
    var phone: String?
    var birthMonth: Int?
    var birthDay: Int?
    var snoozedUntil: Date?
    var extraHour: Int?
    var createdAt: Date
    var customCycle: Bool?
    var usesContactName: Bool?
    var movesReminderToWeekend: Bool?
    var photoPromptDismissedAt: Date?

    var displayName: String {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? relation.callName : name
    }

    func hasCustomCycle(in prefs: Preferences) -> Bool {
        customCycle ?? (cycleDays != prefs.cycle(for: relation))
    }

    func allowsPhotoPrompt(at now: Date, calendar: Calendar) -> Bool {
        guard let photoPromptDismissedAt,
              let resume = calendar.date(byAdding: .day, value: 30, to: photoPromptDismissedAt) else { return true }
        return now >= resume
    }

    var shareName: String {
        guard contactID == nil || usesContactName == false else { return relation.callName }
        let digits = displayName.filter(\.isNumber)
        return digits.count >= 5 ? relation.callName : displayName
    }
}

struct Preferences: Codable, Equatable, Sendable {
    var cycles: [String: Int] = Dictionary(uniqueKeysWithValues: Relation.allCases.map { ($0.rawValue, $0.defaultCycle) })
    var hour = 19
    var minute = 0
    var remindersOn = false
    var holidaysOn = true
    var hideWidgetNames: Bool?

    func cycle(for relation: Relation) -> Int { cycles[relation.rawValue] ?? relation.defaultCycle }
}

struct ReviewProgress: Codable, Equatable, Sendable {
    var records = 0
    var installedAt: Date?
    var lastRequest: Date?
    var requestedVersions: [String]?

    func ready(at now: Date, version: String) -> Bool {
        guard records >= 3, let installedAt, now.timeIntervalSince(installedAt) >= 3 * 86_400 else { return false }
        if let requestedVersions { return !requestedVersions.contains(version) }
        return lastRequest == nil
    }

    mutating func requested(_ version: String) {
        requestedVersions = (requestedVersions ?? []) + [version]
        lastRequest = nil
    }
}

struct AppData: Codable, Equatable, Sendable {
    var schema = 1
    var people: [Person] = []
    var events: [ContactEvent] = []
    var photos: [PhotoEntry] = []
    var prefs = Preferences()
    var review = ReviewProgress()
    var milestones: [String] = []
    var dismissedSuggestions = false

    mutating func applySettingsCode(_ imported: Preferences) {
        for index in people.indices {
            let custom = people[index].hasCustomCycle(in: prefs)
            people[index].customCycle = custom
            if !custom { people[index].cycleDays = imported.cycle(for: people[index].relation) }
        }
        prefs.cycles = imported.cycles
        prefs.hour = imported.hour
        prefs.minute = imported.minute
    }

    func showsPhotoMilestone(for person: Person) -> Bool {
        !milestones.contains(photoMilestoneKey(for: person)) && photos.filter { $0.personID == person.id }.count >= 3
    }

    func photoMilestoneKey(for person: Person) -> String { "three." + person.id.uuidString }
}

struct MonthlySummary {
    let people: [Person]
    let calls: Int
    let visits: Int
    let longest: (person: Person, days: Int)?

    init(data: AppData, now: Date, calendar: Calendar) {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let events = data.events.filter { $0.occurredAt <= now }
        let month = events.filter { $0.occurredAt >= start }
        let contacted = Set(month.map(\.personID))
        people = data.people.filter { contacted.contains($0.id) }
        calls = month.filter { $0.method == .call || $0.method == .faceTime }.count
        visits = month.filter { $0.method == .visit }.count

        let lastDates = Dictionary(events.map { ($0.personID, $0.occurredAt) }, uniquingKeysWith: max)
        longest = data.people.compactMap { person -> (person: Person, days: Int)? in
            guard let last = lastDates[person.id] else { return nil }
            return (person, Schedule.days(from: last, to: now, calendar: calendar))
        }.max { $0.days < $1.days }
    }
}

struct Standing: Equatable, Sendable {
    let last: ContactEvent?
    let due: Date
    let daysSince: Int?
    let overdue: Int
}

enum Schedule {
    static func lastEvent(_ person: Person, _ events: [ContactEvent]) -> ContactEvent? {
        events.filter { $0.personID == person.id }.max { $0.occurredAt < $1.occurredAt }
    }

    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    static func months(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return max(0, calendar.dateComponents([.month], from: startDay, to: endDay).month ?? 0)
    }

    static func isPhotoOlderThanSixMonths(_ takenAt: Date, now: Date, calendar: Calendar) -> Bool {
        let takenDay = calendar.startOfDay(for: takenAt)
        guard let anniversary = calendar.date(byAdding: .month, value: 6, to: takenDay) else { return false }
        return calendar.startOfDay(for: now) > anniversary
    }

    static func standing(_ person: Person, events: [ContactEvent], now: Date, calendar: Calendar) -> Standing {
        let last = lastEvent(person, events)
        let base = calendar.startOfDay(for: last?.occurredAt ?? person.createdAt)
        let due = last == nil ? base : (calendar.date(byAdding: .day, value: person.cycleDays, to: base) ?? base)
        return Standing(last: last, due: due,
                        daysSince: last.map { days(from: $0.occurredAt, to: now, calendar: calendar) },
                        overdue: days(from: due, to: now, calendar: calendar))
    }

    static func ordered(_ people: [Person], events: [ContactEvent], now: Date, calendar: Calendar) -> [Person] {
        let overdue = Dictionary(uniqueKeysWithValues: people.map {
            ($0.id, standing($0, events: events, now: now, calendar: calendar).overdue)
        })
        return people.enumerated().sorted { a, b in
            let x = overdue[a.element.id] ?? 0, y = overdue[b.element.id] ?? 0
            if x != y { return x > y }
            if a.element.createdAt != b.element.createdAt { return a.element.createdAt < b.element.createdAt }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func photos(of person: Person, in photos: [PhotoEntry]) -> [PhotoEntry] {
        photos.filter { $0.personID == person.id }.sorted {
            $0.takenAt == $1.takenAt ? $0.addedAt > $1.addedAt : $0.takenAt > $1.takenAt
        }
    }
}

struct DialAttempt: Equatable, Sendable {
    static let window: TimeInterval = 15 * 60
    let session = UUID()
    let personID: UUID
    let started: Date
    let before: Set<UUID>
    var matched: UUID?
    var consumed = false

    mutating func observe(call: UUID, outgoing: Bool, connected: Bool, at now: Date) -> Bool {
        guard !consumed, outgoing, !before.contains(call), now.timeIntervalSince(started) < Self.window else { return false }
        if matched == nil { matched = call }
        guard matched == call, connected else { return false }
        consumed = true
        return true
    }
}

enum Holidays {
    struct Occasion: Equatable, Sendable {
        let key: String
        let date: Date
    }

    static func gregorian(_ calendar: Calendar) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = calendar.timeZone
        return value
    }

    static func nthSunday(_ n: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        var parts = DateComponents(year: year, month: month, weekday: 1, weekdayOrdinal: n)
        parts.hour = 0
        return gregorian(calendar).date(from: parts)
    }

    static func lunar(month: Int, day: Int, after now: Date, calendar: Calendar) -> Date? {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = calendar.timeZone
        let start = calendar.startOfDay(for: now).addingTimeInterval(-1)
        return chinese.nextDate(after: start, matching: DateComponents(month: month, day: day), matchingPolicy: .nextTime)
            .map { calendar.startOfDay(for: $0) }
    }

    static func next(_ key: String, after now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let year = gregorian(calendar).component(.year, from: now)
        switch key {
        case "mothers", "fathers":
            let month = key == "mothers" ? 5 : 6, n = key == "mothers" ? 2 : 3
            for y in [year, year + 1] {
                if let d = nthSunday(n, month: month, year: y, calendar: calendar), d >= today { return d }
            }
            return nil
        case "spring": return lunar(month: 1, day: 1, after: now, calendar: calendar)
        case "midautumn": return lunar(month: 8, day: 15, after: now, calendar: calendar)
        default: return nil
        }
    }

    static func keys(for relation: Relation, chinese: Bool) -> [String] {
        var keys: [String] = []
        if relation == .mother { keys.append("mothers") }
        if relation == .father { keys.append("fathers") }
        if chinese && relation.isFamily { keys += ["spring", "midautumn"] }
        return keys
    }

    static func nextBirthday(month: Int, day: Int, after now: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: now).addingTimeInterval(-1)
        return gregorian(calendar).nextDate(after: start, matching: DateComponents(month: month, day: day), matchingPolicy: .nextTime)
            .map { calendar.startOfDay(for: $0) }
    }
}

enum SettingsCode {
    static let letters: [Character] = ["P", "G", "S", "K", "F", "O"]

    static func encode(_ prefs: Preferences) -> String {
        var text = "KL1."
        for letter in letters {
            let relation = Relation.allCases.first { $0.codeLetter == letter } ?? .other
            text += String(letter) + String(prefs.cycle(for: relation))
        }
        return text + String(format: "T%02d%02d", prefs.hour, prefs.minute)
    }

    static func decode(_ raw: String) -> Preferences? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard text.count <= 64, text.hasPrefix("KL1.") else { return nil }
        var body = Substring(text.dropFirst(4))
        var cycles: [Character: Int] = [:]
        for letter in letters {
            guard body.first == letter else { return nil }
            body = body.dropFirst()
            let digits = body.prefix { $0.isNumber }
            guard let value = Int(digits), (1...365).contains(value) else { return nil }
            cycles[letter] = value
            body = body.dropFirst(digits.count)
        }
        guard body.first == "T" else { return nil }
        let time = body.dropFirst()
        guard time.count == 4, time.allSatisfy(\.isNumber), let hour = Int(time.prefix(2)), let minute = Int(time.suffix(2)),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var prefs = Preferences()
        for relation in Relation.allCases { prefs.cycles[relation.rawValue] = cycles[relation.codeLetter] }
        prefs.hour = hour
        prefs.minute = minute
        return prefs
    }
}

enum RelationGuess {
    private static let rules: [(Relation, [String])] = [
        (.other, ["姑妈", "姨妈", "舅妈", "姑媽", "姨媽", "舅媽", "干妈", "乾媽", "婶", "嬸", "伯", "叔", "舅", "姑", "姨", "aunt", "uncle"]),
        (.grandparent, ["奶奶", "爷爷", "外婆", "外公", "姥姥", "姥爷", "爺爺", "姥爺", "grandma", "grandpa", "granny", "nana", "grandmother", "grandfather"]),
        (.mother, ["妈", "媽", "母亲", "母親", "母上", "mom", "mum", "mother", "mama", "mommy"]),
        (.father, ["爸", "父亲", "父親", "dad", "father", "papa", "daddy"]),
        (.sibling, ["姐", "哥", "弟", "妹", "sister", "brother", "sis", "bro"]),
        (.child, ["儿子", "女儿", "兒子", "女兒", "son", "daughter"])
    ]

    static func guess(_ text: String) -> Relation? {
        let lower = text.lowercased()
        let words = Set(lower.split { !$0.isLetter }.map(String.init))
        for (relation, keys) in rules {
            for key in keys {
                let ascii = key.allSatisfy(\.isASCII)
                if ascii ? words.contains(key) : lower.contains(key) { return relation }
            }
        }
        return nil
    }
}
