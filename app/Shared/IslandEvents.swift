// Волна 33 E: что показать на островке (Dynamic Island) и в виджете. RESEARCH/20-tycoon-design.md §8.
//
// Островок: пёс появляется, только когда что-то происходит. Одно событие за раз (как Hush), главное — по таблице §8:
//   1 убежал / следы → 2 последнее сердечко → 3 голоден → 4 возвращается с места, «Я дома!» → 5 копилка полна →
//   6 новый уровень (короткая активность на 15 мин).
// Волна 45 O: между «Я дома!» и копилкой — просьба пса (DogAsks): «Почеши за ушком?» и таймер до конца окна.
// Только текущая (уже открытая) просьба и никогда не вид после stale — см. choose и DECISIONS «Волна 45 O».
// «Всё хорошо» и ночь хозяина (окно сна из сейва, то же, что глушит уведомления) — островок пустой, активности нет
// (решение 7а). Live Activity снаружи не обновить, есть одно переключение по staleDate. Поэтому при уходе в фон
// считаем, когда картинка сменится (начало или конец события, начало ночи, утро), кладём это время в staleDate,
// а вид после stale — событие, которое будет главным в тот момент. Дальше нужен заход в приложение.
//
// Виджет: 24 кадра раз в 30 мин на 12 ч вперёд, 6 поз пса (сидит, лежит, спит, ест, ждёт у миски, нет дома).
// Волна 45 O: в окне просьбы — ещё кадры раз в 5 мин (widgetAskStepS), чтобы «ещё N мин» не врало.
// Ядро крутится без действий, как в ForecastTools.timeline.
//
// Копилка двора (bankFullAt) и поход (tripBackAt) приходят параметрами: Yard и Places пишут другие агенты.
// Только Foundation и PetCore: гоняется на Linux. UI подключат в волне 34.

import Foundation
@preconcurrency import PetCore

/// Числа островка и виджета. Значения по умолчанию — здесь; кусок `island_events` в economy.json их переопределяет.
struct IslandEventsConfig: Hashable, Sendable {
    /// Сколько висит «Я дома!» после возвращения с места.
    var homeHoldS: Double = 3600
    /// Короткая активность «★14» после нового уровня.
    var levelHoldS: Double = 900
    /// Live Activity живёт до 8 ч: staleDate дальше не ставим.
    var maxStaleH: Double = 8
    /// На сколько часов вперёд смотреть прогноз для острова.
    var forecastH: Double = 48
    /// Запускать активность заранее с текстом «Проголодается к 18:40». Решение 7а: нет, в тихое время пусто.
    var startEarly = false
    /// Шаг и число кадров виджета: 24 × 30 мин = 12 ч.
    var widgetStepS: Double = 1800
    var widgetEntries = 24
    /// Волна 45 O: шаг кадров виджета в окне просьбы пса — «ещё N мин» обновляется так часто.
    var widgetAskStepS: Double = 300
    /// Ниже этой бодрости пёс в виджете лежит.
    var lieEnergy: Double = 30

    static let shared = IslandEventsConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        let c = e["island_events"]
        guard !c.object.isEmpty else { return }
        if let v = c["home_hold_s"].double { homeHoldS = v }
        if let v = c["level_hold_s"].double { levelHoldS = v }
        if let v = c["max_stale_h"].double { maxStaleH = v }
        if let v = c["forecast_h"].double { forecastH = v }
        if let v = c["start_early"].bool { startEarly = v }
        if let v = c["widget_step_s"].double { widgetStepS = v }
        if let v = c["widget_entries"].double { widgetEntries = Int(v) }
        if let v = c["widget_ask_step_s"].double { widgetAskStepS = v }
        if let v = c["lie_energy"].double { lieEnergy = v }
    }
}

/// Поза пса в виджете и компакте островка (6 поз §8). Не путать с Pose из Presenter: там настроения для 3D.
enum DogPose: String, Codable, CaseIterable, Hashable, Sendable {
    case sit, lie, sleep, eat, bowl, away

    var title: String {
        switch self {
        case .sit: return "Сидит"
        case .lie: return "Лежит"
        case .sleep: return "Спит"
        case .eat: return "Ест"
        case .bowl: return "Ждёт у миски"
        case .away: return "Нет дома"
        }
    }
}

