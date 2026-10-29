// Волна 34 J: что рисовать на островке (Dynamic Island) и в виджете. Чистые функции поверх IslandEvents (§8):
// входы из сейва (копилка двора, поход, новый уровень), карточка события для Live Activity, пиксельный пёс
// (кадры поз), вид кадра виджета (шкалы, кольцо копилки, небо по времени суток, ярус двора) и «Собрать» из виджета.
// Только Foundation и PetCore: гоняется на Linux. Вью — Shared/Views/IslandEventViews.swift и WidgetScreenViews.swift.

import Foundation
@preconcurrency import PetCore

// MARK: - Входы из сейва

/// Копилка, поход и уровень из сейва — то, что IslandEvents принимает параметрами (Yard, Places, DogLevel).
enum IslandFeed {
    /// Копилка двора: когда полна, с какого момента копится (для кольца), сколько монет в полной. nil — станций нет.
    static func bank(_ f: SaveFile, now: Double, _ cfg: YardConfig = .shared) -> IslandBank? {
        let lv = DogLevel.level(f)
        guard let full = Yard.fullAt(f.yard, now: now, dogLevel: lv, cfg) else { return nil }
        let c = Yard.peek(f.yard, now: now, dogLevel: lv, cfg)
        let cap = Yard.cap(rate: Yard.rate(c, dogLevel: lv, cfg), cfg)
        // Ставка постоянная: от пустой до полной — ровно bankHours. Кольцо в момент t — та же доля, что bank/cap.
        let from = full - cfg.bankHours * 3600
        return IslandBank(fullAt: full, from: from, coins: Int(max(cap, c.bank).rounded(.down)))
    }

    /// Поход на место: идёт — до until; кончился недавно (последний итог) — «Я дома!» от его времени.
    /// nil — не ходил: IslandEvents сам посмотрит прогулку ядра.
    static func trip(_ f: SaveFile, now: Double, _ cfg: IslandEventsConfig = .shared) -> IslandTrip? {
        if let a = f.trip.active {
            let name = Places.place(a.place)?.name ?? "Прогулка"
            return IslandTrip(from: a.start, backAt: a.until, place: name)
        }
        if let r = f.trip.last, r.t <= now, now - r.t < cfg.homeHoldS {
            return IslandTrip(from: nil, backAt: r.t, place: Places.place(r.place)?.name ?? "Прогулка")
        }
        return nil
    }

    /// Новый уровень пса: «★14» на levelHoldS после него.
    static func levelUp(_ f: SaveFile) -> IslandLevelUp? {
        f.level.lastUp.map { IslandLevelUp(level: $0.level, at: $0.t) }
    }

    /// Волна 45 O: просьба пса, открытая на now (та же, что плашка дома, — DogAsks.current).
    /// nil, если пёс спит, гуляет, моется или в походе: островок его не будит и не зовёт туда, где его нет.
    static func ask(_ f: SaveFile, now: Double, _ cfg: DogAskConfig = .shared) -> IslandAsk? {
        guard let a = DogAsks.current(f, now: now, cfg), let k = a.kind else { return nil }
        if let tr = f.trip.active, now < tr.until { return nil }
        let s = PetRunner.peek(f, at: now)
        guard s.alive, s.napUntil == nil, s.outing == nil, s.bathUntil == nil else { return nil }
        return IslandAsk(kind: k, start: a.start, end: a.start + cfg.window, coins: a.coins)
    }

    /// Вход выбора острова целиком из сейва.
    static func input(_ f: SaveFile, now: Double, tzOffsetMin: Int? = nil,
                      _ cfg: IslandEventsConfig = .shared) -> IslandInput {
        var i = IslandEvents.input(f, at: now, trip: trip(f, now: now, cfg), bank: bank(f, now: now),
                                   levelUp: levelUp(f), tzOffsetMin: tzOffsetMin, cfg)
        i.ask = ask(f, now: now)
        return i
    }

    /// Ярус двора (0 — подоконник) и его имя.
    static func yardTier(_ f: SaveFile, _ cfg: YardConfig = .shared) -> (index: Int, name: String) {
        let i = min(max(0, HomeShop.level(f, .yard)), max(0, cfg.maxTier))
        let name = cfg.tiers.indices.contains(i) ? cfg.tiers[i].name : ""
        return (i, name)
    }
}

