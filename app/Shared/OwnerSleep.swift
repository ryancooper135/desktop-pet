// Режим сна владельца (этап 6): питомец сам учит, когда хозяин спит, по меткам заходов и нажатий.
// Каждое касание (вход в приложение, уход в фон, кнопки виджета, острова и пульта; шаги и «Команды» — нет:
// шаги приходят сами, команду может запустить автоматизация по расписанию)
// раскладывается по ночам: вечер 18:00–04:00 — «последний заход», утро 04:00–14:00 — «первый заход».
// Окно сна — медианы за 14 дней с отбросом выбросов; пока ночей меньше 5 — 00:00–08:00.
//
// Где применяется:
//  • тихие часы уведомлений (NotificationPlanner) — объединение сна питомца (owner.bedMin–wakeMin) и окна хозяина,
//    но не дальше capMin от окна питомца: иначе «последний шанс» мог бы уехать за смерть (см. quiet);
//  • подсказка «Отбой» вечером, если Шиба ложится заметно раньше или позже хозяина (bedHintDue);
//  • «Доброе утро» один раз за ночь при первом утреннем заходе (greetingDue).
// Ядро не трогаем: owner.bedMin задаёт только хозяин («Ложусь в» и «Отбой»), owner.wakeMin — по-прежнему умолчание.

import Foundation

/// Окно сна в минутах от местной полуночи: bed — засыпает, wake — просыпается (может быть меньше bed — через полночь).
struct SleepWindow: Codable, Hashable, Sendable {
    var bed: Int
    var wake: Int
}

/// Наблюдения по ночам и ручная настройка. Верхним полем сейва (SaveFile.sleep), пустое в файл не пишется.
struct SleepLog: Codable, Hashable, Sendable {
    /// Ночь n — местный день вечера (вечер 23:50 и утро 08:10 следующего дня — одна ночь).
    /// eve и morn — минуты от полудня дня n: вечер 18:00 = 360, полночь = 720, 04:00 = 960, утро 08:10 = 1210.
    /// Так переход через полночь — обычное сложение, и медиана не путает 23:50 с 00:10.
    struct Night: Codable, Hashable, Sendable {
        var n: Int
        var eve: Int?
        var morn: Int?
    }

    var nights: [Night] = []
    /// «Задать вручную»: если есть — вместо выученного.
    var manual: SleepWindow?
    /// Последнее касание и начало «бодрствования» (первое касание после перерыва ≥ OwnerSleep.restGapH).
    var lastT: Double?
    var wokeT: Double?
    /// За какую ночь уже сказали «Доброе утро» и предложили «Отбой» — по разу.
    var greeted: Int?
    var hinted: Int?

    init() {}

    var isEmpty: Bool {
        nights.isEmpty && manual == nil && lastT == nil && wokeT == nil && greeted == nil && hinted == nil
    }

    enum CodingKeys: String, CodingKey { case nights, manual, lastT, wokeT, greeted, hinted }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nights = (try? c.decodeIfPresent([Night].self, forKey: .nights)) ?? []
        manual = try? c.decodeIfPresent(SleepWindow.self, forKey: .manual)
        lastT = try? c.decodeIfPresent(Double.self, forKey: .lastT)
        wokeT = try? c.decodeIfPresent(Double.self, forKey: .wokeT)
        greeted = try? c.decodeIfPresent(Int.self, forKey: .greeted)
        hinted = try? c.decodeIfPresent(Int.self, forKey: .hinted)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !nights.isEmpty { try c.encode(nights, forKey: .nights) }
        try c.encodeIfPresent(manual, forKey: .manual)
        try c.encodeIfPresent(lastT, forKey: .lastT)
        try c.encodeIfPresent(wokeT, forKey: .wokeT)
        try c.encodeIfPresent(greeted, forKey: .greeted)
        try c.encodeIfPresent(hinted, forKey: .hinted)
    }
}

/// Оценка на сейчас: окно и откуда оно.
struct SleepEstimate: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// Ночей мало (k из minNights) — окно по умолчанию.
        case learning(Int)
        case learned
        case manual
    }

    var window: SleepWindow
    var source: Source
    /// Сколько ночей пошло в оценку (после отброса выбросов).
    var nights: Int

    /// Ещё учится: окно по умолчанию, предлагать его хозяину нечего.
    var isLearning: Bool {
        if case .learning = source { return true }
        return false
    }
}