/// Поход на место (Places). backAt — tripBackAt; from — для полоски, nil — без полоски.
struct IslandTrip: Hashable, Sendable {
    var from: Double?
    var backAt: Double
    var place: String
}

/// Копилка двора (Yard). fullAt — bankFullAt; from — с какого момента копится (для кольца); coins — сколько будет в полной.
struct IslandBank: Hashable, Sendable {
    var fullAt: Double
    var from: Double?
    var coins: Int?

    /// Заполнение кольца в момент t: 0…1; без from — только «полна или нет».
    func ring(at t: Double) -> Double {
        if t >= fullAt { return 1 }
        guard let a = from, fullAt > a else { return 0 }
        return min(1, max(0, (t - a) / (fullAt - a)))
    }
}

/// Новый уровень пса (DogLevel): какой и когда хозяин его увидел.
struct IslandLevelUp: Hashable, Sendable {
    var level: Int
    var at: Double
}

/// Волна 45 O: открытая просьба пса (DogAsks). kind — "feed", "pet", …; end — конец окна.
struct IslandAsk: Hashable, Sendable {
    var kind: String
    var start: Double
    var end: Double
    var coins: Int

    var ask: DogAsk { DogAsk(start: start, kind: kind, coins: coins) }
}

/// Окно сна хозяина в местных минутах (NotificationPlanner.quietHours) и пояс.
struct IslandQuiet: Hashable, Sendable {
    var from: Int
    var to: Int
    var tzOffsetMin: Int

    private func local(_ t: Double) -> Int {
        ((Int((t / 60).rounded(.down)) + tzOffsetMin) % 1440 + 1440) % 1440
    }

    func asleep(_ t: Double) -> Bool { OwnerSleep.inWindow(local(t), from, to) }

    /// Ближайшая минута после t, где сон начинается или кончается; nil — окна нет (from == to).
    func nextEdge(after t: Double) -> Double? {
        guard ((from - to) % 1440 + 1440) % 1440 != 0 else { return nil }
        let base = (t / 60).rounded(.down) * 60
        let m = local(t)
        func d(_ e: Int) -> Int {
            let x = ((e - m) % 1440 + 1440) % 1440
            return x == 0 ? 1440 : x
        }
        return base + Double(min(d(from), d(to))) * 60
    }
}

/// Отрезок времени [from, until); until nil — до захода в приложение.
struct IslandSpan: Hashable, Sendable {
    var from: Double
    var until: Double?
}

/// Что ядро обещает, если никто не придёт: когда последнее сердечко, когда побег, когда голоден.
struct IslandOutlook: Hashable, Sendable {
    var lastChanceAt: Double?
    var deathAt: Double?
    /// Голод (еда < warn_low): от начала до кормушки, что подняла еду выше порога, или до побега.
    var hunger: [IslandSpan] = []
}

/// Вход выбора: всё уже посчитано на момент now. Чистые данные — для тестов без сейва.
struct IslandInput: Hashable, Sendable {
    var now: Double
    var name: String
    var alive: Bool
    var outlook: IslandOutlook
    var trip: IslandTrip?
    var bank: IslandBank?
    var levelUp: IslandLevelUp?
    /// Побег уже идёт (Runaway.status); nil — пёс дома.
    var runaway: Runaway.Status?
    /// Прогнозный побег будет насовсем (третий за окно) или побеги выключены — «Найди» не показываем.
    var runawayClosed = false
    var searchH: Double = 72
    var trailsNeed = 2
    var quiet: IslandQuiet?
    /// Пояс для подписей «к 18:40».
    var tzOffsetMin = 0
    /// Волна 45 O: просьба пса, открытая на now; nil — нет (или пёс спит, гуляет, моется, в походе).
    var ask: IslandAsk?
}

