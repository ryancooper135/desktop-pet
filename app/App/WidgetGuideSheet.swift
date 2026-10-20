// Гайд «Поставь виджет и остров»: после первой удачной кормёжки, повтор через 7 дней, максимум 2 раза.
// Когда показывать — Guides.shouldShowWidgetGuide, кто показывает — GuideCenter.

import SwiftUI
import UIKit
@preconcurrency import PetCore

struct WidgetGuideSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    var onDone: () -> Void
    @State private var turningOn = false

    var body: some View {
        let name = model.snap.name
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 16) {
                    WidgetDemo(pose: model.snap.pose)
                        .padding(.top, 20)
                    VStack(spacing: 4) {
                        Text("\(name) всегда рядом")
                            .petFont(24, .bold)
                            .foregroundStyle(PetPalette.ink)
                            .accessibilityAddTraits(.isHeader)
                        // Короче и с полями: длинная фраза шла от края до края.
                        Text("Как он — видно без приложения")
                            .petFont(15, .medium)
                            .foregroundStyle(PetPalette.soft)
                            .padding(.horizontal, 12)
                    }
                    .multilineTextAlignment(.center)

                    GuideCard(title: "Виджет на экран «Домой»", icon: "square.grid.2x2.fill", steps: [
                        "Зажми пустое место на экране «Домой»",
                        "Нажми «Изменить» → «Добавить виджет»",
                        "Найди «Питомец» и выбери размер",
                    ])
                    GuideCard(title: "И на экран блокировки", icon: "lock.fill", steps: [
                        "Зажми экран блокировки → «Настроить»",
                        "Выбери экран блокировки и добавь «Питомец»",
                    ])
                    island(name: name)
                }
            }
            .scrollIndicators(.hidden)

            Button {
                onDone()
            } label: {
                Text("Готово").frame(maxWidth: .infinity, minHeight: 50)
            }
            .petFont(17, .bold)
            .buttonStyle(.borderedProminent)
            .tint(PetPalette.accent)
            .accessibilityIdentifier("guide.done")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(PetPalette.bg.ignoresSafeArea())
    }

    /// Остров: включён — просто рассказываем; выключен у нас — кнопка; выключен в iOS — в Настройки.
    @ViewBuilder
    private func island(name: String) -> some View {
        let enabled = model.file?.island.enabled ?? true
        let system = LiveActivityController.systemEnabled
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "capsule.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PetPalette.accent)
                    .frame(width: 22)
                Text("Остров")
                    .petFont(16, .bold)
                    .foregroundStyle(PetPalette.ink)
                Spacer(minLength: 0)
            }
            if !system {
                Text("Живые активности выключены в iOS. Включи их: Настройки → Питомец → Live Activities.")
                    .guideText()
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .petFont(15, .semibold)
                .tint(PetPalette.accent)
                .accessibilityIdentifier("guide.settings")
            } else if !enabled {
                Text("Включи — и \(name) будет жить на «острове» наверху экрана, даже когда приложение закрыто.")
                    .guideText()
                Button {
                    turningOn = true
                    Task {
                        await AppActions.shared.setIsland(enabled: true)
                        turningOn = false
                    }
                } label: {
                    Text("Включить остров").frame(maxWidth: .infinity, minHeight: 40)
                }
                .petFont(15, .semibold)
                .buttonStyle(.bordered)
                .tint(PetPalette.accent)
                .disabled(turningOn)
                .accessibilityIdentifier("guide.island")
            } else {
                Text("Уже включён: когда сворачиваешь приложение, \(name) живёт на «острове» наверху экрана.")
                    .guideText()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(PetPalette.card))
    }
}

private struct GuideCard: View {
    let title: String
    let icon: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PetPalette.accent)
                    .frame(width: 22)
                Text(title)
                    .petFont(16, .bold)
                    .foregroundStyle(PetPalette.ink)
                Spacer(minLength: 0)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { pair in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(pair.offset + 1)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(PetPalette.accent))
                    Text(pair.element).guideText()
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(PetPalette.card))
    }
}

/// Мини-телефон: иконки и «прилетающий» виджет с мордочкой. Без анимации, если она выключена в системе.
private struct WidgetDemo: View {
    let pose: Pose
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(PetPalette.card)
                .frame(width: 150, height: 190)
            Capsule()
                .fill(PetPalette.ink.opacity(0.85))
                .frame(width: 46, height: 12)
                .offset(y: -80)
            VStack(spacing: 8) {
                tile
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 6).fill(PetPalette.soft.opacity(0.25)).frame(width: 22, height: 22)
                    }
                }
            }
            .offset(y: 8)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var tile: some View {
        let base = RoundedRectangle(cornerRadius: 14)
            .fill(PetPalette.bg)
            .frame(width: 112, height: 70)
            .overlay(
                HStack(spacing: 6) {
                    PetFaceView(pose: pose).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(PetPalette.accent).frame(width: 40, height: 6)
                        Capsule().fill(PetPalette.soft.opacity(0.4)).frame(width: 30, height: 6)
                    }
                }
            )
        if reduceMotion {
            base
        } else {
            base.phaseAnimator([false, true]) { content, shown in
                content
                    .scaleEffect(shown ? 1 : 0.7)
                    .opacity(shown ? 1 : 0.2)
            } animation: { shown in
                shown ? .spring(duration: 0.6, bounce: 0.35).delay(0.4) : .easeIn(duration: 0.3).delay(1.6)
            }
        }
    }
}

private extension Text {
    func guideText() -> some View {
        self.petFont(15)
            .foregroundStyle(PetPalette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
