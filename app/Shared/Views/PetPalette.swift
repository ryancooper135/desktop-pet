// Палитра стиля A (как в песочнице RESEARCH/mockups/sandbox): тёплая, мягкая, без чистого чёрного.

import SwiftUI
import UIKit
@preconcurrency import PetCore

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }

    /// Цвет, который сам меняется в тёмной теме.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { tc in
            let h = tc.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255,
                           blue: CGFloat(h & 0xff) / 255, alpha: 1)
        })
    }
}

enum PetPalette {
    static let ink = Color.dynamic(light: 0x4a3b33, dark: 0xf3ece6)
    static let soft = Color.dynamic(light: 0x8a7a70, dark: 0xb8a89e)
    static let bg = Color.dynamic(light: 0xf3ece6, dark: 0x2a2320)
    static let card = Color.dynamic(light: 0xfffaf5, dark: 0x3a302b)
    static let accent = Color(hex: 0xf08a5d)
    static let red = Color(hex: 0xe5534b)
    static let green = Color(hex: 0x74bf78)
    static let yellow = Color(hex: 0xf2bf4a)
    /// Фон 3D-сцены: сцена — «комната», а не UI, поэтому одинаковый в обеих темах.
    static let stageBg = Color(hex: 0xf6efe6)

    // Шерсть и мордочка: одинаковые в обеих темах.
    static let fur = Color(hex: 0xe39a55)
    static let furDark = Color(hex: 0xc97a3a)
    static let cream = Color(hex: 0xfbebd6)
    static let nose = Color(hex: 0x4a3b33)
    static let blush = Color(hex: 0xf4a0a0)
    static let tongue = Color(hex: 0xef7f8a)
    static let mouth = Color(hex: 0x8c3b3b)

    static func need(_ n: Need) -> Color {
        switch n {
        case .food: return Color(hex: 0xf0913a)
        case .clean: return Color(hex: 0x6f9fd8)
        case .energy: return Color(hex: 0xf2bf4a)
        case .fun: return Color(hex: 0x74bf78)
        case .love: return Color(hex: 0xef6a7a)
        case .walk: return Color(hex: 0x9b7fd8)
        case .look: return Color(hex: 0x4fb3a9)
        }
    }

    static func level(_ l: Int) -> Color {
        switch l {
        case 0: return Color(hex: 0x74bf78)
        case 1: return Color(hex: 0xf2bf4a)
        case 2: return Color(hex: 0xf0913a)
        default: return Color(hex: 0xe5534b)
        }
    }

    static func needIcon(_ n: Need) -> String {
        switch n {
        case .food: return "fork.knife"
        case .clean: return "drop"
        case .energy: return "bolt"
        case .fun: return "tennisball"
        case .love: return "heart"
        case .walk: return "figure.walk"
        case .look: return "sparkles"
        }
    }
}
