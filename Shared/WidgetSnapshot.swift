import Foundation

struct WidgetSnapshot: Codable {
    static let group = "group.com.hgsldswk.keepintouch"
    static let kind = "KeepCloseWidget"
    private static let filename = "keepclose-widget-v1.json"

    struct Card: Codable, Identifiable {
        let id: UUID
        let name: String
        let last: Date?
        let created: Date
        let cycle: Int

        func standing(now: Date, calendar: Calendar) -> Standing {
            let person = Person(id: id, nickname: name, relation: .other, cycleDays: cycle, createdAt: created)
            let events = last.map { [ContactEvent(personID: id, occurredAt: $0, method: .other)] } ?? []
            return Schedule.standing(person, events: events, now: now, calendar: calendar)
        }
    }

    let cards: [Card]
    let showNames: Bool

    static func read() -> Self? {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: directory.appendingPathComponent(filename)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write() throws {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent(Self.filename), options: .atomic)
    }

    func ordered(now: Date, calendar: Calendar) -> [Card] {
        cards.enumerated().sorted { a, b in
            let x = a.element.standing(now: now, calendar: calendar).overdue
            let y = b.element.standing(now: now, calendar: calendar).overdue
            return x == y ? a.offset < b.offset : x > y
        }.map(\.element)
    }
}