// MARK: - Карточка острова

/// Значок события: следы, сердце, миска, пёс-точка на полоске, домик, облачко просьбы, свинка, звезда;
/// calm — тихий вид.
enum IslandGlyph: String, Codable, CaseIterable, Hashable, Sendable {
    case tracks, heart, bowl, trip, home, ask, piggy, star, calm

    init(_ k: IslandEvent.Kind) {
        switch k {
        case .runaway: self = .tracks
        case .lastChance: self = .heart
        case .hungry: self = .bowl
        case .trip: self = .trip
        case .home: self = .home
        case .ask: self = .ask
        case .bank: self = .piggy
        case .levelUp: self = .star
        }
    }

    /// SF Symbol для мест, где пиксельный значок мелковат (минимальный остров, экран блокировки).
    var symbol: String {
        switch self {
        case .tracks: return "pawprint.fill"
        case .heart: return "heart.fill"
        case .bowl: return "fork.knife"
        case .trip: return "figure.walk"
        case .home: return "house.fill"
        case .ask: return "bubble.left.fill"
        case .piggy: return "dollarsign.circle.fill"
        case .star: return "star.fill"
        case .calm: return "pawprint"
        }
    }
}

/// Что показывает компакт справа: таймер, кольцо копилки или короткую подпись.
enum IslandTrailing: String, Codable, Hashable, Sendable {
    case timer, ring, text
}

/// Событие острова в плоском виде: едет в ContentState (Codable), вью рисует по нему без ядра.
struct IslandCard: Codable, Hashable, Sendable {
    /// nil — тихий вид (событие кончилось, а активность сама себя не закроет).
    var kind: IslandEvent.Kind?
    var glyph: IslandGlyph
    var title: String
    var detail: String?
    var compact: String
    var pose: DogPose
    var from: Double
    var until: Double?
    var timerEnd: Double?
    var progressFrom: Double?
    var ring: Double?
    /// Кнопка развёрнутого вида: голод — «Покормить», дома — «Погладить», сердечко — спасающая, остальное — «Открыть».
    var act: IslandAct

    /// Компакт справа.
    var trailing: IslandTrailing {
        switch kind {
        case .lastChance?, .trip?, .runaway?, .ask?: return timerEnd != nil ? .timer : .text
        case .bank?: return .ring
        default: return .text
        }
    }

    /// Полоска похода есть, только если известно начало.
    var hasProgress: Bool { progressFrom != nil && timerEnd != nil && (timerEnd ?? 0) > (progressFrom ?? 0) }

    /// Доля пройденного пути похода в момент t (0…1) — где стоит пёс-точка на полоске.
    func progress(at t: Double) -> Double {
        guard let a = progressFrom, let b = timerEnd, b > a else { return 0 }
        return min(1, max(0, (t - a) / (b - a)))
    }

    /// Кнопка выполняет действие, не открывая приложение.
    var actsInPlace: Bool { act.action != nil }
}

enum IslandLook {
    /// Карточка события. pending — событие ещё не началось (ранний старт): заголовок — «Проголодается к 18:40».
    static func card(_ e: IslandEvent, pending: Bool = false, pick: IslandPick? = nil) -> IslandCard {
        IslandCard(kind: e.kind, glyph: IslandGlyph(e.kind), title: pending ? e.soon : e.title,
                   detail: pending ? nil : e.detail, compact: e.compact, pose: e.pose, from: e.from, until: e.until,
                   timerEnd: e.timerEnd, progressFrom: e.progressFrom, ring: e.ring,
                   act: IslandPlan.act(for: e.kind, pick: pick, ask: e.ask))
    }

    /// Тихий вид: событие прошло, а нового нет. Ночью хозяина — спит, днём — «Всё хорошо».
    static func rest(name: String, night: Bool, at t: Double) -> IslandCard {
        IslandCard(kind: nil, glyph: .calm, title: night ? "\(name) спит" : "Всё хорошо",
                   detail: night ? nil : "\(name) дома", compact: "", pose: night ? .sleep : .sit, from: t,
                   until: nil, timerEnd: nil, progressFrom: nil, ring: nil, act: .open)
    }

