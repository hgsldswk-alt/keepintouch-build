import SwiftUI
import UIKit

@MainActor
enum Seed {
    private static var lang: String {
        let first = Locale.preferredLanguages.first ?? "en"
        if first.hasPrefix("zh-Hant") || first.hasPrefix("zh-TW") || first.hasPrefix("zh-HK") { return "hant" }
        return first.hasPrefix("zh") ? "hans" : "en"
    }

    private static func pick(_ hans: String, _ hant: String, _ en: String) -> String {
        switch lang {
        case "hans": return hans
        case "hant": return hant
        default: return en
        }
    }

    static let mom = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
    static let grandma = UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!
    static let friend = UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!
    static let dad = UUID(uuidString: "00000000-0000-0000-0000-00000000A004")!

    private static func date(_ text: String) -> Date {
        ISO8601DateFormatter.fixture.date(from: text + "T19:30:00") ?? Date()
    }

    static func apply(_ name: String, to model: AppModel) throws {
        guard name == "store" else { return }
        let created = date("2025-01-10")
        var data = AppData()
        data.dismissedSuggestions = true
        data.people = [
            Person(id: mom, nickname: pick("老妈", "老媽", "Mom"), relation: .mother,
                   note: pick("妈妈腰不好，记得问问", "媽媽腰不好，記得問問", "Ask how her back is doing"),
                   cycleDays: 7, contactID: "seed-mom", birthMonth: 3, birthDay: 8, createdAt: created, usesContactName: false),
            Person(id: grandma, nickname: pick("外婆", "外婆", "Grandma"), relation: .grandparent,
                   note: pick("问问她的花开了没", "問問她的花開了沒", "Ask about her garden"),
                   cycleDays: 14, contactID: "seed-grandma", createdAt: created.addingTimeInterval(60), usesContactName: false),
            Person(id: friend, nickname: pick("老许", "老許", "Alex"), relation: .friend,
                   note: pick("约他年底一起爬山", "約他年底一起爬山", "Plan a hike before New Year"),
                   cycleDays: 30, contactID: "seed-friend", createdAt: created.addingTimeInterval(120), usesContactName: false),
            Person(id: dad, nickname: pick("老爸", "老爸", "Dad"), relation: .father,
                   cycleDays: 7, contactID: "seed-dad", createdAt: created.addingTimeInterval(180), usesContactName: false)
        ]
        data.events = [
            ContactEvent(personID: mom, occurredAt: date("2026-10-18"), method: .visit),
            ContactEvent(personID: mom, occurredAt: date("2026-11-01"), method: .call),
            ContactEvent(personID: grandma, occurredAt: date("2026-10-31"), method: .call),
            ContactEvent(personID: friend, occurredAt: date("2026-10-25"), method: .wechat),
            ContactEvent(personID: dad, occurredAt: date("2026-11-20"), method: .call)
        ]
        let shots: [(UUID, String, Int)] = [(mom, "2024-02-10", 0), (mom, "2025-06-15", 1), (mom, "2026-02-17", 2),
                                             (friend, "2026-08-02", 3)]
        for (person, day, style) in shots {
            let id = UUID()
            guard let bytes = artwork(style).jpegData(compressionQuality: 0.9) else { continue }
            try PhotoFiles.store(bytes, id: id, in: model.photosDirectory)
            data.photos.append(PhotoEntry(id: id, personID: person, takenAt: date(day), dateFromFile: true,
                                          addedAt: date(day), file: id.uuidString + ".jpg"))
        }
        data.prefs.remindersOn = true
        model.replace(data)
    }

