import SwiftUI
import WidgetKit

private struct Entry: TimelineEntry {
    let date: Date
    let cards: [WidgetSnapshot.Card]
    let showNames: Bool
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { sample() }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let entry = make(Date())
        completion(context.isPreview && entry.cards.isEmpty ? sample() : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let midnight = calendar.startOfDay(for: now)
        let dates = [now] + (1...3).compactMap { calendar.date(byAdding: .day, value: $0, to: midnight) }
        completion(Timeline(entries: dates.map(make), policy: .atEnd))
    }

    private func make(_ date: Date) -> Entry {
        let snapshot = WidgetSnapshot.read()
        let cards = snapshot?.ordered(now: date, calendar: .current) ?? []
        return Entry(date: date, cards: cards, showNames: snapshot?.showNames ?? true)
    }

    private func sample() -> Entry {
        let now = Date()
        return Entry(date: now, cards: [
            WidgetSnapshot.Card(id: UUID(), name: L.t("relation.call.mother"), last: now.addingTimeInterval(-12 * 86_400),
                                created: now, cycle: 7)
        ], showNames: true)
    }
}

private func line(_ card: WidgetSnapshot.Card, at date: Date, showNames: Bool) -> String {
    let daysSince = card.standing(now: date, calendar: .current).daysSince
    if !showNames {
        guard let days = daysSince else { return "—" }
        return L.f(days == 1 ? "widget.day-count.one" : "widget.day-count", max(0, days))
    }
    guard let days = daysSince else { return L.t("widget.never") }
    return days <= 0 ? L.t("status.today") : L.f("widget.days", days)
}

private func callURL(_ card: WidgetSnapshot.Card?) -> URL? {
    card.map { URL(string: "keepclose://call/" + $0.id.uuidString)! }
}

private struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            if let card = entry.cards.first {
                HStack(spacing: 6) {
                    if !entry.showNames { initial(card) }
                    VStack(alignment: .leading, spacing: 2) {
                        if entry.showNames { Label(card.name, systemImage: "phone.fill").font(.headline).lineLimit(1) }
                        Text(line(card, at: entry.date, showNames: entry.showNames)).font(.caption).lineLimit(1)
                    }
                }
                .privacySensitive()
                .widgetURL(callURL(card))
                .containerBackground(for: .widget) { Color.clear }
            } else {
                Text(L.t("widget.empty")).containerBackground(for: .widget) { Color.clear }
            }
        case .systemMedium:
            HStack(spacing: 8) {
                ForEach(entry.cards.prefix(3)) { card in
                    Link(destination: callURL(card)!) { tile(card) }
                }
                if entry.cards.isEmpty { Text(L.t("widget.empty")).font(.subheadline.weight(.semibold)) }
            }
            .foregroundStyle(Palette.onAccent)
            .containerBackground(for: .widget) { Palette.accent }
        default:
            Group {
                if let card = entry.cards.first { tile(card) } else {
                    Text(L.t("widget.empty")).font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(Palette.onAccent)
            .widgetURL(callURL(entry.cards.first))
            .containerBackground(for: .widget) { Palette.accent }
        }
    }

    private func tile(_ card: WidgetSnapshot.Card) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.showNames { Image(systemName: "phone.circle.fill").font(.title2) }
            else { initial(card) }
            Spacer(minLength: 2)
            if entry.showNames { Text(card.name).font(.headline).lineLimit(1).minimumScaleFactor(0.6) }
            Text(line(card, at: entry.date, showNames: entry.showNames))
                .font(.caption.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .privacySensitive()
    }

    private func initial(_ card: WidgetSnapshot.Card) -> some View {
        Text(String(card.name.prefix(1))).font(.headline)
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(0.18), in: Circle())
    }
}

@main
struct KeepCloseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: Provider()) { WidgetView(entry: $0) }
            .configurationDisplayName(L.t("widget.name"))
            .description(L.t("widget.description"))
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