    /// Что положить в ContentState: вид сейчас и вид после staleDate.
    /// pickNow/pickAfter — что ядро примет сейчас и в момент stale (для кнопки «последнего сердечка»).
    static func cards(_ show: IslandShow, _ i: IslandInput, pickNow: IslandPick? = nil,
                      pickAfter: IslandPick? = nil) -> (now: IslandCard?, next: IslandCard?) {
        guard let cur = show.current else { return (nil, nil) }
        let now = card(cur, pending: show.pending, pick: pickNow)
        guard let s = show.staleDate else { return (now, nil) }
        if let a = show.after { return (now, card(a, pick: pickAfter)) }
        return (now, rest(name: i.name, night: i.quiet?.asleep(s) ?? false, at: s))
    }

    /// Что показывать: до stale — карточку, после — следующую (без неё — ту же: тихо гаснуть не умеем).
    static func shown(_ card: IslandCard?, next: IslandCard?, stale: Bool) -> IslandCard? {
        stale ? (next ?? card) : card
    }

    /// Остаток таймера как у системного отсчёта: «40:00», «1:30:00», «0:05». Для снимков (petFrozenNow):
    /// Text(timerInterval:pauseTime:) на паузе показывает прошедшее, а не остаток.
    static func countdown(_ seconds: Double) -> String {
        let s = seconds.isFinite ? max(0, Int(seconds.rounded(.up))) : 0
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        let ss = sec < 10 ? "0\(sec)" : "\(sec)"
        if h > 0 { return "\(h):\(m < 10 ? "0" : "")\(m):\(ss)" }
        return "\(m):\(ss)"
    }
}

// MARK: - Пиксельный пёс

/// Цвет клетки пиксельного пса. Буквы — в строках кадров.
enum PixelInk: Character, CaseIterable, Hashable, Sendable {
    case outline = "o", fur = "f", dark = "d", cream = "c", eye = "e", bowl = "b", zz = "z"
}

struct PixelCell: Hashable, Sendable {
    var x: Int
    var y: Int
    var ink: PixelInk
}

/// Пёс 16×12 клеток, смотрит вправо. У каждой позы 2–3 кадра одного размера, цикл не дольше 2 с.
/// Рисует вью Path'ами (без картинок). В Live Activity и виджете система кадры не крутит — там стоит первый.
enum PixelDog {
    static let width = 16
    static let height = 12
    /// Длина кадра: 3 кадра × 0,5 с = 1,5 с — в пределах 2 с.
    static let frameS: Double = 0.5