enum OwnerSleep {
    /// Окно по умолчанию, пока не выучено.
    static let defaultWindow = SleepWindow(bed: 0, wake: 8 * 60)
    /// Скользящее окно наблюдений и сколько ночей нужно для своей оценки.
    static let days = 14
    static let minNights = 5
    /// Ночей храним с запасом: оценка берёт последние 14 дней, остальное — для «учусь» после перерыва.
    static let keepNights = 21
    /// Вечер — касания 18:00–04:00, утро — 04:00–14:00, 14:00–18:00 не считаем: днём о сне ничего не узнать.
    static let eveFrom = 18 * 60
    static let mornFrom = 4 * 60
    static let mornTo = 14 * 60
    /// Ночь короче 3 ч или длиннее 14 ч — не сон (не ложился вовсе или не заходил весь день), в оценку не идёт.
    static let minNightMin = 3 * 60
    static let maxNightMin = 14 * 60
    /// Значение дальше 3 ч от медианы — выброс (одна бессонная ночь, ранний самолёт).
    static let outlierMin = 3 * 60
    /// Перерыв, после которого касание считается новым «проснулся» (для «Доброе утро»).
    static let restGapH: Double = 3
    /// «Доброе утро» — только утром, до 13:00.
    static let greetTo = 13 * 60

    // MARK: координаты

    /// Местный день и минута касания t при сдвиге tz.
    static func local(_ t: Double, tzOffsetMin tz: Int) -> (day: Int, min: Int) {
        let m = Int((t / 60).rounded(.down)) + tz
        let day = Int((Double(m) / 1440).rounded(.down))
        return (day, m - day * 1440)
    }

    /// Минута суток → минуты от полудня «дня вечера»: 18:00 → 360, 00:40 → 760, 08:10 → 1210, 13:59 → 1559.
    /// m < mornTo — уже следующие сутки после вечера.
    static func noonRel(_ m: Int) -> Int { m < mornTo ? m + 720 : m - 720 }

    /// Обратно: минуты от полудня → минута суток.
    static func clock(_ x: Int) -> Int { (((x + 720) % 1440) + 1440) % 1440 }

    /// Расстояние между минутами суток по кругу: 23:50 и 00:10 — 20 минут.
    static func circDiff(_ a: Int, _ b: Int) -> Int {
        let d = (((a - b) % 1440) + 1440) % 1440
        return min(d, 1440 - d)
    }

    static func inWindow(_ m: Int, _ from: Int, _ to: Int) -> Bool {
        let a = ((from % 1440) + 1440) % 1440, b = ((to % 1440) + 1440) % 1440
        return a <= b ? (m >= a && m < b) : (m >= a || m < b)
    }

    /// К ближайшим 5 минутам.
    static func round5(_ x: Int) -> Int { Int((Double(x) / 5).rounded()) * 5 }

    // MARK: запись

    /// Какие действия — касание хозяина. Шаги приходят сами, «Команды» может запустить автоматизация по расписанию:
    /// по ним не видно, что хозяин не спит.
    static func counts(_ source: ActionSource) -> Bool {
        source != .shortcut && source != .steps
    }

    /// Касание хозяина в t: вечером — последний заход ночи, утром — первый. tz — сдвиг на момент касания
    /// (переехал в другой пояс — дальше пишется местное время там, где ты сейчас).
    static func note(_ log: inout SleepLog, t: Double, tzOffsetMin tz: Int) {
        // Первое касание вообще — не «проснулся»: приложение только поставили, здороваться не с чем.
        if let last = log.lastT, t - last >= restGapH * 3600 { log.wokeT = t }
        log.lastT = t

        let (day, m) = local(t, tzOffsetMin: tz)
        let night: Int
        if m >= eveFrom {
            night = day
        } else if m < mornTo {
            night = day - 1
        } else {
            return
        }
        let x = noonRel(m)
        var i = log.nights.firstIndex { $0.n == night }
        if i == nil {
            log.nights.append(SleepLog.Night(n: night))
            log.nights.sort { $0.n < $1.n }
            i = log.nights.firstIndex { $0.n == night }
        }
        guard let k = i else { return }
        if m >= eveFrom || m < mornFrom {
            log.nights[k].eve = max(log.nights[k].eve ?? x, x)
        } else {
            log.nights[k].morn = min(log.nights[k].morn ?? x, x)
        }
        log.nights.removeAll { $0.n < night - keepNights }
    }

    // MARK: оценка

    /// Окно сна на момент now: ручное, выученное или по умолчанию (пока ночей меньше minNights).
    static func estimate(_ log: SleepLog, now: Double, tzOffsetMin tz: Int) -> SleepEstimate {
        let pairs = usableNights(log, now: now, tzOffsetMin: tz)
        if let w = log.manual { return SleepEstimate(window: w, source: .manual, nights: pairs.count) }
        guard pairs.count >= minNights else {
            return SleepEstimate(window: defaultWindow, source: .learning(pairs.count), nights: pairs.count)
        }
        let bed = robustMedian(pairs.map(\.eve))
        let wake = robustMedian(pairs.map(\.morn))
        return SleepEstimate(window: SleepWindow(bed: clock(round5(bed)), wake: clock(round5(wake))),
                             source: .learned, nights: pairs.count)
    }

    /// Полные ночи (есть и вечер, и утро) за последние 14 дней с правдоподобной длиной.
    static func usableNights(_ log: SleepLog, now: Double, tzOffsetMin tz: Int) -> [(eve: Int, morn: Int)] {
        let today = local(now, tzOffsetMin: tz).day
        return log.nights.compactMap { (n: SleepLog.Night) -> (eve: Int, morn: Int)? in
            guard n.n >= today - days, n.n < today, let e = n.eve, let m = n.morn else { return nil }
            let len = m - e
            guard len >= minNightMin, len <= maxNightMin else { return nil }
            return (e, m)
        }
    }