/// Событие островка: когда идёт, что писать до начала и во время.
struct IslandEvent: Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case runaway, lastChance, hungry, trip, home, ask, bank, levelUp

        /// Приоритет по таблице §8: меньше — главнее. Поход и «Я дома!» — одна строка, по времени не пересекаются.
        /// Просьба (волна 45 O) — выше копилки: она уходит через час, копилка ждёт.
        var rank: Int {
            switch self {
            case .runaway: return 1
            case .lastChance: return 2
            case .hungry: return 3
            case .trip, .home: return 4
            case .ask: return 5
            case .bank: return 6
            case .levelUp: return 7
            }
        }
    }

    var kind: Kind
    var from: Double
    /// nil — пока хозяин не зайдёт.
    var until: Double?
    /// Развёрнутый вид, когда событие идёт: «Голоден!», «Найди Шибу: 1/2 следа, 41 ч».
    var title: String
    /// Строка под заголовком; nil — без неё.
    var detail: String?
    /// До начала (ранний или отложенный старт): «Проголодается к 18:40».
    var soon: String
    /// Подпись компакта: «1/2», «★14», «+412».
    var compact: String
    var pose: DogPose
    /// Конец таймера (Text(timerInterval:)); progressFrom — начало полоски.
    var timerEnd: Double?
    var progressFrom: Double?
    /// Кольцо копилки 0…1.
    var ring: Double?
    /// Волна 45 O: что просит пёс (для кнопки на островке); только у .ask.
    var ask: String? = nil

    func on(_ t: Double) -> Bool { t >= from && (until.map { t < $0 } ?? true) }
}

/// Что делать с островком при уходе в фон.
struct IslandShow: Hashable, Sendable {
    /// Что на островке сейчас; nil — островок пустой, активность не запускать (или закончить).
    var current: IslandEvent?
    /// current ещё не наступило (ранний старт): показывать current.soon.
    var pending = false
    /// Когда картинка сменится: начало или конец события, ночь, утро. nil — ничего не изменится.
    var staleDate: Double?
    /// Вид после stale; nil — после stale островок пустеет (активность закончить).
    var after: IslandEvent?

    /// Нужна ли Live Activity прямо сейчас.
    var activity: Bool { current != nil }
    var stale: Date? { staleDate.map { Date(timeIntervalSince1970: $0) } }
}

/// Кадр виджета.
struct PoseFrame: Hashable, Sendable {
    var t: Double
    var pose: DogPose
    /// Записка «нет дома»: «Маяк · вернётся в 14:20».
    var note: String?
    /// Шкалы 0…100 на момент кадра.
    var bars: [Need: Int]
    /// Кольцо копилки 0…1; nil — копилки нет.
    var ring: Double?
    var tripUntil: Double?
    var alive: Bool
    /// Волна 45 O: просьба пса, открытая в момент кадра; nil — нет или пёс спит, нет дома, моется.
    var ask: DogAsk? = nil

    var food: Int { bars[.food] ?? 0 }
    var bankFull: Bool { (ring ?? 0) >= 1 }
}

enum IslandEvents {
    /// Шаг ядра (PetEngine.STEP внутренний): событие кормушки стоит в начале шага, еда видна в его конце.
    private static let coreStepS: Double = 60

    // MARK: выбор события

    /// Время «18:40» в поясе tz.
    static func hm(_ t: Double, tz: Int) -> String {
        OwnerSleep.hm(PetEngine.localMin(t, Owner(bedMin: 0, wakeMin: 0, tzOffsetMin: tz)))
    }

    /// «1/2 следа», «0/1 след», «3/5 следов», «0/11 следов»: слово согласовано с числом рядом — всего следов
    /// (волна 36 O; было всегда «следа»).
    static func trailsText(_ trails: Int, _ need: Int) -> String {
        "\(trails)/\(need) " + EconText.plural(need, "след", "следа", "следов")
    }

