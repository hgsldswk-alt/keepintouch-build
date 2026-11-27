import AppIntents
import Foundation

@MainActor
final class IntentRouter: ObservableObject {
    static let shared = IntentRouter()
    @Published var dial: UUID?
}

enum StoredPeople {
    static func load() -> [Person] {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let file = base.appendingPathComponent("KeepClose/data.json")
        guard let bytes = try? Data(contentsOf: file), let data = try? JSONDecoder().decode(AppData.self, from: bytes) else { return [] }
        return data.people
    }
}

struct PersonEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "intent.person")
    static var defaultQuery = PersonQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PersonQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PersonEntity] {
        StoredPeople.load().filter { identifiers.contains($0.id) }.map { PersonEntity(id: $0.id, name: $0.displayName) }
    }

    func entities(matching string: String) async throws -> [PersonEntity] {
        let key = string.lowercased()
        return StoredPeople.load().filter { $0.displayName.lowercased().contains(key) }
            .map { PersonEntity(id: $0.id, name: $0.displayName) }
    }

    func suggestedEntities() async throws -> [PersonEntity] {
        StoredPeople.load().map { PersonEntity(id: $0.id, name: $0.displayName) }
    }
}

struct CallPersonIntent: AppIntent {
    static var title: LocalizedStringResource = "intent.call.title"
    static var description = IntentDescription("intent.call.description")
    static var openAppWhenRun = true

    @Parameter(title: "intent.person")
    var person: PersonEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.dial = person.id
        return .result()
    }
}

struct KeepCloseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CallPersonIntent(),
                    phrases: ["Call \(\.$person) with \(.applicationName)",
                              "用\(.applicationName)打给\(\.$person)",
                              "用\(.applicationName)打給\(\.$person)"],
                    shortTitle: "intent.call.short",
                    systemImageName: "phone.fill")
    }
}
