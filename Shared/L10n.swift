import Foundation

private final class LocalizationAnchor: NSObject {}

enum L {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle(for: LocalizationAnchor.self), comment: "")
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: args)
    }

    static func day(_ date: Date, _ template: String = "MMMd") -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static var chinese: Bool { (Locale.preferredLanguages.first ?? "").hasPrefix("zh") }
}
