// Отклик на касание (волна 29): одна точка для вибрации и звука от действий пользователя.
// Какой вид у какого события — RESEARCH/15-feedback.md; когда отклик молчит — Shared/Feel.swift (FeelGate).
//
// Вибрация — генераторы UIKit (prepare() на касание, чтобы первый отклик не опаздывал); сами генераторы
// уважают системную настройку «Тактильный отклик». Звук — SoundKit (.ambient: молчит на беззвучном).
// В фоне, в тестах и при выключенной «Вибрации»/«Звуке» — тишина. Звуки хореографии (мяч, хруст)
// идут мимо Feel: это часть анимации, а не отклик на палец.

import SwiftUI
import UIKit

/// Где рождается вибрация. В приложении — UIKit; в тестах можно подменить.
@MainActor
protocol HapticEngine: AnyObject {
    func prepare(_ kind: FeelKind)
    func fire(_ kind: FeelKind)
}

@MainActor
final class UIKitHaptics: HapticEngine {
    private lazy var selection = UISelectionFeedbackGenerator()
    private lazy var light = UIImpactFeedbackGenerator(style: .light)
    private lazy var soft = UIImpactFeedbackGenerator(style: .soft)
    private lazy var medium = UIImpactFeedbackGenerator(style: .medium)
    private lazy var rigid = UIImpactFeedbackGenerator(style: .rigid)
    private lazy var notice = UINotificationFeedbackGenerator()

    func prepare(_ kind: FeelKind) {
        switch kind {
        case .select: selection.prepare()
        case .tap: light.prepare()
        case .soft: soft.prepare()
        case .bump: medium.prepare()
        case .nudge: rigid.prepare()
        case .success, .denied: notice.prepare()
        }
    }

    func fire(_ kind: FeelKind) {
        switch kind {
        case .select: selection.selectionChanged()
        case .tap: light.impactOccurred()
        case .soft: soft.impactOccurred(intensity: 0.8)
        case .bump: medium.impactOccurred()
        // Мягкое «не то» в игре: короткий жёсткий щелчок вполсилы, не тревожное уведомление.
        case .nudge: rigid.impactOccurred(intensity: 0.5)
        case .success: notice.notificationOccurred(.success)
        case .denied: notice.notificationOccurred(.warning)
        }
    }
}

@MainActor
enum Feel {
    static var engine: HapticEngine = UIKitHaptics()
    private static var gate = FeelGate()

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    // MARK: виды (см. FeelKind)

    static func select(_ sound: SoundCue? = nil) { fire(.select, sound) }
    static func tap(_ sound: SoundCue? = nil) { fire(.tap, sound) }
    static func soft(_ sound: SoundCue? = nil) { fire(.soft, sound) }
    static func bump(_ sound: SoundCue? = nil) { fire(.bump, sound) }
    static func nudge(_ sound: SoundCue? = nil) { fire(.nudge, sound) }
    static func success(_ sound: SoundCue? = nil) { fire(.success, sound) }
    /// Нельзя/недоступно/отказ. По умолчанию с «не-а»: отказ не бывает немым.
    static func denied(_ sound: SoundCue? = .refuse) { fire(.denied, sound) }

    /// Вибрация вида kind (вид выбран выше по коду, например самый сильный за кадр).
    static func haptic(_ kind: FeelKind) { fire(kind, nil) }

    /// Только звук (вибрацию уже дал другой вызов того же события).
    static func sound(_ cue: SoundCue) {
        guard !Env.isTesting else { return }
        refresh()
        if gate.allowSound(cue, at: now) { SoundKit.shared.play(cue) }
    }

    /// Отклик от смены состояния, а не от пальца (сердца, вернулся с прогулки): молчит первые секунды
    /// после возврата из фона.
    static func ambient(_ kind: FeelKind?, _ cue: SoundCue? = nil) {
        fire(kind, cue, ambient: true)
    }

    /// Разбудить генераторы заранее (касание началось, игра началась): отклик без задержки.
    static func prepare(_ kinds: FeelKind...) {
        guard !Env.isTesting, gate.active, FeelGate.enabled(FeelGate.hapticsKey) else { return }
        for k in kinds { engine.prepare(k) }
    }

    // MARK: жизненный цикл (PetApp, scenePhase)

    static func becameActive() { gate.becameActive(at: now) }
    static func wentBackground() { gate.wentBackground() }

    // MARK: внутри

    private static func refresh() {
        gate.haptics = FeelGate.enabled(FeelGate.hapticsKey)
        gate.sound = FeelGate.enabled(FeelGate.soundKey)
    }

    private static func fire(_ kind: FeelKind?, _ cue: SoundCue?, ambient: Bool = false) {
        guard !Env.isTesting else { return }
        refresh()
        let t = now
        if let kind, gate.allowHaptic(kind, at: t, ambient: ambient) { engine.fire(kind) }
        if let cue, gate.allowSound(cue, at: t, ambient: ambient) { SoundKit.shared.play(cue) }
    }
}

extension View {
    /// Серый (`.disabled`) контрол — не немой: пока locked, тап по нему даёт `Feel.denied()`, вид тот же.
    /// Ставить после `.disabled`. Прозрачная накладка есть только у запертого: `.onTapGesture` на живой Button
    /// перехватил бы его собственное действие.
    func deniedTap(when locked: Bool) -> some View {
        overlay {
            if locked {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { Feel.denied() }
                    .accessibilityHidden(true)
            }
        }
    }
}