    private static let sitA = [
        "................",
        "..........o..o..",
        ".........ofoofo.",
        ".........offffo.",
        "..oo.....ofefcco",
        ".offo....offccce",
        ".ofco...offfcco.",
        "..ooffffffffco..",
        "...offffffffco..",
        "...offffffffco..",
        "...ofcoofcoocco.",
        "...oooooooooooo.",
    ]
    private static let sitB = [
        "................",
        "..........o..o..",
        ".........ofoofo.",
        ".........offffo.",
        "...oo....ofefcco",
        "..offo...offccce",
        "..ocfo..offfcco.",
        "..ooffffffffco..",
        "...offffffffco..",
        "...offffffffco..",
        "...ofcoofcoocco.",
        "...oooooooooooo.",
    ]
    private static let lieA = [
        "................",
        "................",
        "................",
        "................",
        "................",
        "..........o..o..",
        ".........ofoofo.",
        ".oo......offffo.",
        "offooooooofeccco",
        ".offffffffffccce",
        ".offfffffffcccco",
        ".oooooooooooooo.",
    ]
    private static let lieB = [
        "................",
        "................",
        "................",
        "................",
        "................",
        "..........o..o..",
        ".........ofoofo.",
        "oo.......offffo.",
        "offooooooofoccco",
        ".offffffffffccce",
        ".offfffffffcccco",
        ".oooooooooooooo.",
    ]
    private static let sleepA = [
        "................",
        "................",
        "................",
        ".............z..",
        "................",
        "..........o..o..",
        ".........ofoofo.",
        ".oo......offffo.",
        "offooooooofoccco",
        ".offffffffffccce",
        ".offfffffffcccco",
        ".oooooooooooooo.",
    ]
    private static let sleepB = [
        "................",
        "..............z.",
        "................",
        "............z...",
        "................",
        "..........o..o..",
        ".........ofoofo.",
        ".oo......offffo.",
        "offooooooofoccco",
        ".offffffffffccce",
        ".offfffffffcccco",
        ".oooooooooooooo.",
    ]
    private static let eatA = [
        "................",
        "................",
        "................",
        "................",
        ".oo....o..o.....",
        "offo..ofoofo....",
        ".ofoooofffffo...",
        "..offffffeffo...",
        "..offffffoccco..",
        "..offfffffocce..",
        "..ofcooofcbbbbbb",
        "..oooooooo.bbbb.",
    ]
    private static let eatB = [
        "................",
        "................",
        "................",
        "................",
        ".oo....o..o.....",
        "offo..ofoofo....",
        ".ofoooofffffo...",
        "..offffffeffo...",
        "..offffffffoccco",
        "..offffffffoccce",
        "..ofcooofcbcbcbb",
        "..oooooooo.bbbb.",
    ]
    private static let bowlA = [
        "................",
        "................",
        ".......o..o.....",
        "......ofoofo....",
        "..oo..offffo....",
        ".offo.ofefcco...",
        ".ofco.offccce...",
        "..ooffffffco....",
        "...offffffco....",
        "...offffffco....",
        "...ofcoofcco.bbb",
        "...oooooooooobbb",
    ]
    private static let bowlB = [
        "................",
        "................",
        ".......o...o....",
        "......ofooofo...",
        "..oo..offfffo...",
        ".offo.ofefcco...",
        ".ofco.offccce...",
        "..ooffffffco....",
        "...offffffco....",
        "...offffffco....",
        "...ofcoofcco.bbb",
        "...oooooooooobbb",
    ]
    private static let empty = Array(repeating: "................", count: 8)
    private static let awayA = empty + [
        ".dd.............",
        ".dd.............",
        "....dd..........",
        "....dd..........",
    ]
    private static let awayB = empty + [
        ".dd....dd.......",
        ".dd....dd.......",
        "....dd..........",
        "....dd..........",
    ]
    private static let awayC = empty + [
        ".dd....dd.......",
        ".dd....dd.......",
        "....dd....dd....",
        "....dd....dd....",
    ]

    /// Кадры позы по порядку.
    static func frames(_ p: DogPose) -> [[String]] {
        switch p {
        case .sit: return [sitA, sitB]
        case .lie: return [lieA, lieB]
        case .sleep: return [sleepA, sleepB]
        case .eat: return [eatA, eatB]
        case .bowl: return [bowlA, bowlB]
        case .away: return [awayA, awayB, awayC]
        }
    }

    static func cycleS(_ p: DogPose) -> Double { Double(frames(p).count) * frameS }

    /// Номер кадра в момент t (секунды): шаг frameS, по кругу.
    static func frameIndex(_ p: DogPose, at t: Double) -> Int {
        let n = frames(p).count
        guard n > 1, t.isFinite else { return 0 }
        let k = Int((t / frameS).rounded(.down)) % n
        return (k + n) % n
    }

    /// Закрашенные клетки кадра.
    static func cells(_ p: DogPose, frame i: Int) -> [PixelCell] {
        let fs = frames(p)
        guard !fs.isEmpty else { return [] }
        return cells(fs[((i % fs.count) + fs.count) % fs.count])
    }

    static func cells(_ rows: [String]) -> [PixelCell] {
        var out: [PixelCell] = []
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                if let ink = PixelInk(rawValue: ch) { out.append(PixelCell(x: x, y: y, ink: ink)) }
            }
        }
        return out
    }
}

// MARK: - Виджет

/// Небо за псом по местному часу.
enum SkyPhase: String, CaseIterable, Hashable, Sendable {
    case dawn, day, dusk, night

