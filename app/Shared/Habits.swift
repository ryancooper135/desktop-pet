// Привычки хозяина (волна 11): готовые действия для «Команд» → «Автоматизация».
// «Я дома», «Я проснулся», «Ложусь спать», «Выпил воды», «Сделал зарядку» — хозяин отмечает свой день,
// пёс отвечает фразой (Siri говорит её вслух) и радуется в приложении, в кошелёк капают монеты.
//
// Здесь только логика без экрана (HabitsScreen.swift рисует, Intents.swift — интенты «Команд»):
// • монеты и сколько раз за сутки — из config/economy.json, income.habits.<id> {coins, per_day};
//   нет ключа — дефолт из Habit.defaults;
// • сверх per_day отметка не в счёт: пёс отвечает, монет нет, счётчики не растут;
// • все привычки вместе с шагами упираются в общий дневной потолок income.habits.daily_cap
//   (Econ.Daily.habits, тот же приём «min(хочу, потолок − уже)», что у Economy для шагов);
// • ядро не трогаем: привычки — не уход за псом, ни шкал, ни журнала act.* (журнал из 200 записей
//   нужен шерсти и открыткам, восемь стаканов воды в день его бы вытеснили);
// • отметки — верхним уровнем SaveFile (habits): сегодня по каждой, последний раз и всего.
//   Пустое в файл не пишется, старый сейв без поля — пусто. Новому щенку переходят: привычки — хозяина.
// Только Foundation и PetCore: гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

// MARK: - Привычки

enum Habit: String, CaseIterable, Codable, Hashable, Sendable {
    case home, wake, sleep, water, workout

    /// Кнопка и строка списка.
    var title: String {
        switch self {
        case .home: "Я дома"
        case .wake: "Я проснулся"
        case .sleep: "Ложусь спать"
        case .water: "Выпил воды"
        case .workout: "Сделал зарядку"
        }
    }

    /// SF Symbol для экрана и «Команд».
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .wake: "sun.horizon.fill"
        case .sleep: "moon.zzz.fill"
        case .water: "drop.fill"
        case .workout: "figure.strengthtraining.functional"
        }
    }

    /// Фраза Siri после имени приложения: «Питомец, я дома». Те же слова — в ShortcutsProvider
    /// (там литералы: их читает сборщик метаданных, отсюда подставить нельзя).
    var siri: String {
        switch self {
        case .home: "я дома"
        case .wake: "я проснулся"
        case .sleep: "я ложусь спать"
        case .water: "я выпил воды"
        case .workout: "я сделал зарядку"
        }
    }

    /// Чем запустить в «Командах» → «Автоматизация»: короткая подсказка под строкой.
    var trigger: String {
        switch self {
        case .home: "«Прибытие» — дом, или NFC-метка у двери"
        case .wake: "«Будильник» — когда будильник выключен"
        case .sleep: "«Режим сна» включается или «Время суток»"
        case .water: "NFC-метка на бутылке или «Время суток» раз в пару часов"
        case .workout: "«Тренировка» на часах окончена или NFC-метка на коврике"
        }
    }

    /// Дефолты, если в economy.json нет ключа: (монет за раз, раз в сутки).
    var defaults: (coins: Int, perDay: Int) {
        switch self {
        case .home: (8, 1)
        case .wake: (8, 1)
        case .sleep: (8, 1)
        case .water: (2, 8)
        case .workout: (10, 1)
        }
    }
}

// MARK: - Настройки

struct HabitConfig: Hashable, Sendable {
    struct Rule: Hashable, Sendable {
        var coins: Int
        var perDay: Int
    }

    var rules: [Habit: Rule] = Dictionary(uniqueKeysWithValues: Habit.allCases.map {
        ($0, Rule(coins: $0.defaults.coins, perDay: $0.defaults.perDay))
    })
    /// Общий потолок привычек (и шагов) в сутки — тот же, что у EconomyConfig.habitsCap.
    var dailyCap = 70

    static let shared = HabitConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let h = e["income"]["habits"]
        dailyCap = max(0, int(h["daily_cap"], dailyCap))
        for habit in Habit.allCases {
            let r = h[habit.rawValue]
            let d = habit.defaults
            rules[habit] = Rule(coins: max(0, int(r["coins"], d.coins)), perDay: max(1, int(r["per_day"], d.perDay)))
        }
    }

    func rule(_ h: Habit) -> Rule { rules[h] ?? Rule(coins: h.defaults.coins, perDay: h.defaults.perDay) }
}

