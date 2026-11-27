import SwiftUI
import UIKit

struct PrimaryButton: ButtonStyle {
    var filled = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .actionStyle(filled: filled)
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.82 : 1)
    }
}

struct HeroCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 20)
                shape.fill(Palette.card)
                    .overlay {
                        shape.fill(LinearGradient(colors: [Palette.accent.opacity(colorScheme == .dark ? 0.18 : 0.46),
                                                           Palette.accent.opacity(0.10)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay { shape.strokeBorder(Palette.line, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
                    .allowsHitTesting(false)
            }
    }
}

struct IconBadge: View {
    let symbol: String
    var color: Color = Palette.accent
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }
}

struct IconTile: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            IconBadge(symbol: symbol, color: color, size: 36)
            Text(title).font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .cardStyle(padding: 8)
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct IconRow: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    var color: Color = Palette.accent
    var pill: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 0)
            if let pill { StatusPill(text: pill, color: color) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EmptyIllustration: View {
    var symbol = "person.2.fill"
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            IconBadge(symbol: "bubble.left.fill", color: Palette.mist, size: 34 * scale)
                .offset(x: -32 * scale, y: 14 * scale)
            IconBadge(symbol: symbol, color: Palette.accent, size: 62 * scale)
            IconBadge(symbol: "heart.fill", color: Palette.butter, size: 30 * scale)
                .offset(x: 35 * scale, y: -21 * scale)
        }
        .frame(width: 108 * scale, height: 78 * scale)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ContactAvatar: View {
    let image: UIImage?
    let person: Person
    let standing: Standing
    var size: CGFloat = 50

    var statusColor: Color {
        if standing.overdue > 0 { return Palette.accent }
        if standing.overdue == 0 { return Palette.butter }
        return standing.daysSince == 0 ? Palette.sage : Palette.mist
    }

    private var fraction: CGFloat {
        guard let days = standing.daysSince else { return 1 }
        return min(1, max(0, CGFloat(days) / CGFloat(max(1, person.cycleDays))))
    }

    var body: some View {
        ZStack {
            Circle().strokeBorder(Palette.line, lineWidth: 3)
            Circle().inset(by: 1.5).trim(from: 0, to: fraction)
                .stroke(statusColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Avatar(image: image, size: size, fill: statusColor)
        }
        .frame(width: size + 10, height: size + 10)
        .accessibilityHidden(true)
    }
}

extension ContactMethod {
    var iconColor: Color {
        switch self {
        case .call, .faceTime: return Palette.mist
        case .sms, .wechat: return Palette.sage
        case .visit: return Palette.butter
        case .other: return Palette.accent
        }
    }
}

extension View {
    func actionStyle(filled: Bool) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(filled ? Color.white : Palette.accentText)
            .background(filled ? Palette.action : Palette.pale, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    func sectionTitle() -> some View {
        self.font(.headline).foregroundStyle(Palette.muted).accessibilityAddTraits(.isHeader)
    }

    func artworkBorder() -> some View {
        overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.25), Palette.accent],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

struct Avatar: View {
    let image: UIImage?
    var size: CGFloat = 48
    var fill: Color = Palette.accent

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct PhotoTile: View {
    let image: UIImage?
    var height: CGFloat = 180

    var body: some View {
        Color.clear
            .frame(height: height)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Palette.pale }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.line, lineWidth: 1).allowsHitTesting(false) }
            .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
    }
}
