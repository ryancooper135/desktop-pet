// Волна 32: мелкая подпись под круглой кнопкой ряда «Альбом · Автомат · Дом · Трюки · Игры» (слова — RoundCaption
// в Shared/PetPrefs.swift). У панели действий подписи были и раньше — теперь и у круглых кнопок над ней.

import SwiftUI

extension View {
    /// Подпись под кругом 48×48. Оверлей: размер кнопки и зона нажатия не меняются, место под подписью даёт ряд
    /// (RoundCaption.room). Кегль постоянный, как у остальных кнопок главного экрана (волна 15). VoiceOver её
    /// не читает: у кнопки уже есть своё имя, иначе слово прозвучало бы дважды.
    func roundCaption(_ text: String?) -> some View {
        overlay(alignment: .bottom) {
            if let text {
                Text(text)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.ink.opacity(0.85))
                    // Под рядом — комната: мягкий ореол цвета фона, чтобы слово читалось на любой стене.
                    .shadow(color: PetPalette.bg.opacity(0.9), radius: 1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 56)
                    .alignmentGuide(.bottom) { d in d[.top] - 2 }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