// MARK: - Отметки в сейве

/// Что хозяин отмечал. day — номер местных суток (Economy.day), today — сколько раз сегодня по каждой,
/// last — когда последний раз, total — сколько раз всего. Ключи — Habit.rawValue: незнакомые не ломают чтение.
struct HabitLog: Codable, Hashable, Sendable {
    var day = 0
    var today: [String: Int] = [:]
    var last: [String: Double] = [:]
    var total: [String: Int] = [:]

    init() {}

    var isEmpty: Bool { day == 0 && today.isEmpty && last.isEmpty && total.isEmpty }

    enum CodingKeys: String, CodingKey { case day, today, last, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        today = (try? c.decodeIfPresent([String: Int].self, forKey: .today)) ?? [:]
        last = (try? c.decodeIfPresent([String: Double].self, forKey: .last)) ?? [:]
        total = (try? c.decodeIfPresent([String: Int].self, forKey: .total)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if day != 0 { try c.encode(day, forKey: .day) }
        if !today.isEmpty { try c.encode(today, forKey: .today) }
        if !last.isEmpty { try c.encode(last, forKey: .last) }
        if !total.isEmpty { try c.encode(total, forKey: .total) }
    }
}

// MARK: - Итог отметки

struct HabitOutcome: Hashable, Sendable {
    let habit: Habit
    /// Засчитано (в пределах per_day). false — сегодня уже хватит или пса нет (reason).
    let ok: Bool
    let reason: String?
    let coins: Int
    /// Хотели монет, но упёрлись в общий потолок привычек.
    let capped: Bool
    /// Который раз сегодня (после отметки).
    let count: Int
    /// Что отвечает пёс: тост в приложении и ответ Siri.
    let text: String
}

enum Habits {
    /// Вид реакции пса в приложении (AppModel.react): радостная, как после расчёсывания.
    static let reactKind = "habit"
    /// Отказ: эта привычка сегодня уже отмечена per_day раз.
    static let enoughReason = "enough"

    /// Сменились местные сутки — «сегодня» с нуля. Назад не откатываемся, как Economy.rollDay.
    static func rollDay(_ log: inout HabitLog, now: Double) {
        let d = Economy.day(now)
        guard d > log.day else { return }
        log.day = d
        log.today = [:]
    }

    /// Сколько раз отмечено сегодня (с учётом смены суток — без записи).
    static func countToday(_ f: SaveFile, _ h: Habit, now: Double) -> Int {
        Economy.day(now) > f.habits.day ? 0 : (f.habits.today[h.rawValue] ?? 0)
    }

    /// Хоть раз было когда-нибудь.
    static func everDone(_ f: SaveFile, _ h: Habit) -> Bool { (f.habits.total[h.rawValue] ?? 0) > 0 }

    /// Монет за привычки ещё можно получить сегодня (общий потолок с шагами).
    static func coinsLeft(_ f: SaveFile, now: Double, _ cfg: HabitConfig = .shared) -> Int {
        let used = Economy.day(now) > f.econ.daily.day ? 0 : f.econ.daily.habits
        return max(0, cfg.dailyCap - used)
    }

    /// Отметить привычку. times — сколько раз сразу («Выпил воды», 2 стакана), не больше остатка per_day.
    /// Пишет только в f: счётчики, кошелёк, общий потолок econ.daily.habits.
    @discardableResult
    static func checkIn(_ h: Habit, times: Int = 1, in f: inout SaveFile, now: Double,
                        _ cfg: HabitConfig = .shared) -> HabitOutcome {
        PetRunner.catchUp(&f, now: now)
        guard f.pet.alive else {
            return HabitOutcome(habit: h, ok: false, reason: "dead", coins: 0, capped: false, count: 0,
                                text: "Шибы пока нет — загляни в приложение")
        }
        rollDay(&f.habits, now: now)
        Economy.rollDay(&f.econ, day: Economy.day(now))
        let rule = cfg.rule(h)
        let done = f.habits.today[h.rawValue] ?? 0
        let n = min(max(1, times), max(0, rule.perDay - done))
        guard n > 0 else {
            return HabitOutcome(habit: h, ok: false, reason: enoughReason, coins: 0, capped: false, count: done,
                                text: enoughText(h))
        }
        let want = rule.coins * n
        let got = min(want, max(0, cfg.dailyCap - f.econ.daily.habits))
        f.econ.daily.habits += got
        f.econ.wallet.coins += got
        if got > 0 {
            f.econ.lastEarn = Earning(id: "habit:\(h.rawValue):\(Int(now))", kind: reactKind, coins: got, capped: got < want, t: now)
        }
        f.habits.today[h.rawValue] = done + n
        f.habits.last[h.rawValue] = now
        let total = (f.habits.total[h.rawValue] ?? 0) + n
        f.habits.total[h.rawValue] = total
        return HabitOutcome(habit: h, ok: true, reason: nil, coins: got, capped: got < want, count: done + n,
                            text: greeting(h, n: total))
    }

