// Волна 39 C: лист «Достижения» — открывается из листа «Уровень» (карточка «Достижения · 4 из 25»).
// Сверху «Получено N из M» с полоской; ниже карточки: полученные — ярко, с датой; неполученные — тускло,
// с прогрессом «3 / 7» и полоской. Награда «+5 ✂️» у каждой. Логика и тексты — Achievements (Shared), тут только вид.
// Только чтение: ничего не пишет (платит Shards.settle).

import SwiftUI
@preconcurrency import PetCore

struct AchievementsSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let f = model.file {
                    let rows = Achievements.rows(f)
                    header(f, rows)
                    ForEach(rows) { r in
                        AchievementCard(row: r)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("achieve.sheet")
    }

    private func header(_ f: SaveFile, _ rows: [AchievementRow]) -> some View {
        let got = rows.filter(\.got).count
        return VStack(spacing: 8) {
            HStack {
                Spacer()
                SheetCloseButton(id: "achieve.close")
            }
            Text("Достижения")
                .petFont(24, .bold)
                .foregroundStyle(PetPalette.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("achieve.title")
            XpBar(fraction: rows.isEmpty ? 0 : Double(got) / Double(rows.count), height: 10)
                .padding(.horizontal, 24)
            Text(Achievements.summary(f))
                .petFont(15, .semibold)
                .monospacedDigit()
                .foregroundStyle(PetPalette.ink)
                .accessibilityIdentifier("achieve.summary")
        }
    }
}

/// Карточка одного достижения.
private struct AchievementCard: View {
    let row: AchievementRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(row.item.emoji)
                .petFont(26)
                .frame(width: 44, height: 44)
                .background(Circle().fill(row.got ? PetPalette.accent.opacity(0.18) : PetPalette.soft.opacity(0.12)))
                .grayscale(row.got ? 0 : 1)
                .opacity(row.got ? 1 : 0.55)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                AXRow(spacing: 8) {
                    Text(row.item.title)
                        .petFont(16, .bold)
                        .foregroundStyle(row.got ? PetPalette.ink : PetPalette.soft)
                        .axLines(2)
                    if !typeIsAX { Spacer(minLength: 6) }
                    Text(Achievements.rewardText(row.reward))
                        .petFont(14, .bold)
                        .monospacedDigit()
                        .foregroundStyle(row.got ? PetPalette.accent : PetPalette.soft)
                }
                Text(row.item.note)
                    .petFont(13, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .axLines(2)
                if row.got {
                    Label {
                        Text(Achievements.gotText(row))
                            .petFont(13, .semibold)
                            .foregroundStyle(PetPalette.green)
                            .axLines(1)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(PetPalette.green)
                    }
                } else {
                    HStack(spacing: 8) {
                        XpBar(fraction: row.fraction, height: 6)
                        Text(Achievements.progressText(row))
                            .petFont(12, .semibold)
                            .monospacedDigit()
                            .foregroundStyle(PetPalette.soft)
                            .fixedSize()
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(PetPalette.card)
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(row.got ? PetPalette.accent.opacity(0.55) : .clear, lineWidth: 1.5))
        )
        .opacity(row.got ? 1 : 0.8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Achievements.speech(row))
        .accessibilityIdentifier("achieve.\(row.id)")
    }

    @Environment(\.dynamicTypeSize) private var type
    private var typeIsAX: Bool { type.isAccessibilitySize }
}