    /// Рассвет 5–8, день 8–18, вечер 18–21, ночь 21–5.
    static func at(_ t: Double, tz: Int) -> SkyPhase {
        let m = ((Int((t / 60).rounded(.down)) + tz) % 1440 + 1440) % 1440
        switch m / 60 {
        case 5..<8: return .dawn
        case 8..<18: return .day
        case 18..<21: return .dusk
        default: return .night
        }
    }
}

/// Что на экране блокировки: таймер похода, кольцо копилки или просто силуэт.
enum WidgetLockMode: String, Hashable, Sendable {
    case trip, ring, pose
}

struct WidgetBar: Hashable, Sendable {
    var need: Need
    var value: Int
}

/// Вид одного кадра виджета: всё посчитано, вью только рисует.
struct WidgetLook: Hashable, Sendable {
    var t: Double
    var pose: DogPose
    var alive: Bool
    /// Короткая подпись под псом: «Всё хорошо», «Ждёт у миски», «Маяк · вернётся в 14:20».
    var caption: String
    /// Главная шкала — самая низкая из видимых.
    var main: WidgetBar?
    /// Три самые низкие шкалы в обычном порядке (medium).
    var bars: [WidgetBar]
    var ring: Double?
    /// Монет в копилке на момент кадра и в полной.
    var coins: Int?
    var coinsFull: Int?
    /// «+214 · полная в 21:10» или «+412 · собери!»; nil — копилки нет.
    var bankLine: String?
    var bankFull: Bool
    var tripFrom: Double?
    var tripUntil: Double?
    var sky: SkyPhase
    var tier: Int
    var tierName: String
    var lock: WidgetLockMode
    /// Размер пса по росту: щенок мельче.
    var dogScale: Double
    /// Волна 45 O: просьба пса на кадре — caption тогда плашка «Почеши за ушком? · ещё 40 мин» (как дома),
    /// askEmoji — значок перед ней, askEnd — конец окна. nil — просьбы нет.
    var ask: String? = nil
    var askEmoji: String? = nil
    var askEnd: Double? = nil

    /// Порядок шкал (как VisibleNeeds.all в приложении).
    static let order: [Need] = [.food, .clean, .energy, .fun, .love, .walk]

    /// Кнопка «Собрать» в medium: в копилке что-то есть. В small — только полная.
    var canCollect: Bool { alive && (coins ?? 0) > 0 }

    /// Доля пройденного похода в момент кадра.
    var tripProgress: Double? {
        guard let b = tripUntil, let a = tripFrom, b > a else { return nil }
        return min(1, max(0, (t - a) / (b - a)))
    }

    /// Smart Stack: поднять виджет, когда что-то нужно.
    var relevance: Float {
        guard alive else { return 0 }
        let base: Float
        switch pose {
        case .bowl: base = 0.8
        case .lie: base = 0.4
        default: base = bankFull ? 0.6 : 0.1
        }
        // Просьба уходит через час: поднять выше «Всё хорошо», но не выше голода.
        return ask != nil ? max(base, 0.5) : base
    }

    static func caption(_ fr: PoseFrame) -> String {
        if let n = fr.note { return n }
        switch fr.pose {
        case .sit: return "Всё хорошо"
        case .lie: return "Заскучал"
        default: return fr.pose.title
        }
    }

    /// Самые низкие шкалы: n штук в обычном порядке. Равные — по порядку.
    static func lowest(_ bars: [Need: Int], _ n: Int) -> [WidgetBar] {
        let all = order.map { WidgetBar(need: $0, value: bars[$0] ?? 0) }
        let pick = all.enumerated().sorted { a, b in
            a.element.value != b.element.value ? a.element.value < b.element.value : a.offset < b.offset
        }.prefix(n).map(\.offset)
        return pick.sorted().map { all[$0] }
    }

    static func bankLine(coins: Int, full: Bool, fullAt: Double, tz: Int) -> String {
        full ? "+\(coins) · собери!" : "+\(coins) · полная в \(IslandEvents.hm(fullAt, tz: tz))"
    }

