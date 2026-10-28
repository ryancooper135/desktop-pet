// Награда ✂️ для тоста, ещё не показанная (волна 40 E): достижения и обычные выплаты того же действия.
// Показ (когда тост видно, не поверх отчёта/листа/сцены уровня) — AppModel.showAward; здесь только что и как сказать.
// Волна 43 L: обычных выплат может быть несколько в одну запись (день заботы и сундук недели, день заботы и место) —
// раньше держалась одна, и «+3 ✂️ за день заботы» терялся за сундуком.

import Foundation
@preconcurrency import PetCore

struct PendingAward: Hashable, Sendable {
    var ids: [String] = []
    var plain: [ShardGain] = []

    init() {}

    mutating func add(ids new: [String]) {
        ids += new.filter { !ids.contains($0) }
    }

    /// Обычная выплата (не за достижение: у тех свой тост по ids); повтор той же — ничего.
    mutating func add(plain g: ShardGain) {
        guard g.shards > 0, !g.reason.hasPrefix("ach."), !plain.contains(g) else { return }
        plain.append(g)
    }

    /// Один тост на всё: «Достижение: … · +5 ✂️ · +3 ✂️ за день заботы», «+3 клочка за день заботы»
    /// или «+3 ✂️ за день заботы · +10 ✂️ …» (несколько выплат). nil — показывать нечего.
    func toast(_ cfg: PremiumConfig = .shared) -> (text: String, emoji: String)? {
        if let text = Achievements.toast(ids, alsoAll: plain, cfg) { return (text, "🏆") }
        guard let first = plain.first else { return nil }
        if plain.count == 1 { return (Shards.toastText(first), "✂️") }
        return (plain.map(Shards.gainText).joined(separator: " · "), "✂️")
    }
}
