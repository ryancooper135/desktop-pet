// Ротация реплик без истории: порядок строк — перестановка от сида, каждый цикл она чуть
// перемешивается внутри блоков ширины w. Повтор строки — не раньше чем через n − w + 1 ходов,
// поэтому длину хода (period) и w подбираем по размеру пула так, чтобы между ходами одной
// строки прошло ≥ 7 дней. Всё детерминировано: приложение, виджет и остров видят одно и то же.
//
// Редкие кадры: полчасовая сетка по местному времени, блоки по rareEvery слотов, в каждом блоке
// ровно один редкий слот (днём, если в блоке есть дневные слоты). Отсюда ~1 из 20 и гарантия
// дневной пасхалки не реже раза в 3 дня (на деле — раз в ~сутки).

import Foundation

enum LineRotation {
    /// Окно без повторов.
    static let windowHours = 168
    /// Лестница длины хода, часы. Берётся самая короткая, при которой пул укладывается в окно.
    static let periodsHours = [1, 2, 3, 4, 6, 8, 12, 24]
    /// Для выбора по слотам (уведомления — день, лента «Пока тебя не было» — час): минимум слотов между повторами.
    static let slotGap = 7

    /// Редкий кадр: длина слота (как точки timeline виджета), 1 редкий слот на rareEvery слотов.
    static let rareSlotMinutes = 30
    static let rareEvery = 20
    /// Где ставить редкий слот, если в блоке есть такие часы (местное время, [from, to)).
    static let rareDayFromHour = 10
    static let rareDayToHour = 22
    /// Повтор редкой строки не раньше чем через 7 дней: блоки по 10 ч → ≥ 18 блоков.
    static let rareGap = (windowHours * 60 + rareSlotMinutes * rareEvery - 1) / (rareSlotMinutes * rareEvery) + 1

    // MARK: план ротации

    /// Длина хода (часы) и ширина блока для пула из count строк, из которых slack могут быть недоступны
    /// (tier 1, подстановки): их ход может занять строка эскалации или предыдущая строка.
    static func plan(count: Int, slack: Int) -> (periodHours: Int, block: Int) {
        for p in periodsHours {
            let gap = (windowHours + p - 1) / p + 1 + slack
            if count >= gap { return (p, count - gap + 1) }
        }
        return (24, 1)
    }

    /// Ширина блока для выбора по слотам: между ходами одной строки ≥ gap слотов (если строк хватает).
    static func block(count: Int, gap: Int) -> Int {
        max(1, count - gap + 1)
    }

    /// Номер хода по местному времени.
    static func slot(_ t: Double, tzOffsetMin: Int, periodHours: Int) -> Int {
        floorDiv(localMinute(t, tzOffsetMin), max(1, periodHours) * 60)
    }

    static func localMinute(_ t: Double, _ tzOffsetMin: Int) -> Int {
        Int((t / 60).rounded(.down)) + tzOffsetMin
    }

    // MARK: порядок

    /// Порядок индексов 0..<count в цикле cycle.
    static func order(count: Int, seed: UInt64, cycle: Int, block: Int) -> [Int] {
        var a = Array(0..<count)
        var rng = StableRandom(seed: seed)
        shuffle(&a, 0, count, &rng)
        if block > 1 {
            var rc = StableRandom(seed: StableRandom.mix(seed ^ StableRandom.mix(UInt64(bitPattern: Int64(cycle)))))
            var s = 0
            while s < count {
                shuffle(&a, s, min(s + block, count), &rc)
                s += block
            }
        }
        return a
    }

    /// Индекс строки на ходу position, когда доступны все.
    static func at(count: Int, seed: UInt64, position: Int, block: Int) -> Int {
        order(count: count, seed: seed, cycle: floorDiv(position, count), block: block)[mod(position, count)]
    }

    /// Строка хода position: если она недоступна (eligible == false), берётся ближайшая доступная до неё.
    /// nil — доступных нет совсем.
    static func walk(count: Int, seed: UInt64, position: Int, block: Int, eligible: [Bool]) -> Int? {
        guard count > 0, eligible.count == count, eligible.contains(true) else { return nil }
        var cached: (cycle: Int, order: [Int])? = nil
        for step in 0..<(2 * count) {
            let k = position &- step
            let c = floorDiv(k, count)
            if cached?.cycle != c { cached = (c, order(count: count, seed: seed, cycle: c, block: block)) }
            let i = cached!.order[mod(k, count)]
            if eligible[i] { return i }
        }
        return eligible.firstIndex(of: true)
    }

    // MARK: редкие кадры

    /// Номер блока, если на момент t приходится его редкий слот; иначе nil.
    static func rareBlock(seed: String, at t: Double, tzOffsetMin: Int) -> Int? {
        let q = floorDiv(localMinute(t, tzOffsetMin), rareSlotMinutes)
        let b = floorDiv(q, rareEvery)
        return rareSlot(seed: seed, block: b) == q ? b : nil
    }

    /// Редкий слот блока b (номер получасового слота по местному времени).
    static func rareSlot(seed: String, block b: Int) -> Int {
        let first = b * rareEvery
        let h = StableRandom.mix(StableHash.fnv1a("\(seed):rare") ^ StableRandom.mix(UInt64(bitPattern: Int64(b))))
        let day = (first..<(first + rareEvery)).filter { isDay(slot: $0) }
        if !day.isEmpty { return day[Int(h % UInt64(day.count))] }
        return first + Int(h % UInt64(rareEvery))
    }

    /// Получасовой слот попадает в дневные часы.
    static func isDay(slot q: Int) -> Bool {
        let perDay = 24 * 60 / rareSlotMinutes
        let m = mod(q, perDay)
        return m >= rareDayFromHour * 60 / rareSlotMinutes && m < rareDayToHour * 60 / rareSlotMinutes
    }

    // MARK: арифметика

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    static func mod(_ a: Int, _ b: Int) -> Int {
        let r = a % b
        return r < 0 ? r + b : r
    }

    /// Фишер–Йейтс на a[from..<to]. Свой, а не shuffle(using:): у того порядок не обещан между версиями Swift.
    private static func shuffle(_ a: inout [Int], _ from: Int, _ to: Int, _ rng: inout StableRandom) {
        var i = to - 1
        while i > from {
            let j = from + Int(rng.next() % UInt64(i - from + 1))
            a.swapAt(i, j)
            i -= 1
        }
    }
}

/// splitmix64: стабильный между запусками и версиями генератор.
struct StableRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        return Self.finalize(state)
    }

    /// Перемешивание битов одного числа: у FNV слабые младшие биты, а мы берём остаток.
    static func mix(_ x: UInt64) -> UInt64 {
        finalize(x &+ 0x9E37_79B9_7F4A_7C15)
    }

    private static func finalize(_ x: UInt64) -> UInt64 {
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
