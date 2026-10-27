// Волна 34 G: действия экрана «Двор» — купить плиту, улучшить станцию, открыть ярус, собрать копилку.
// Всё через стор (PetStore.mutate) в одной записи: двор, кошелёк, опыт пса (DogLevel.settle), потом снимок
// и виджеты с островком (AppActions.afterChange). Отказ не немой: тост с причиной и «не-а» (refuse).

import Foundation
@preconcurrency import PetCore

extension AppModel {
    /// Уровень пса по последнему чтению стора (для экрана и бейджа).
    var yardDogLevel: Int { file.map { DogLevel.level($0) } ?? 1 }

    /// Бейдж кнопки «Двор»: копилка полная или следующая плита по карману (YardText.badge).
    func yardBadge(now: Double = Clock.now()) -> Bool {
        guard let f = file else { return false }
        return YardText.badge(f, now: now, dogLevel: DogLevel.level(f))
    }

    /// Купить плиту двора. nil — стор не записался; отказ показан тостом.
    @discardableResult
    func buyYardPlate(_ id: String) -> YardBuyResult? {
        yardWrite { f, now in Yard.buyPlate(id, in: &f, now: now, dogLevel: DogLevel.level(f)) }
            .map { r in
                switch r {
                case .ok: Feel.success(.coins)
                default: refuseYard(r)
                }
                return r
            }
    }

    /// Улучшить станцию на уровень.
    @discardableResult
    func upgradeYardStation(_ id: String) -> YardBuyResult? {
        yardWrite { f, now in Yard.upgrade(id, in: &f, now: now, dogLevel: DogLevel.level(f)) }
            .map { r in
                switch r {
                case .upgraded: Feel.success(.coins)
                default: refuseYard(r)
                }
                return r
            }
    }

    /// Золотая табличка станции за клочки ✂️ (волна 35 M): +goldPct % к её доходу и золотой вид в сцене.
    @discardableResult
    func goldYardStation(_ id: String) -> YardGoldResult? {
        let r = yardWrite { f, now in Yard.gild(id, in: &f, now: now, dogLevel: DogLevel.level(f)) }
        guard let r else { return nil }
        switch r {
        case .ok:
            Feel.success(.coins)
            show("Табличка теперь золотая: +\(YardConfig.shared.goldPct) %", emoji: "🏅")
        case .noShards(let need): refuse("Не хватает: ещё \(EconText.shards(need))")
        case .owned: refuse("Табличка уже золотая")
        case .notBuilt: refuse("Сначала поставь станцию")
        case .unknown: refuse(RefuseText.text("store"))
        }
        return r
    }

    /// Открыть следующий ярус — это уровень линии дома «Участок» (HomeShop.buy, там же гейт и журнал yard.tier).
    @discardableResult
    func openYardTier() -> HomeShop.BuyResult? {
        let r = yardWrite { f, now in HomeShop.buy(.yard, in: &f, now: now) }
        guard let r else { return nil }
        switch r {
        case .ok: Feel.success(.hearts)
        case .noCoins(let need): refuse(YardText.noCoins(need))
        case .needLevel(let l): refuse("Пёс ещё мал: нужен ур. \(l)")
        case .needPlates(let k): refuse("Сначала купи все плиты яруса — осталось \(k)")
        case .maxed: refuse("Все ярусы уже открыты")
        case .unknown: refuse(RefuseText.text("store"))
        }
        return r
    }

    /// Собрать копилку: монеты в кошелёк, порции в кладовую, тост с чаевыми. Пусто — мягкий отказ.
    @discardableResult
    func collectYard() -> YardHarvest? {
        let h = yardWrite { f, now in Yard.collect(in: &f, now: now, dogLevel: DogLevel.level(f)) }
        guard let h else { return nil }
        if h.isEmpty {
            refuse(YardText.harvest(h))
        } else {
            Feel.success(.coins)
            show(YardText.harvest(h), emoji: "🐷")
        }
        return h
    }

    /// Переезд двора (волна 36 P): двор заново, монеты сверх moveKeepCoins срезаются, слава навсегда.
    /// Гейт (ур. пса и полный двор) — в Yard.move; кнопки без гейта нет, но отказ всё равно не немой.
    @discardableResult
    func moveYard() -> YardMoveResult? {
        let r = yardWrite { f, now in Yard.move(in: &f, now: now, dogLevel: DogLevel.level(f)) }
        guard let r else { return nil }
        if case .ok(let m, _) = r {
            Feel.success(.hearts)
            show(YardText.moved(moves: m), emoji: "🚚")
        } else if let t = YardText.moveRefuse(r) {
            refuse(t)
        }
        return r
    }

    // MARK: общее

    /// Одна запись в стор: действие, опыт пса и клочки по журналу, снимок, виджеты. nil — стор не записался.
    private func yardWrite<R>(_ body: (inout SaveFile, Double) -> R) -> R? {
        let now = Clock.now()
        let r: R
        do {
            r = try PetStore.shared.mutate { f -> R in
                let out = body(&f, now)
                // Опыт пса и достижения двора («Первая станция», «Переезд»…) — в эту же запись (волна 40 E).
                PetRunner.settleRewards(&f, now: now)
                return out
            }
        } catch {
            refuse(RefuseText.text("store"))
            return nil
        }
        refresh(now: now)
        Task { await AppActions.shared.afterChange() }
        return r
    }

    private func refuseYard(_ r: YardBuyResult) {
        switch r {
        case .noCoins(let need): refuse(YardText.noCoins(need))
        case .locked(let l): refuse(YardText.lock(l))
        case .owned: refuse("Это уже стоит во дворе")
        case .maxed: refuse("Станция на максимуме")
        case .notBuilt: refuse("Сначала поставь станцию")
        case .unknown: refuse(RefuseText.text("store"))
        case .ok, .upgraded: break
        }
    }
}
