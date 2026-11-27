import SwiftUI
import UIKit

enum Palette {
    private static let accentValue: UInt32 = 0xE8B89A
    private static let paleValue: UInt32 = 0xF6E3D6
    private static let darkAccentValue: UInt32 = 0xF0C4A8

    static let accentUIColor = srgb(accentValue)
    static let paleUIColor = srgb(paleValue)
    static let accent = Color(uiColor: accentUIColor)
    static let action = Color(uiColor: srgb(0x98583C))
    static let onAccent = Color(uiColor: srgb(0x1D110B))
    static let accentText = adaptive(0x88482F, darkAccentValue)
    static let sage = Color(uiColor: srgb(0x9CB89A))
    static let mist = Color(uiColor: srgb(0x8FA9C6))
    static let butter = Color(uiColor: srgb(0xF2D79B))
    static let paper = adaptive(0xF7F5F0, 0x241C18)
    static let ink = adaptive(0x1F2326, 0xFFF3EC)
    static let muted = adaptive(0x62564F, 0xD9C6B9)
    static let card = adaptive(0xFFFFFF, 0x332721)
    static let pale = adaptive(paleValue, 0x492F25)
    static let line = adaptive(0xE8DAD0, 0x634A3E)
    static let warm = adaptive(0xFBF3E6, 0x3D3027)

    static let artworkInk = Color(uiColor: srgb(0x1F2326))
    static let artworkPaper = Color(uiColor: srgb(0xFCF7F2))
    static let darkPanel = Color(uiColor: srgb(0x4A3025))
    static let onDarkPanel = Color(uiColor: srgb(0xFFF5EE))
    static let accentOnDarkPanel = Color(uiColor: srgb(darkAccentValue))

    private static func srgb(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            srgb(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