    static func contacts(for people: [Person]) -> [String: ContactInfo] {
        var result: [String: ContactInfo] = [:]
        let names = ["seed-mom": pick("王秀兰", "王秀蘭", "Linda Chen"), "seed-grandma": pick("李桂芳", "李桂芳", "Rose Miller"),
                     "seed-friend": pick("许然", "許然", "Alex Park"), "seed-dad": pick("陈建国", "陳建國", "David Chen")]
        for person in people {
            guard let id = person.contactID, let name = names[id] else { continue }
            result[id] = ContactInfo(name: name, phones: ["+1 555 0100"],
                                     thumbnail: id == "seed-grandma" ? portrait().jpegData(compressionQuality: 0.9) : nil)
        }
        return result
    }

    static func suggestions() -> [Suggestion] {
        [Suggestion(id: "seed-mom", name: pick("妈妈", "媽媽", "Mom"), relation: .mother),
         Suggestion(id: "seed-dad", name: pick("爸爸", "爸爸", "Dad"), relation: .father),
         Suggestion(id: "seed-grandma", name: pick("外婆", "外婆", "Grandma"), relation: .grandparent)]
    }

    static func sampleImage() -> UIImage { artwork(4) }

    static func artwork(_ style: Int) -> UIImage {
        let palettes: [(UIColor, UIColor, UIColor)] = [
            (UIColor(red: 0.98, green: 0.80, blue: 0.62, alpha: 1), UIColor(red: 0.93, green: 0.55, blue: 0.45, alpha: 1), UIColor(red: 0.55, green: 0.20, blue: 0.20, alpha: 1)),
            (UIColor(red: 0.72, green: 0.86, blue: 0.95, alpha: 1), UIColor(red: 0.98, green: 0.93, blue: 0.80, alpha: 1), UIColor(red: 0.30, green: 0.52, blue: 0.36, alpha: 1)),
            (UIColor(red: 0.99, green: 0.88, blue: 0.86, alpha: 1), UIColor(red: 0.96, green: 0.72, blue: 0.75, alpha: 1), UIColor(red: 0.40, green: 0.45, blue: 0.30, alpha: 1)),
            (UIColor(red: 0.80, green: 0.90, blue: 0.85, alpha: 1), UIColor(red: 0.95, green: 0.95, blue: 0.85, alpha: 1), UIColor(red: 0.20, green: 0.40, blue: 0.45, alpha: 1)),
            (Palette.paleUIColor, UIColor(red: 0.99, green: 0.90, blue: 0.80, alpha: 1), UIColor(red: 0.36, green: 0.23, blue: 0.17, alpha: 1))
        ]
        let (top, bottom, figure) = palettes[style % palettes.count]
        let size = CGSize(width: 1200, height: 900)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor.white.withAlphaComponent(0.75).setFill()
            cg.fillEllipse(in: CGRect(x: 860, y: 120, width: 170, height: 170))
            figure.withAlphaComponent(0.35).setFill()
            let hill = UIBezierPath()
            hill.move(to: CGPoint(x: 0, y: 700))
            hill.addCurve(to: CGPoint(x: 1200, y: 640), controlPoint1: CGPoint(x: 400, y: 520), controlPoint2: CGPoint(x: 800, y: 760))
            hill.addLine(to: CGPoint(x: 1200, y: 900))
            hill.addLine(to: CGPoint(x: 0, y: 900))
            hill.close()
            hill.fill()
            figure.setFill()
            for (x, h) in [(470.0, 1.0), (640.0, 0.9)] {
                let head = 120 * h
                cg.fillEllipse(in: CGRect(x: x, y: 380 + (1 - h) * 120, width: head, height: head))
                UIBezierPath(roundedRect: CGRect(x: x - 40, y: 380 + head + 10 + (1 - h) * 120, width: head + 80, height: 420),
                             cornerRadius: 90).fill()
            }
        }
    }

    static func portrait() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { context in
            Palette.paleUIColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
            Palette.accentUIColor.withAlphaComponent(0.8).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 80, y: 50, width: 80, height: 80))
            UIBezierPath(roundedRect: CGRect(x: 45, y: 140, width: 150, height: 140), cornerRadius: 70).fill()
        }
    }
}