    /// Все события, что идут сейчас или начнутся в горизонте прогноза.
    static func candidates(_ i: IslandInput, _ cfg: IslandEventsConfig = .shared) -> [IslandEvent] {
        let now = i.now
        func hm(_ t: Double) -> String { Self.hm(t, tz: i.tzOffsetMin) }
        var out: [IslandEvent] = []

        func runaway(from: Double, until: Double, trails: Int, need: Int, found: Bool) -> IslandEvent {
            let h = Int(max(0, until - max(now, from)) / 3600)
            return IslandEvent(kind: .runaway, from: from, until: until,
                               title: found ? "\(i.name) нашёлся!" : "Найди \(i.name): \(trailsText(trails, need)), \(h) ч",
                               detail: found ? "Верни домой" : "Ищи по следам или шагами",
                               soon: "Может убежать к \(hm(from))", compact: found ? "✓" : "\(trails)/\(need)",
                               pose: .away, timerEnd: until, progressFrom: nil, ring: nil)
        }

        // 1. Побег: уже идёт — по статусу; ещё нет — с момента прогнозного последнего сердечка.
        if !i.alive {
            if let st = i.runaway, st.canReturn {
                out.append(runaway(from: now, until: now + st.hoursLeft * 3600,
                                   trails: st.trails, need: st.trailsNeed, found: st.found))
            }
            // Мёртвый пёс: остальное не показываем; насовсем потерян — островок пустой.
            return out
        }
        if let d = i.outlook.deathAt, !i.runawayClosed {
            out.append(runaway(from: d, until: d + i.searchH * 3600, trails: 0, need: i.trailsNeed, found: false))
        }

        // 2. Последнее сердечко: таймер до конца шанса.
        if let a = i.outlook.lastChanceAt {
            let d = i.outlook.deathAt
            out.append(IslandEvent(kind: .lastChance, from: a, until: d, title: "Последнее сердечко",
                                   detail: d.map { "Помоги до \(hm($0))" } ?? "Помоги \(i.name)",
                                   soon: "Последнее сердечко к \(hm(a))", compact: "♥", pose: .lie,
                                   timerEnd: d, progressFrom: nil, ring: nil))
        }

        // 3. Голоден.
        for h in i.outlook.hunger {
            out.append(IslandEvent(kind: .hungry, from: h.from, until: h.until, title: "Голоден!", detail: "Миска пустая",
                                   soon: "Проголодается к \(hm(h.from))", compact: "🥣", pose: .bowl,
                                   timerEnd: nil, progressFrom: nil, ring: nil))
        }

        // 4. Поход: полоска и таймер до возвращения, потом «Я дома!».
        if let tr = i.trip {
            if tr.backAt > now {
                out.append(IslandEvent(kind: .trip, from: tr.from ?? now, until: tr.backAt, title: tr.place,
                                       detail: "Вернётся в \(hm(tr.backAt))", soon: tr.place, compact: "🐾",
                                       pose: .away, timerEnd: tr.backAt, progressFrom: tr.from, ring: nil))
            }
            let end = tr.backAt + cfg.homeHoldS
            if end > now {
                out.append(IslandEvent(kind: .home, from: tr.backAt, until: end, title: "Я дома!", detail: tr.place,
                                       soon: "Вернётся в \(hm(tr.backAt))", compact: "🏠", pose: .sit,
                                       timerEnd: nil, progressFrom: nil, ring: nil))
            }
        }

        // 4½. Просьба пса (волна 45 O): только уже открытая. Будущую заранее не показываем — «Попросит в 15:10»
        // обещал бы то, что решится по стейту на старт, и запускал бы активность ради пустяка.
        if let a = i.ask, a.start <= now, now < a.end {
            let line = DogAskText.line(a.kind)
            out.append(IslandEvent(kind: .ask, from: a.start, until: a.end, title: line,
                                   detail: DogAskText.hint(a.ask), soon: line, compact: DogAskText.emoji(a.kind),
                                   pose: .sit, timerEnd: a.end, progressFrom: nil, ring: nil, ask: a.kind))
        }

        // 5. Копилка двора полна.
        if let b = i.bank {
            out.append(IslandEvent(kind: .bank, from: b.fullAt, until: nil,
                                   title: b.coins.map { "+\($0) 🪙 ждут" } ?? "Копилка полна", detail: "Собери во дворе",
                                   soon: "Копилка полна к \(hm(b.fullAt))", compact: b.coins.map { "+\($0)" } ?? "🪙",
                                   pose: .sit, timerEnd: nil, progressFrom: nil, ring: 1))
        }

        // 6. Новый уровень: короткая активность.
        if let l = i.levelUp, l.at + cfg.levelHoldS > now {
            out.append(IslandEvent(kind: .levelUp, from: l.at, until: l.at + cfg.levelHoldS, title: "★\(l.level)",
                                   detail: "Новый уровень", soon: "★\(l.level)", compact: "★\(l.level)", pose: .sit,
                                   timerEnd: nil, progressFrom: nil, ring: nil))
        }
        return out
    }

