// Батарея и плавность (волна 16): когда 3D-комнате можно не рисоваться и как идут кадры мини-игр.
// Чистые функции без SwiftUI и RealityKit — тесты на Linux (RenderPauseTests).

import Foundation

/// Комната (PetStage) под полноэкранной обложкой. Обложка — мини-игра или «Пока тебя не было»: непрозрачная,
/// на весь экран, а RealityView под ней без паузы рисует сцену с тенью и скиннингом 60 раз в секунду.
/// Листы (.sheet) не в счёт: из-под них видна полоска комнаты, она должна жить.
enum StagePause {
    /// Сколько ждать после открытия обложки, прежде чем гасить комнату: обложка ещё въезжает, комнату видно.
    static let settle: TimeInterval = 0.8

    /// Закрыта ли комната целиком.
    static func covered(catchGame: Bool, blockDuo: Bool, zombie: Bool, away: Bool) -> Bool {
        catchGame || blockDuo || zombie || away
    }

    /// Через сколько секунд сцена принимает состояние covered. Гасим не сразу (въезд обложки), включаем сразу:
    /// обложка уезжает, а под ней должна быть живая комната — Шиба прыгает после мини-игры.
    static func delay(covered: Bool) -> TimeInterval {
        covered ? settle : 0
    }
}

/// Часы кадров мини-игры (CatchGameScreen, ZombieRunScreen). Время раунда — сумма шагов, а не настенные часы:
/// шаг не больше maxStep (подвисание не прыгает раунд вперёд). Пока приложение не активно (Пункт управления,
/// переключатель приложений, звонок), шаг 0 — раунд стоит, а цикл просыпается реже (idleMs вместо frameMs).
struct FrameClock {
    static let maxStep: TimeInterval = 0.05
    /// Около 1/60 с.
    static let frameMs = 16
    /// На паузе — четыре раза в секунду: только проверить, не вернулись ли.
    static let idleMs = 250

    private(set) var last: TimeInterval

    init(now: TimeInterval) {
        last = now
    }

    /// Шаг времени раунда к моменту now. running == false — 0, и пауза не попадёт в следующий шаг.
    mutating func tick(now: TimeInterval, running: Bool) -> TimeInterval {
        defer { last = now }
        guard running else { return 0 }
        return min(max(now - last, 0), Self.maxStep)
    }

    /// Сколько спать до следующего шага.
    static func waitMs(running: Bool) -> Int {
        running ? frameMs : idleMs
    }
}
