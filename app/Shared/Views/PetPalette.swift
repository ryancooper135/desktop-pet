// Палитра. С волны 53 — стиль B «Стекло» (design/wave53): было тёплое A из песочницы RESEARCH/mockups/sandbox.

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
    // Волна 53: стиль B «Стекло» — холодная лаванда, чернила #1C1B29, акцент фиолетовый #6C5CE7.
    // Имена прежние, чтобы все экраны, виджеты и островок перешли на B без правок у себя.
    static let ink = Color.dynamic(light: 0x1c1b29, dark: 0xf2f0fa)
    static let soft = Color.dynamic(light: 0x6b6880, dark: 0xa9a6bc)
    static let bg = Color.dynamic(light: 0xefe8fb, dark: 0x1b1928)
    static let card = Color.dynamic(light: 0xffffff, dark: 0x2a2740)
    static let accent = Color(hex: 0x6c5ce7)
    static let red = Color(hex: 0xff4f7b)
    static let green = Color(hex: 0x22c59a)
    static let yellow = Color(hex: 0xffc54d)
    /// Фон 3D-сцены: сцена — «комната», а не UI, поэтому одинаковый в обеих темах.
    static let stageBg = Color(hex: 0xf6efe6)

    // Токены B (design/wave53/base.css): цвета действий, золото наград, тёмный островок.
    static let vio = Color(hex: 0x6c5ce7)
    static let food = Color(hex: 0xff9446)
    static let love = Color(hex: 0xff5e86)
    static let play = Color(hex: 0x22c59a)
    static let wash = Color(hex: 0x3ea7ff)
    static let gold = Color(hex: 0xffd46b)
    static let island = Color(hex: 0x0b0a12)
    static let islandMute = Color(hex: 0xa9a6bc)
    /// Стена комнаты в макетах: сверху голубая, книзу сиреневая (фон листов и двора).
    static let wallTop = Color.dynamic(light: 0xcfe0ff, dark: 0x1d2236)
    static let wallBottom = Color.dynamic(light: 0xe9ddfa, dark: 0x221c33)

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
        case .food: return food
        case .clean: return wash
        case .energy: return Color(hex: 0xffb92e)
        case .fun: return play
        case .love: return love
        case .walk: return Color(hex: 0x8b7cf6)
        case .look: return Color(hex: 0x2ec4b6)
        }
    }

    static func level(_ l: Int) -> Color {
        switch l {
        case 0: return Color(hex: 0x22c59a)
        case 1: return Color(hex: 0xf2b134)
        case 2: return Color(hex: 0xff8a3d)
        default: return red
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