    /// Главное событие в момент t: самое приоритетное из идущих; ночью хозяина — никакого.
    static func top(_ c: [IslandEvent], at t: Double, quiet: IslandQuiet?) -> IslandEvent? {
        if let q = quiet, q.asleep(t) { return nil }
        var best: IslandEvent?
        for e in c where e.on(t) {
            if let b = best, b.kind.rank <= e.kind.rank { continue }
            best = e
        }
        return best
    }

    /// Текущее событие, staleDate и вид после stale.
    static func choose(_ c: [IslandEvent], now: Double, quiet: IslandQuiet?,
                       _ cfg: IslandEventsConfig = .shared) -> IslandShow {
        let cur = top(c, at: now, quiet: quiet)
        // Волна 45 O: просьба — только текущий вид. Вид после stale ею не бывает: второго переключения у активности
        // нет, и таймер «ещё 0:00» висел бы до захода в приложение. Чужая просьба для расчёта stale — как не было;
        // своя (cur) остаётся, её конец — край, на котором вид меняется.
        let pool = c.filter { $0.kind != .ask || $0 == cur }
        let horizon = now + cfg.forecastH * 3600
        var edges: Set<Double> = []
        for e in pool {
            edges.insert(e.from)
            if let u = e.until { edges.insert(u) }
        }
        if let q = quiet {
            var t = now
            while let n = q.nextEdge(after: t), n <= horizon { edges.insert(n); t = n }
        }
        var show = IslandShow(current: cur)
        for b in edges.filter({ $0 > now && $0 <= horizon }).sorted() {
            let x = top(pool, at: b, quiet: quiet)
            if x != cur { show.staleDate = b; show.after = x; break }
        }
        // Активность живёт до 8 ч: если до тех пор ничего не меняется — stale на 8 ч, вид тот же.
        if cur != nil {
            let cap = now + cfg.maxStaleH * 3600
            if (show.staleDate ?? .infinity) > cap {
                show.staleDate = cap
                show.after = top(pool, at: cap, quiet: quiet)
            }
        }
        // Ранний старт (выключен решением 7а): заранее «Проголодается к 18:40», после stale — «Голоден!».
        if cur == nil, cfg.startEarly, !(quiet?.asleep(now) ?? false), let a = show.after, let s = show.staleDate,
           s - now <= cfg.maxStaleH * 3600 {
            show.current = a
            show.pending = true
        }
        return show
    }

    static func show(_ i: IslandInput, _ cfg: IslandEventsConfig = .shared) -> IslandShow {
        choose(candidates(i, cfg), now: i.now, quiet: i.quiet, cfg)
    }

    // MARK: прогноз

    /// Последнее сердечко, побег и отрезки голода по ядру без действий. s — стейт на момент s.t (= now).
    /// Прогноз ядра не взводит «low» повторно, поэтому после кормушки, поднявшей еду, считаем заново от того стейта.
    static func outlook(_ s0: PetState, _ r: Rules, _ o: Owner, horizonH: Double) -> IslandOutlook {
        let end = s0.t + horizonH * 3600
        let ev0 = PetEngine.forecast(s0, r, o, horizonH: horizonH)
        var out = IslandOutlook()
        guard s0.alive else { return out }
        out.deathAt = ev0.first { $0.kind == .death }?.t
        out.lastChanceAt = s0.lastChanceH != nil ? s0.t : ev0.first { $0.kind == .last_chance }?.t

        var s = s0
        var ev = ev0
        for _ in 0..<8 {
            let low = (s.needs[.food] ?? 100) < r.warnLow
            let start: Double? = low ? s.t : ev.first(where: { $0.kind == .low && $0.key == Need.food.rawValue })?.t
            guard let a = start else { break }
            var stop: Double?
            for e in ev where e.kind == .autofeed && e.t >= a {
                let x = PetEngine.advance(s, r, o, e.t + coreStepS)
                if x.alive, (x.needs[.food] ?? 0) >= r.warnLow { stop = e.t; s = x; break }
            }
            out.hunger.append(IslandSpan(from: a, until: stop ?? out.deathAt))
            guard stop != nil, s.t < end else { break }
            ev = PetEngine.forecast(s, r, o, horizonH: (end - s.t) / 3600)
        }
        return out
    }

    // MARK: из сейва