    static func median(_ xs: [Int]) -> Double {
        let s = xs.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count % 2 == 1 ? Double(s[mid]) : Double(s[mid - 1] + s[mid]) / 2
    }

    /// Медиана после отброса значений дальше outlierMin от первой медианы.
    static func robustMedian(_ xs: [Int]) -> Int {
        let m = median(xs)
        let kept = xs.filter { abs(Double($0) - m) <= Double(outlierMin) }
        return Int(median(kept.isEmpty ? xs : kept).rounded())
    }

    // MARK: применение

    /// Тихие часы уведомлений: от раннего из двух «засыпаний» до позднего «проснулся» (сон питомца и хозяина),
    /// но не раньше bedMin − capMin и не позже wakeMin + capMin. Почему предел: ядро переносит уведомление из тихих
    /// часов на их конец, а таймер последнего сердца идёт только пока хозяин бодрствует по окну питомца (8 ч) и
    /// не кончается в первые 3 ч после подъёма. С пределом 3 ч «последний шанс» всегда приходит раньше смерти:
    /// до тихих часов таймер мог съесть ≤ capMin, после подъёма до конца тихих — тоже ≤ capMin, 3 + 3 < 8.
    static func quiet(bedMin: Int, wakeMin: Int, est: SleepWindow, capMin: Int) -> (from: Int, to: Int) {
        let petBed = noonRel(bedMin)
        let petWake = petBed + (((wakeMin - bedMin) % 1440) + 1440) % 1440
        let ownBed = noonRel(est.bed)
        let ownWake = ownBed + (((est.wake - est.bed) % 1440) + 1440) % 1440
        let from = max(min(petBed, ownBed), petBed - capMin)
        let to = min(max(petWake, ownWake), petWake + capMin)
        return (clock(from), clock(to))
    }

    /// Ночь, за которую пора сказать «Доброе утро», или nil. Утро (04:00–13:00), хозяин «проснулся» этим утром
    /// (первое касание после перерыва ≥ 3 ч — не всенощное бдение) и за эту ночь ещё не здоровались.
    /// Звать после note: так заход, когда Шиба ещё спал, тоже считается — поздороваемся на следующем.
    static func greetingDue(_ log: SleepLog, now: Double, tzOffsetMin tz: Int) -> Int? {
        let (day, m) = local(now, tzOffsetMin: tz)
        guard m >= mornFrom, m < greetTo, let woke = log.wokeT else { return nil }
        let w = local(woke, tzOffsetMin: tz)
        guard w.day == day, w.min >= mornFrom, w.min < greetTo else { return nil }
        let night = day - 1
        return log.greeted == night ? nil : night
    }

    /// Ночь, в которую пора предложить «Отбой», или nil. Только когда окно выучено или задано: за 15 минут до
    /// «засыпаю» хозяина и до 45 минут после, если Шиба ложится иначе (bedMin дальше 20 минут) и кнопка видна
    /// (лампа 20:00–02:00). Раз за ночь.
    static func bedHintDue(_ log: SleepLog, est: SleepEstimate, bedMin: Int, now: Double, tzOffsetMin tz: Int) -> Int? {
        guard !est.isLearning else { return nil }
        let (day, m) = local(now, tzOffsetMin: tz)
        guard m >= 20 * 60 || m < 2 * 60 else { return nil }
        guard circDiff(est.window.bed, bedMin) >= 20 else { return nil }
        guard inWindow(m, est.window.bed - 15, est.window.bed + 45) else { return nil }
        let night = m >= eveFrom ? day : day - 1
        return log.hinted == night ? nil : night
    }

    /// «Ложусь в» как у хозяина: выученное «засыпаю», прижатое к выбору настроек (20:00–02:00).
    /// nil — окно ещё не выучено (и не задано) или уже совпадает с bedMin (разница меньше 20 минут).
    static func suggestedBed(_ est: SleepEstimate, bedMin: Int) -> Int? {
        guard !est.isLearning else { return nil }
        let x = min(max(noonRel(est.window.bed), 8 * 60), 14 * 60)
        let m = clock(round5(x))
        return circDiff(m, bedMin) >= 20 ? m : nil
    }

    /// «00:40–08:10».
    static func text(_ w: SleepWindow) -> String { "\(hm(w.bed))–\(hm(w.wake))" }

    /// «учится сам», «задано вручную», «пока учусь: 2 из 5 ночей».
    static func status(_ est: SleepEstimate) -> String {
        switch est.source {
        case .manual: return "задано вручную"
        case .learned: return "учится сам"
        case .learning(let k): return "пока учусь: \(k) из \(minNights) ночей"
        }
    }

    static func hm(_ m: Int) -> String {
        let v = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", v / 60, v % 60)
    }
}