    /// Стор не записался.
    static func failed(_ h: Habit) -> HabitOutcome {
        HabitOutcome(habit: h, ok: false, reason: "store", coins: 0, capped: false, count: 0, text: RefuseText.text("store"))
    }

    // MARK: тексты

    /// Ответ пса. n — который раз всего: фразы по кругу, детерминированно (тесты, снимки).
    static func greeting(_ h: Habit, n: Int) -> String {
        let list = lines[h] ?? [h.title]
        return list[(max(1, n) - 1) % list.count]
    }

    static let lines: [Habit: [String]] = [
        .home: ["Ты дома! Шиба несётся встречать и виляет всем собой",
                "Ура, ты пришёл! Шиба кружится у двери",
                "Наконец-то! Шиба принёс тебе тапок… почти"],
        .wake: ["Доброе утро! Шиба потягивается и виляет хвостом",
                "Проснулся? Шиба давно ждал — гав!",
                "С добрым утром! Шиба зевает вместе с тобой"],
        .sleep: ["Спокойной ночи! Шиба сворачивается клубком рядом",
                 "Сладких снов. Шиба тоже уже зевает",
                 "Ложимся? Шиба выключает хвост до утра"],
        .water: ["Буль-буль! Шиба тоже попил из миски",
                 "Молодец! Шиба одобрительно лизнул стакан",
                 "Вода — это хорошо. Шиба согласен"],
        .workout: ["Зарядка засчитана! Шиба тянется лапами вперёд",
                   "Сильный хозяин — довольный Шиба",
                   "Раз-два! Шиба прыгает рядом за компанию"],
    ]

    static func enoughText(_ h: Habit) -> String {
        switch h {
        case .water: "Воды на сегодня засчитано вдоволь — Шиба гордится"
        case .home: "Шиба снова рад тебя видеть"
        case .wake: "Утро уже отмечено — Шиба помнит"
        case .sleep: "Шиба уже пожелал спокойной ночи"
        case .workout: "Зарядка на сегодня уже есть — отдыхай"
        }
    }

    /// Подпись награды на экране «Привычки»: «+8 монет · раз в день», «+2 монеты · до 8 раз в день».
    static func rewardText(_ h: Habit, _ cfg: HabitConfig = .shared) -> String {
        let r = cfg.rule(h)
        let often = r.perDay == 1 ? "раз в день" : "до \(r.perDay) раз в день"
        return "+\(EconText.coins(r.coins)) · \(often)"
    }

    /// Отметка на экране: «Сегодня ✓», «Сегодня 3 из 8», «Было 5 раз», «Ещё не было».
    static func statusText(_ f: SaveFile, _ h: Habit, now: Double, _ cfg: HabitConfig = .shared) -> String {
        let today = countToday(f, h, now: now)
        let per = cfg.rule(h).perDay
        if today > 0 { return per == 1 ? "Сегодня ✓" : "Сегодня \(today) из \(per)" }
        let total = f.habits.total[h.rawValue] ?? 0
        return total > 0 ? "Было \(total) \(times(total))" : "Ещё не было"
    }

    /// «раз» не склоняется, но «2 раза».
    static func times(_ n: Int) -> String { EconText.plural(n, "раз", "раза", "раз") }

    /// Ответ целиком: фраза пса и монеты («+8 монет») или потолок.
    static func reply(_ o: HabitOutcome) -> String {
        if o.coins > 0 { return "\(o.text) · +\(EconText.coins(o.coins))" }
        if o.ok && o.capped { return "\(o.text) · монет за привычки на сегодня хватит" }
        return o.text
    }
}