    /// Вход для выбора из сейва. trip/bank/levelUp — от Places, Yard и DogLevel (их файлы здесь не читаем).
    /// Без trip: прогулка ядра (outing) или свежее возвращение с неё из журнала.
    static func input(_ f: SaveFile, at now: Double, trip: IslandTrip? = nil, bank: IslandBank? = nil,
                      levelUp: IslandLevelUp? = nil, tzOffsetMin: Int? = nil,
                      _ cfg: IslandEventsConfig = .shared) -> IslandInput {
        let r = ItemPerks.rules(f)
        // Ядро крутится с поясом из файла (как PetRunner.peek), часы и сон хозяина — с поясом устройства.
        var eo = f.owner
        if let tzOffsetMin { eo.tzOffsetMin = tzOffsetMin }
        var o = f.owner
        o.tzOffsetMin = tzOffsetMin ?? Clock.tzOffsetMin(at: now)
        let s = now > f.pet.t ? PetEngine.advance(f.pet, r, eo, now) : f.pet
        let look = outlook(s, r, eo, horizonH: cfg.forecastH)
        let q = NotificationPlanner.quietHours(f, now: now, owner: o)
        let rc = RunawayConfig.shared
        let deathT = look.deathAt ?? now
        let recent = f.runaway.comebacks.filter { deathT - $0 < rc.windowDays * 86400 && deathT >= $0 }

        var walk = trip
        if walk == nil, let w = s.outing { walk = IslandTrip(from: w.from, backAt: w.until, place: "Прогулка") }
        if walk == nil, let e = f.journal.last(where: { $0.kind.hasPrefix("ev.back_home") }),
           e.t <= now, now - e.t < cfg.homeHoldS {
            walk = IslandTrip(from: nil, backAt: e.t, place: "Прогулка")
        }

        return IslandInput(now: now, name: f.petName, alive: s.alive, outlook: look, trip: walk, bank: bank,
                           levelUp: levelUp, runaway: Runaway.status(f, at: now),
                           runawayClosed: !rc.enabled || recent.count >= rc.maxInWindow,
                           searchH: rc.searchH, trailsNeed: rc.trails,
                           quiet: IslandQuiet(from: q.from, to: q.to, tzOffsetMin: o.tzOffsetMin),
                           tzOffsetMin: o.tzOffsetMin)
    }

    /// Что делать с островком при уходе в фон.
    static func show(_ f: SaveFile, at now: Double, trip: IslandTrip? = nil, bank: IslandBank? = nil,
                     levelUp: IslandLevelUp? = nil, tzOffsetMin: Int? = nil,
                     _ cfg: IslandEventsConfig = .shared) -> IslandShow {
        show(input(f, at: now, trip: trip, bank: bank, levelUp: levelUp, tzOffsetMin: tzOffsetMin, cfg), cfg)
    }

    // MARK: виджет

    /// Моменты кадров: сейчас и дальше по сетке стенных часов (:00 и :30), строго по возрастанию.
    static func frameTimes(now: Double, _ cfg: IslandEventsConfig = .shared) -> [Double] {
        let step = max(60, cfg.widgetStepS)
        var ts = [now]
        var g = ((now / step).rounded(.down) + 1) * step
        while ts.count < max(1, cfg.widgetEntries) { ts.append(g); g += step }
        return ts
    }

    /// Поза в момент кадра. ate — ел за последний шаг кадра (кормушка или хозяин).
    static func pose(_ s: PetState, _ r: Rules, _ o: Owner, trip: IslandTrip?, ate: Bool,
                     _ cfg: IslandEventsConfig = .shared) -> DogPose {
        let t = s.t
        if !s.alive || s.outing != nil { return .away }
        if let tr = trip, t >= (tr.from ?? -.infinity), t < tr.backAt { return .away }
        if PetEngine.petNight(t, r, o) || s.napUntil != nil { return .sleep }
        if ate { return .eat }
        let v = s.needs
        if (v[.food] ?? 100) < r.warnLow { return .bowl }
        if (v[.energy] ?? 100) < cfg.lieEnergy || PetEngine.level(s, r) >= 2
            || (v[.fun] ?? 100) < r.warnLow || (v[.love] ?? 100) < r.warnLow { return .lie }
        return .sit
    }

