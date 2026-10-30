// Волна 35 K: плашка челленджа дня под шапкой экрана мини-игры — «Челлендж: 2 000 · сегодня»,
// «Челлендж дня — в «Блок Дуо»» или «✓ Челлендж выполнен». До ур. 11 её нет совсем (экран как раньше).
// После раунда, который выполнил челлендж, плашка на 3 с становится всплывашкой «+1 ✂️ · +10 опыта».
// Экран игры вставляет одну строку: ChallengeBadge(game: .blockduo) сразу после topBar.

import SwiftUI
@preconcurrency import PetCore

struct ChallengeBadge: View {
    let game: ChallengeGame

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Когда открыли экран: выигрыши раньше — не наши, всплывашку не показываем.
    @State private var openedT = Clock.now()
    /// Текст всплывашки, пока она видна.
    @State private var reward: String? = nil
    @State private var hideTask: Task<Void, Never>? = nil

    /// Сколько висит всплывашка.
    static let rewardFor: Double = 3

    var body: some View {
        // VStack, а не Group: пустой (до ур. 11) он всё равно живёт — onAppear/onChange срабатывают, места не занимает.
        VStack(spacing: 0) {
            if let text = reward {
                pill(text, a11y: "Челлендж выполнен: \(text)", tint: PetPalette.green, strong: true)
                    .accessibilityIdentifier("challenge.reward")
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else if let s = model.challengeStatus(game) {
                pill(Challenges.badgeText(s), a11y: Challenges.badgeA11y(s), tint: tint(s), strong: s == .done || isToday(s))
                    .accessibilityIdentifier("challenge.badge")
                    .transition(.opacity)
            }
        }
        .onChange(of: model.file?.challenge.last?.t) { _, _ in noteWin() }
        .onAppear {
            openedT = Clock.now() - 1
            // Раунд мог записаться раньше, чем плашка появилась (снимки UI-тестов с готовой партией).
            noteWin()
        }
        .onDisappear { hideTask?.cancel() }
    }

    private func isToday(_ s: ChallengeStatus) -> Bool {
        if case .today = s { return true }
        return false
    }

    private func tint(_ s: ChallengeStatus) -> Color {
        switch s {
        case .today: return PetPalette.accent
        case .elsewhere: return PetPalette.soft
        case .done: return PetPalette.green
        }
    }

    /// Компактная капсула: цветная точка-обводка и текст. Фон карточки — читается и на тёмном фоне игры.
    private func pill(_ text: String, a11y: String, tint: Color, strong: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, weight: strong ? .bold : .semibold, design: .rounded))
            .foregroundStyle(strong ? PetPalette.ink : PetPalette.soft)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(PetPalette.card))
            .overlay(Capsule().strokeBorder(tint.opacity(strong ? 0.9 : 0.5), lineWidth: 1.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(a11y))
            .padding(.bottom, 8)
    }

    /// Раунд только что выполнил челлендж — показать награду и вернуться к «✓ Челлендж выполнен».
    private func noteWin() {
        guard let w = model.challengeWin(game, after: openedT) else { return }
        let text = Challenges.rewardText(w)
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) { reward = text }
        // Новый выигрыш больше не «свежий»: повторное открытие экрана всплывашку не покажет.
        openedT = w.t + 0.001
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.rewardFor))
            if Task.isCancelled { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { reward = nil }
        }
    }
}
