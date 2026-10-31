// Волна 53 «B · Стекло», вариант 1: верх главного экрана — карточка «Задание дня», колечки шкал справа,
// мысль и просьба пса значками. Вместо фраз — значки и шкалы; полный текст остаётся для VoiceOver.

import SwiftUI
import UIKit
@preconcurrency import PetCore

// MARK: - Задание дня

/// Карточка под шапкой: кольцо выполненных, «ЗАДАНИЕ ДНЯ · 1/3», что сделать и награда чёрной плашкой «🪙 +45».
/// Тап — лист «Задания дня» (TasksSheet). Данные — HomeLook.quest(model.taskBoard).
struct HomeQuestCard: View {
    @Environment(AppModel.self) private var model
    let quest: HomeLook.Quest
    @State private var open = false

    var body: some View {
        Button {
            Feel.tap(.button)
            open = true
        } label: {
            HStack(spacing: 12) {
                RingGauge(value: quest.fraction, color: quest.allDone ? PetPalette.play : PetPalette.vio, size: 44, line: 4) {
                    Text(quest.emoji).font(.system(size: 18))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(quest.caption.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .kerning(0.6)
                        .foregroundStyle(PetPalette.soft)
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(quest.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let reward = quest.reward {
                    Text(reward)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(Capsule().fill(PetPalette.island))
                        .fixedSize()
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PetPalette.play)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
            .bGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(quest.a11y))
        .accessibilityHint(Text("Открыть задания дня"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.quest")
        .sheet(isPresented: $open) {
            TasksSheet()
                .environment(model)
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Колечки шкал

/// Вертикальная стеклянная пилюля справа: четыре колечка (сытость, чистота, веселье, любовь), всегда на виду.
/// Пустая шкала — красное колечко. Тап или свайп вверх — лист всех шкал (прежняя ручка «Шкалы», id open.needs).
struct NeedsPill: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot

    var body: some View {
        Button {
            Coach.shared.performed("swipe")
            model.showNeeds = true
        } label: {
            VStack(spacing: 8) {
                ForEach(VisibleNeeds.short, id: \.self) { n in
                    let v = snap.needs[n] ?? 0
                    let empty = Presenter.needEmpty(v)
                    RingGauge(value: v / 100, color: empty ? PetPalette.red : PetPalette.need(n),
                              size: BMetrics.needRing, line: 4) {
                        Image(systemName: Self.icon(n))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(empty ? PetPalette.red : PetPalette.need(n))
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 5)
            .bGlass(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(SquishStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onEnded { g in
                if g.translation.height < -12 {
                    Coach.shared.performed("swipe")
                    model.showNeeds = true
                }
            }
        )
        .accessibilityLabel(Text("Шкалы"))
        .accessibilityValue(Text(VisibleNeeds.short
            .map { "\(Catalog.needName($0)) \(Int((snap.needs[$0] ?? 0).rounded())) %" }
            .joined(separator: ", ")))
        .accessibilityHint(Text("Все шкалы питомца"))
        .accessibilityIdentifier("open.needs")
    }

    /// Залитый вариант значка шкалы, если он есть («drop» → «drop.fill»; у «fork.knife» залитого нет).
    static func icon(_ n: Need) -> String {
        let base = PetPalette.needIcon(n)
        return UIImage(systemName: base + ".fill") != nil ? base + ".fill" : base
    }

    /// Ширина пилюли — для симметрии центра экрана (HomeScreen отступает столько же слева).
    static let width: CGFloat = BMetrics.needRing + 10
}

// MARK: - Мысль и просьба значками

/// Стеклянный кружок-пузырь у пса: значок вместо фразы («Хочу есть» → вилка). Срочно — красная обводка.
struct IconBubble<Face: View>: View {
    var urgent = false
    var accent: Color = PetPalette.vio
    @ViewBuilder var face: Face

    var body: some View {
        face
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 4)
            .bGlass(Capsule())
            .overlay(Capsule().stroke(urgent ? PetPalette.red.opacity(0.7) : accent.opacity(0.35), lineWidth: urgent ? 2 : 1))
            .contentShape(Capsule())
    }
}
