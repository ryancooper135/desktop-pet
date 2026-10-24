// Волна 5 на главном: кошелёк, «Открытка дня» и карточка «Вкус открыт!».
// Перенесено из HomeScreen.swift без изменений (волна 28).

import SwiftUI
import UIKit
@preconcurrency import PetCore

// MARK: - Волна 5: кошелёк, открытка, открытый вкус

/// Кошелёк у шестерёнки: «🪙 150 · 🎟 1», а с клочками — «… ✂️ 12» (волна 32; нет клочков — ✂️ не показываем,
/// чтобы ряд с именем не сжимался зря). Тап — автомат с капсулами.
struct WalletChip: View {
    let coins: Int
    let tickets: Int
    var shards: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("🪙").font(.system(size: 13))
                Text("\(coins)")
                    .contentTransition(.numericText(value: Double(coins)))
                Text("🎟").font(.system(size: 13))
                Text("\(tickets)")
                    .contentTransition(.numericText(value: Double(tickets)))
                if shards > 0 {
                    Text("✂️").font(.system(size: 12))
                    Text("\(shards)")
                        .contentTransition(.numericText(value: Double(shards)))
                }
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(PetPalette.ink)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Capsule().fill(PetPalette.card))
            .animation(.snappy, value: coins)
            .animation(.snappy, value: tickets)
            .animation(.snappy, value: shards)
        }
        .fixedSize()
        .buttonStyle(SquishStyle())
        // Подпись прямо у кнопки: один элемент «150 монет, 1 билетик». Обёртка accessibilityElement(children: .ignore)
        // давала вложенную вторую кнопку «🪙, 150, 🎟, 1», и VoiceOver читал картинки по отдельности.
        .accessibilityLabel(Text(EconText.wallet(coins: coins, tickets: tickets, shards: shards)))
        .accessibilityHint(Text("Кошелёк. Открыть автомат с капсулами"))
        .accessibilityIdentifier("open.wallet")
    }
}

/// «Открытка дня»: маленькая бумажка под верхним рядом, пока есть несохранённая открытка.
struct PostcardChip: View {
    let card: Postcard
    let action: () -> Void

    private var lastDay: Bool { Postcards.isLastDay(card, now: Clock.now()) }
    /// Для UI-тестов: есть ли у открытки снимок и каким способом он снят (ar/metal/window/fallback).
    private var photoValue: String {
        guard card.image != nil else { return "" }
        return "photo:" + (PostcardCamera.lastSource.isEmpty ? "disk" : PostcardCamera.lastSource)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(PetPalette.accent)
                Text("Открытка дня")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                if lastDay {
                    // Мягко: тем же акцентом, что конверт, без красного.
                    Text("· \(Postcards.lastDayChip)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: 0xfff6d8))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            )
            // Бумага всегда светлая.
            .environment(\.colorScheme, .light)
            .rotationEffect(.degrees(-2))
        }
        .buttonStyle(SquishStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text(lastDay ? "Открытка дня, \(Postcards.lastDayChip)" : "Открытка дня"))
        .accessibilityValue(Text(photoValue))
        .accessibilityIdentifier("postcard.card")
    }
}

/// «Вкус открыт!»: заметная карточка на пару секунд — значок вещи и строка альбома.
struct TasteOpenedCard: View {
    let fact: TasteFact

    var body: some View {
        HStack(spacing: 10) {
            Text(fact.emoji).font(.system(size: 30))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Вкус открыт!")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(fact.taste == .dislike ? PetPalette.soft : PetPalette.accent)
                Text(fact.text)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(PetPalette.card)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(fact.taste == .dislike ? PetPalette.soft.opacity(0.5) : PetPalette.accent, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("taste.opened")
    }
}