    static func make(_ fr: PoseFrame, bank: IslandBank?, trip: IslandTrip?, tier: Int, tierName: String,
                     tz: Int, dogScale: Double = 1,
                     askWindow: Double = DogAskConfig.shared.window) -> WidgetLook {
        let ring = fr.ring
        let full = fr.bankFull
        var coins: Int?
        var line: String?
        if let b = bank, let r = ring {
            let c = Int((Double(b.coins ?? 0) * r).rounded(.down))
            coins = c
            line = bankLine(coins: c, full: full, fullAt: b.fullAt, tz: tz)
        }
        // Полоска похода — только у похода с известным началом и только пока он идёт.
        var from: Double?
        if let u = fr.tripUntil, let tr = trip, tr.backAt == u { from = tr.from }
        let lowest = lowest(fr.bars, 3)
        let lock: WidgetLockMode = fr.tripUntil != nil && fr.alive ? .trip : (ring != nil ? .ring : .pose)
        var look = WidgetLook(t: fr.t, pose: fr.pose, alive: fr.alive, caption: caption(fr),
                              main: Self.lowest(fr.bars, 1).first, bars: lowest, ring: ring, coins: coins,
                              coinsFull: bank?.coins, bankLine: line, bankFull: full, tripFrom: from,
                              tripUntil: fr.tripUntil, sky: SkyPhase.at(fr.t, tz: tz), tier: tier, tierName: tierName,
                              lock: lock, dogScale: min(1, max(0.7, dogScale)))
        // Просьба: та же плашка, что дома (DogAskText.plate), минуты — на момент кадра.
        if let a = fr.ask, let k = a.kind {
            look.caption = DogAskText.plate(a, now: fr.t)
            look.ask = look.caption
            look.askEmoji = DogAskText.emoji(k)
            look.askEnd = a.start + askWindow
        }
        return look
    }

    /// Кадры виджета из сейва: 24 шт., сейчас и дальше по :00/:30 на 12 ч; в окнах просьб пса — ещё раз в 5 мин.
    /// asks: nil — посчитать из сейва (DogAsks.upcoming, то же расписание, что у приложения); [] — без просьб.
    static func looks(_ f: SaveFile, now: Double, tzOffsetMin: Int? = nil, asks: [DogAsk]? = nil,
                      _ cfg: IslandEventsConfig = .shared) -> [WidgetLook] {
        let tz = tzOffsetMin ?? Clock.tzOffsetMin(at: now)
        let bank = IslandFeed.bank(f, now: now)
        // Поход на место; без него — прогулка ядра (тогда тоже полоска с пёсиком-точкой).
        var trip = f.trip.active != nil ? IslandFeed.trip(f, now: now, cfg) : nil
        if trip == nil, let w = PetRunner.peek(f, at: now).outing {
            trip = IslandTrip(from: w.from, backAt: w.until, place: "Гуляет")
        }
        let until = (IslandEvents.frameTimes(now: now, cfg).last ?? now) + 1
        let a = asks ?? DogAsks.upcoming(f, now: now, until: until)
        let frames = IslandEvents.widget(f, now: now, trip: trip, bank: bank, tzOffsetMin: tzOffsetMin, asks: a, cfg)
        let tier = IslandFeed.yardTier(f)
        let scale = Growth.look(f).scale
        return frames.map {
            make($0, bank: bank, trip: trip, tier: tier.index, tierName: tier.name, tz: tz, dogScale: scale)
        }
    }

    /// Когда просить новый timeline: после последнего кадра (шаг сетки), но не раньше чем через минуту.
    static func reloadT(_ looks: [WidgetLook], now: Double, _ cfg: IslandEventsConfig = .shared) -> Double {
        max(now + 60, (looks.last?.t ?? now) + max(60, cfg.widgetStepS))
    }

    /// «Собрать» из виджета: копилка в кошелёк без открытия приложения. Сначала догоняем ядро (как любое действие),
    /// после сбора — опыт пса по журналу (yard.collect даёт 4 XP).
    @discardableResult
    static func collect(in f: inout SaveFile, now: Double) -> YardHarvest {
        PetRunner.catchUp(&f, now: now)
        let h = Yard.collect(in: &f, now: now, dogLevel: DogLevel.level(f))
        // Опыт и достижение за добитый уровень — в эту же запись (волна 42 I).
        PetRunner.settleRewards(&f, now: now)
        return h
    }
}