    /// Волна 45 O: моменты кадров с просьбами — сетка плюс старт, каждые widgetAskStepS в окне и конец окна.
    /// Не дальше последнего кадра сетки, строго по возрастанию.
    static func frameTimes(now: Double, asks: [DogAsk], window: Double, _ cfg: IslandEventsConfig = .shared) -> [Double] {
        var ts = frameTimes(now: now, cfg)
        guard !asks.isEmpty, let last = ts.last else { return ts }
        let step = max(60, cfg.widgetAskStepS)
        var extra: [Double] = []
        for a in asks {
            let end = a.start + window
            var t = a.start
            while t < end { extra.append(t); t += step }
            extra.append(end)
        }
        ts += extra.filter { $0 > now && $0 <= last }
        return Array(Set(ts)).sorted()
    }

    /// 24 кадра виджета. s0 — стейт на now; eo — хозяин ядра (пояс файла), o — пояс устройства для ночи и подписей.
    /// ateAt — когда хозяин кормил последний раз (тогда первый кадр «ест»).
    /// asks — просьбы пса на этом отрезке (DogAsks.upcoming): в их окнах кадры чаще, и на кадре — просьба,
    /// если пёс дома, не спит и не моется (как DogAsks.choose: спящего не будим).
    static func frames(_ s0: PetState, _ r: Rules, engine eo: Owner, local o: Owner, now: Double,
                       trip: IslandTrip? = nil, bank: IslandBank? = nil, ateAt: Double? = nil,
                       asks: [DogAsk] = [], askWindow: Double = DogAskConfig.shared.window,
                       _ cfg: IslandEventsConfig = .shared) -> [PoseFrame] {
        let ts = frameTimes(now: now, asks: asks, window: askWindow, cfg)
        let step = max(60, cfg.widgetStepS)
        let span = ((ts.last ?? now) - now) / 3600
        let feeds = PetEngine.forecast(s0, r, eo, horizonH: span + step / 3600).filter { $0.kind == .autofeed }.map(\.t)
        var s = s0
        var out: [PoseFrame] = []
        for t in ts {
            if t > s.t { s = PetEngine.advance(s, r, eo, t) }
            var cur = s
            cur.t = t
            let ate = (feeds + (ateAt.map { [$0] } ?? [])).contains { $0 > t - step && $0 <= t }
            let p = pose(cur, r, o, trip: trip, ate: ate, cfg)
            var note: String?
            var until: Double?
            if !s.alive {
                note = "Убежал… ищи следы"
            } else if let tr = trip, t >= (tr.from ?? -.infinity), t < tr.backAt {
                note = "\(tr.place) · вернётся в \(hm(tr.backAt, tz: o.tzOffsetMin))"
                until = tr.backAt
            } else if let w = s.outing {
                note = "Гуляет · вернётся в \(hm(w.until, tz: o.tzOffsetMin))"
                until = w.until
            }
            var bars: [Need: Int] = [:]
            for (n, v) in s.needs { bars[n] = Int(v.rounded()) }
            var ask: DogAsk?
            if s.alive, p != .sleep, p != .away, s.bathUntil == nil {
                ask = asks.first { $0.open(at: t, window: askWindow) }
            }
            out.append(PoseFrame(t: t, pose: p, note: note, bars: bars, ring: bank?.ring(at: t), tripUntil: until,
                                 alive: s.alive, ask: ask))
        }
        return out
    }

    /// Кадры виджета из сейва. trip/bank — параметры (Places, Yard); asks — просьбы пса (волна 45 O).
    static func widget(_ f: SaveFile, now: Double, trip: IslandTrip? = nil, bank: IslandBank? = nil,
                       tzOffsetMin: Int? = nil, asks: [DogAsk] = [],
                       _ cfg: IslandEventsConfig = .shared) -> [PoseFrame] {
        let r = ItemPerks.rules(f)
        var eo = f.owner
        if let tzOffsetMin { eo.tzOffsetMin = tzOffsetMin }
        var o = f.owner
        o.tzOffsetMin = tzOffsetMin ?? Clock.tzOffsetMin(at: now)
        let s = now > f.pet.t ? PetEngine.advance(f.pet, r, eo, now) : f.pet
        let fed = f.lastAction.flatMap { la in la.ok && (la.kind == "feed" || la.kind == "cook") ? la.t : nil }
        return frames(s, r, engine: eo, local: o, now: now, trip: trip, bank: bank, ateAt: fed, asks: asks, cfg)
    }
}
