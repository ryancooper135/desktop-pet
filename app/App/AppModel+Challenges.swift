// Волна 35 K: челлендж дня в мини-играх — что показать на плашке экрана игры. Логика и награда — Challenges.swift;
// засчитывает его сам finish экрана (Challenges.play вокруг CatchGame/BlockDuo/ZombieRun.finish), здесь только чтение.

import Foundation
@preconcurrency import PetCore

extension AppModel {
    /// Плашка челленджа на экране игры g; nil — до ур. 11 (плашки нет).
    func challengeStatus(_ g: ChallengeGame) -> ChallengeStatus? {
        guard let f = file else { return nil }
        return Challenges.status(f, game: g, at: snap.t)
    }

    /// Выигрыш челленджа в игре g, случившийся после момента t (экран открыт) — для всплывашки «+1 ✂️ · +10 опыта».
    func challengeWin(_ g: ChallengeGame, after t: Double) -> ChallengeWin? {
        guard let w = file?.challenge.last, w.game == g.rawValue, w.t >= t else { return nil }
        return w
    }
}
