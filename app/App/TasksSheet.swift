// Волна 42 J: лист «Задания дня» — открывается карточкой в листе «Уровень» (LevelSheet).
// Каждое задание: значок, что сделать, прогресс «1 / 3» и награда «+20 🪙»; внизу — награда за все задания (✂️).
// Раз в сутки невыполненное задание можно заменить. Логика и тексты — DailyTasks / DailyTaskText (Shared).

import SwiftUI
@preconcurrency import PetCore

struct TasksSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text(DailyTaskText.title)
                        .petFont(22, .bold)
                        .foregroundStyle(PetPalette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    SheetCloseButton(id: "tasks.close")
                }
                if let b = model.taskBoard {
                    ForEach(b.items, id: \.id) { t in
                        row(t, canSwap: b.swapsLeft > 0 && !t.done && !b.allPaid)
                    }
                    allCard(b)
                    Text(b.swapsLeft > 0 ? "Одно задание в день можно заменить" : "Новые задания — завтра")
                        .petFont(12, .medium)
                        .foregroundStyle(PetPalette.soft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Заданий пока нет")
                        .petFont(15, .medium)
                        .foregroundStyle(PetPalette.soft)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tasks.sheet")
    }

    private func row(_ t: DailyTask, canSwap: Bool) -> some View {
        HStack(spacing: 12) {
            Text(DailyTaskText.emoji(t.id))
                .font(.system(size: 26))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(DailyTaskText.name(t))
                    .petFont(15, .semibold)
                    .foregroundStyle(PetPalette.ink)
                    .strikethrough(t.done, color: PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
                XpBar(fraction: Double(min(t.n, t.need)) / Double(max(1, t.need)), height: 6)
                HStack(spacing: 8) {
                    Text(DailyTaskText.progress(t))
                        .petFont(13, .semibold)
                        .monospacedDigit()
                        .foregroundStyle(t.done ? PetPalette.accent : PetPalette.soft)
                    Text(DailyTaskText.reward(t))
                        .petFont(13, .medium)
                        .monospacedDigit()
                        .foregroundStyle(PetPalette.soft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(DailyTaskText.name(t)): \(DailyTaskText.progress(t)), награда \(EconText.coins(t.coins))")
            .accessibilityIdentifier("tasks.row.\(t.id)")
            if canSwap {
                Button {
                    Feel.tap(.button)
                    model.swapTask(t.id)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PetPalette.soft)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel("Заменить задание")
                .accessibilityIdentifier("tasks.swap.\(t.id)")
            } else if t.done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(PetPalette.accent)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
    }

    private func allCard(_ b: TaskBoard) -> some View {
        HStack(spacing: 10) {
            Text(b.allPaid ? "🎉" : "✂️")
                .font(.system(size: 22))
                .accessibilityHidden(true)
            Text(b.allPaid ? "Все задания дня выполнены" : DailyTaskText.allReward(b))
                .petFont(14, .semibold)
                .foregroundStyle(b.allPaid ? PetPalette.accent : PetPalette.ink)
            Spacer(minLength: 8)
            Text("\(b.doneCount) / \(b.items.count)")
                .petFont(14, .bold)
                .monospacedDigit()
                .foregroundStyle(PetPalette.soft)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).strokeBorder(PetPalette.accent.opacity(0.5), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tasks.all")
    }
}
