import Foundation

struct BackupArchive: Codable, Sendable {
    let format: String
    let version: Int
    let data: AppData
    let photoBytes: [String: Data]

    init(data: AppData, photoBytes: [String: Data]) {
        var portable = data
        portable.review = ReviewProgress()
        self.format = "keepclose-backup"
        self.version = 1
        self.data = portable
        self.photoBytes = photoBytes
    }

    static func read(_ url: URL) throws -> Self {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let archive = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try archive.validate()
        return archive
    }

    func validate() throws {
        let people = Set(data.people.map(\.id))
        let filenames = Set(data.photos.map(\.file))
        guard format == "keepclose-backup", version == 1, data.schema == 1,
              people.count == data.people.count,
              Set(data.events.map(\.id)).count == data.events.count,
              Set(data.photos.map(\.id)).count == data.photos.count,
              filenames.count == data.photos.count, filenames == Set(photoBytes.keys),
              data.people.allSatisfy({ (1...365).contains($0.cycleDays) && ($0.extraHour.map { (0...23).contains($0) } ?? true) }),
              data.events.allSatisfy({ people.contains($0.personID) }),
              data.photos.allSatisfy({ people.contains($0.personID) && PhotoFiles.validName($0.file) }),
              photoBytes.values.allSatisfy({ !$0.isEmpty }),
              data.prefs.cycles.values.allSatisfy({ (1...365).contains($0) }),
              (0...23).contains(data.prefs.hour), (0...59).contains(data.prefs.minute)
        else { throw CocoaError(.fileReadCorruptFile) }
    }
}
