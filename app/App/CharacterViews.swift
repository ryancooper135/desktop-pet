// Альбом: «Характер» — три оси черт с полюсами и метка, где пёс сейчас; «Помню» — воспоминания, новые сверху.
// Логика — Traits и Memories (app/Shared), здесь только вид. Id — album.character и album.memories.

import SwiftUI

/// «Характер»: пока ухода за неделю мало — «складывается N из 12», метки посерединке.
struct CharacterSection: View {
    let scores: [TraitScore]?
    let summary: String?
    let done: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Характер")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("за неделю")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
            }
            // Пока характер складывается — это пояснение, а не итог: кегль как у подписей соседних разделов
            // («Пока пусто. Отпусти на прогулку…»), иначе два серых абзаца крупнее заголовков осей.
            Text(headline)
                .font(.system(size: scores == nil ? 13 : 15, weight: scores == nil ? .medium : .semibold, design: .rounded))
                .foregroundStyle(scores == nil ? PetPalette.soft : PetPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("album.character.summary")
            VStack(spacing: 12) {
                ForEach(TraitAxis.allCases, id: \.self) { axis in
                    TraitAxisRow(axis: axis, score: scores?.first { $0.axis == axis })
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card))
            .opacity(scores == nil ? 0.6 : 1)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("album.character")
    }

    private var headline: String {
        if scores == nil {
            return "Складывается: \(min(done, Traits.minActs)) из \(Traits.minActs) дел. Гладь, играй, гуляй и купай — сам покажет, какой он."
        }
        return summary ?? "Ровный характер — всего понемногу"
    }
}

/// Ось: полюса по краям, метка там, где пёс. Видимая черта — подсвечена, под осью — пояснение.
struct TraitAxisRow: View {
    let axis: TraitAxis
    let score: TraitScore?

    var body: some View {
        let s = score?.score ?? 0
        let lit = score?.trait
        VStack(spacing: 5) {
            HStack {
                pole(axis.minus, lit: lit == axis.minus)
                Spacer(minLength: 8)
                pole(axis.plus, lit: lit == axis.plus)
            }
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(PetPalette.soft.opacity(0.18))
                    // Середина шкалы.
                    Rectangle().fill(PetPalette.soft.opacity(0.35))
                        .frame(width: 2, height: 10)
                        .offset(x: w / 2 - 1)
                    Circle()
                        .fill(lit == nil ? PetPalette.soft : PetPalette.accent)
                        .frame(width: 14, height: 14)
                        .offset(x: (w - 14) * CGFloat((s + 1) / 2))
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            if let lit {
                Text(lit.hint)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .frame(maxWidth: .infinity, alignment: lit == axis.plus ? .trailing : .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(axis.minus.title) — \(axis.plus.title)"))
        .accessibilityValue(Text(score?.title ?? "посерединке"))
        .accessibilityIdentifier("album.trait.\(axis.rawValue)")
    }

    private func pole(_ t: Trait, lit: Bool) -> some View {
        Text("\(t.emoji) \(t.title)")
            .font(.system(size: 13, weight: lit ? .bold : .medium, design: .rounded))
            .foregroundStyle(lit ? PetPalette.ink : PetPalette.soft)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// «Помню»: значок, событие и дата. Знакомство — всегда последним.
struct MemoriesSection: View {
    let rows: [MemoryRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Помню")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("\(rows.count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
            }
            if rows.count <= 1 {
                Text("Первая прогулка, первый трюк, рекорды — всё яркое он запомнит и иногда будет вспоминать.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    HStack(spacing: 10) {
                        Text(row.emoji).font(.system(size: 22))
                            .frame(width: 34)
                        Text(row.text)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(PetPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Text(row.date)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(PetPalette.soft)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(row.text), \(row.date)"))
                    .accessibilityIdentifier("album.memory.\(row.id)")
                    if i < rows.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card))
        }
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("album.memories")
    }
}
