// «Открытка дня» (RESEARCH/06 #8). Ничего не снимаем в момент события: после местной полуночи
// задним числом разбираем журнал за прошедший день, находим «моменты» (кормёжка, игра, находка,
// спасение, день дружбы…), выбираем один стабильно от petId и номера дня и собираем открытку:
// поза/клип/проп для заглушки, находка, подпись из lines.json (away.card_*), время.
// Открытка живёт 7 суток с местной полуночи, когда появилась; не сохранили — пропадает.
// Сохранённые лежат в альбоме (SaveFile.cards) без срока. Пустой день — открытки нет, ничего не выдумываем.
//
// Кадр 3D для открытки снимает приложение в удачный момент дня (PostcardPhotos, PostcardCamera); при сборке
// открытки ей достаётся кадр того же момента. Нет кадра — экран рисует заглушку по Postcard.frame.
// Срок и мягкое «последний день» — Postcards.expiryNote (PostcardPhotos.swift).
//
// Только Foundation и PetCore: гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

/// Тип момента. Порядок case — порядок пула при выборе: не переставлять, иначе у всех сменятся открытки.
/// rawValue пишется в сейв и в ключ строк (away.card_<rawValue>).
enum MomentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case feed                       // покормил хрустиками
    case treat                      // покормил чем-то кроме хрустиков
    case play                       // поиграл с мячом
    case pets                       // гладил (серия — дороже)
    case bath                       // помыл
    case find                       // вернулся с прогулки с находкой
    case findFirst = "find_first"   // такую находку принёс впервые
    case wake                       // разбудили посреди дрёмы
    case morning                    // первое дело хозяина после утреннего подъёма
    case steps                      // много шагов за день
    case rescue                     // вытащили из «Плохо»
    case firstDay = "first_day"     // день знакомства
    case days                       // дни дружбы: 7, 30, 50, 100…
    case birthday                   // кратно 365 дням

    /// Вехи всегда важнее обычных моментов дня.
    var isMilestone: Bool { self == .firstDay || self == .days || self == .birthday }
    /// Ключ строк в разделе away.
    var lineKey: String { "card_\(rawValue)" }
}

/// Кандидат в открытку дня.
struct Moment: Hashable, Sendable {
    let kind: MomentKind
    let t: Double
    var score: Int
    /// id находки (find, find_first).
    var find: String? = nil
    /// id еды (treat).
    var item: String? = nil
    /// Поглаживаний в серии, дней дружбы, лет, шагов.
    var count: Int? = nil
}

/// Открытка. kind строкой: открытка типа из будущей версии не теряется в старом приложении.
struct Postcard: Codable, Hashable, Sendable, Identifiable {
    /// "c<день>": на день одна открытка.
    let id: String
    /// Местный день (дни от 1970-01-01 по поясу tz).
    let day: Int
    let kind: String
    /// Момент, который на открытке.
    let t: Double
    /// Пояс хозяина, по которому собрана: время и дата на открытке от него.
    let tz: Int
    let score: Int
    let caption: String
    var lineId: String?
    var find: String?
    var item: String?
    var count: Int?
    /// Pose.rawValue и клип из PetClips для снимка; prop — что поставить в кадр (bowl, ball, tub, cake, id находки).
    let pose: String
    var clip: String?
    var prop: String?
    /// После этого момента несохранённая открытка пропадает.
    let expiresT: Double
    /// Когда сохранили в альбом; nil — не сохранена.
    var savedT: Double?
    /// Имя файла кадра в Paths.dir/photos (PostcardPhotos); nil — кадра нет, на открытке заглушка.
    var image: String?

    var momentKind: MomentKind? { MomentKind(rawValue: kind) }
    var isSaved: Bool { savedT != nil }
}

/// Всё, что нужно экрану и снимку, уже в готовых типах.
struct PostcardFrame: Hashable, Sendable {
    let pose: Pose
    let clip: String?
    let prop: String?
    let find: Find?
    let caption: String
    /// «14:20» по поясу открытки.
    let time: String
    /// «17 октября».
    let date: String
}

extension Postcard {
    var frame: PostcardFrame {
        PostcardFrame(pose: Pose(rawValue: pose) ?? .happy, clip: clip, prop: prop, find: find.flatMap { Finds.find($0) },
                      caption: caption, time: Finds.clock(t, tzOffsetMin: tz), date: Postcards.dateLabel(day))
    }
}

/// Открытки в сейве: ждущие решения (7 суток) и альбом. Компактно: пустой альбом — пара байт.
struct PostcardBook: Codable, Hashable, Sendable {
    /// Лимит альбома: сейв пишут виджеты, раздувать его нельзя (~400 байт на открытку → ~80 КБ).
    static let albumMax = 200

    /// Не сохранённые, ещё живые. Старые сначала.
    var pending: [Postcard] = []
    /// Сохранённые, в порядке сохранения.
    var album: [Postcard] = []
    /// Последний местный день, который уже разобран (за него открытка выдана или её не было).
    var doneDay: Int?

    init() {}

    enum CodingKeys: String, CodingKey { case pending, album, doneDay }

    /// Одна битая открытка не должна стирать весь альбом.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pending = ((try? c.decodeIfPresent([Lossy<Postcard>].self, forKey: .pending)) ?? []).compactMap(\.value)
        album = ((try? c.decodeIfPresent([Lossy<Postcard>].self, forKey: .album)) ?? []).compactMap(\.value)
        doneDay = try? c.decodeIfPresent(Int.self, forKey: .doneDay)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pending, forKey: .pending)
        try c.encode(album, forKey: .album)
        try c.encodeIfPresent(doneDay, forKey: .doneDay)
    }

    func card(_ id: String) -> Postcard? {
        album.first { $0.id == id } ?? pending.first { $0.id == id }
    }

    /// Что переходит к новому питомцу (PetStore.startOver, economy.json death.keep: "album"): сохранённые
    /// открытки остаются, несохранённые и отметка разобранного дня — нет (новый питомец начинает свои дни).
    func carriedOver() -> PostcardBook {
        var b = PostcardBook()
        b.album = album
        return b
    }
}

/// Элемент массива, который не валит весь массив, если сам не разобрался.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

enum Postcards {
    // MARK: настройки

    /// Сколько живёт несохранённая открытка.
    static let lifeDays = 7
    static let life: Double = Double(lifeDays) * 86400
    /// Подпись короче строк ленты: на открытке под кадром.
    static let captionMax = 50

    /// Серия поглаживаний: тапы не дальше 5 минут друг от друга, от 3 штук.
    static let petsGap: Double = 5 * 60
    static let petsSeries = 3
    /// Спасение: забота после беды не позже 48 ч; серия дел — с перерывами до 30 минут.
    static let rescueWindow: Double = 48 * 3600
    static let careGap: Double = 30 * 60
    /// «Доброе утро»: первое дело хозяина в течение 2 часов после подъёма Шибы.
    static let morningWindow: Double = 2 * 3600
    /// Шаги за день.
    static let stepsMin = 3000
    static let stepsBig = 8000
    /// Дни дружбы (кроме кратных 365 — это день рождения).
    static let friendDays = [7, 30, 50, 100, 200, 300, 500, 1000]
    /// В пул выбора идут моменты не слабее 60 % лучшего.
    static let poolShare = 0.6

    /// Очки интересности. Повтор вчерашнего типа (кроме вех и спасения) — вдвое меньше.
    static let scores: [MomentKind: Int] = [
        .feed: 20, .treat: 30, .play: 35, .pets: 10, .bath: 30, .find: 50, .findFirst: 70,
        .wake: 25, .morning: 15, .steps: 25, .rescue: 70, .firstDay: 100, .days: 100, .birthday: 100,
    ]
    /// Серия поглаживаний: 25 за 3, +5 за каждое следующее, до 45. Спасение с последнего сердечка — 90.
    static let petsSeriesScore = 25, petsSeriesMax = 45
    static let rescueLastChanceScore = 90
    static let stepsBigScore = 35

    // MARK: местные дни (DayKey)

    /// «17 октября» без DateFormatter: одинаково на Linux и в тестах.
    static func dateLabel(_ day: Int) -> String {
        let months = ["января", "февраля", "марта", "апреля", "мая", "июня",
                      "июля", "августа", "сентября", "октября", "ноября", "декабря"]
        let (_, m, d) = civil(day)
        return "\(d) \(months[m - 1])"
    }

    /// Дни от 1970-01-01 → (год, месяц 1–12, число). Алгоритм Хиннанта.
    static func civil(_ day: Int) -> (year: Int, month: Int, day: Int) {
        let z = day + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    // MARK: моменты

    /// Журнал и outbox вместе (outbox длиннее: 500 против 200), без повторов, по времени.
    static func entries(_ f: SaveFile) -> [JournalEntry] {
        var seen = Set<String>()
        var out: [JournalEntry] = []
        for e in f.outbox + f.journal where seen.insert(e.id).inserted { out.append(e) }
        return out.sorted { $0.t != $1.t ? $0.t < $1.t : $0.id < $1.id }
    }

    private static let careActs: Set<String> = ["act.feed", "act.item", "act.bath", "act.play", "act.pet"]

    private static func isTrouble(_ kind: String) -> Bool {
        kind.hasPrefix("ev.heart") || kind.hasPrefix("ev.distress") || kind.hasPrefix("ev.last_chance")
    }

    /// Все моменты местного дня. Порядок: как в журнале.
    static func moments(_ f: SaveFile, day: Int, tzOffsetMin tz: Int) -> [Moment] {
        let start = DayKey.start(day, tzOffsetMin: tz), end = DayKey.start(day + 1, tzOffsetMin: tz)
        let all = entries(f)
        let inDay = all.filter { $0.t >= start && $0.t < end }
        // Дела хозяина: шаги считает телефон сам, это не забота.
        let owned = inDay.filter { $0.ok == true && $0.kind.hasPrefix("act.") && $0.kind != "act.steps" }
        var out: [Moment] = []
        func add(_ k: MomentKind, _ t: Double, score: Int? = nil, find: String? = nil, item: String? = nil, count: Int? = nil) {
            out.append(Moment(kind: k, t: t, score: score ?? scores[k] ?? 10, find: find, item: item, count: count))
        }

        // Еда, игра, мытьё, «разбудил».
        for e in owned {
            switch e.kind {
            case "act.feed":
                let food = e.key ?? Catalog.mainFood
                if food == Catalog.mainFood { add(.feed, e.t) } else { add(.treat, e.t, item: food) }
            case "act.play": add(.play, e.t)
            case "act.bath": add(.bath, e.t)
            case "act.wake": add(.wake, e.t)
            default: break
            }
        }

        // Находки. Первая такая — если все находки этого вида ещё в журнале и эта самая ранняя.
        let homes = all.filter { $0.kind.hasPrefix("ev.back_home") }
        for e in homes where e.t >= start && e.t < end {
            guard let id = e.key ?? e.kind.split(separator: ".").dropFirst(2).first.map(String.init) else { continue }
            let same = homes.filter { ($0.key ?? "") == id }
            let total = f.pet.finds[id] ?? 0
            if total > 0, same.count >= total, same.first?.id == e.id {
                add(.findFirst, e.t, find: id)
            } else {
                add(.find, e.t, find: id)
            }
        }

        // Поглаживания сериями: тапы (и удачные, и в кулдаун) с паузами до 5 минут.
        var series: [JournalEntry] = []
        func closeSeries() {
            defer { series = [] }
            guard let last = series.last, series.contains(where: { $0.ok == true }) else { return }
            let n = series.count
            if n >= petsSeries {
                add(.pets, last.t, score: min(petsSeriesMax, petsSeriesScore + 5 * (n - petsSeries)), count: n)
            } else {
                add(.pets, last.t)
            }
        }
        for e in inDay where e.kind == "act.pet" {
            if let prev = series.last, e.t - prev.t > petsGap { closeSeries() }
            series.append(e)
        }
        closeSeries()

        // Шаги за день.
        let stepEntries = inDay.filter { $0.kind == "act.steps" && $0.ok == true }
        let steps = stepEntries.reduce(0) { $0 + max(0, $1.value ?? 0) }
        if steps >= stepsMin, let last = stepEntries.last {
            add(.steps, last.t, score: steps >= stepsBig ? stepsBigScore : nil, count: steps)
        }

        // Доброе утро: Шиба встал (подъём хозяина + сдвиг сна питомца), и хозяин скоро что-то сделал.
        let wakeT = start + Double(f.owner.wakeMin + Catalog.rules.afterWakeMin) * 60
        if let first = owned.first(where: { $0.t >= wakeT && $0.t <= wakeT + morningWindow && $0.kind != "act.wake" }) {
            add(.morning, first.t)
        }

        // Спасение: после беды (сердечко, плохое состояние, последний шанс) — серия дел ухода,
        // момент на последнем деле серии. Смерть беду обнуляет.
        var troubleT: Double?
        var lastChance = false
        var i = 0
        while i < all.count {
            let e = all[i]
            if isTrouble(e.kind) {
                if troubleT == nil { troubleT = e.t }
                if e.kind.hasPrefix("ev.last_chance") { lastChance = true }
            } else if e.kind.hasPrefix("ev.death") {
                troubleT = nil; lastChance = false
            } else if let tt = troubleT, e.ok == true, careActs.contains(e.kind) {
                if e.t - tt > rescueWindow {
                    troubleT = nil; lastChance = false
                } else {
                    var last = e
                    var j = i + 1
                    while j < all.count {
                        let n = all[j]
                        if n.t - last.t > careGap || isTrouble(n.kind) || n.kind.hasPrefix("ev.death") { break }
                        if n.ok == true, careActs.contains(n.kind) { last = n }
                        j += 1
                    }
                    if last.t >= start && last.t < end {
                        add(.rescue, last.t, score: lastChance ? rescueLastChanceScore : nil)
                    }
                    troubleT = nil; lastChance = false
                    i = j
                    continue
                }
            }
            i += 1
        }

        // Вехи: день знакомства, дни дружбы, день рождения. Кроме первого дня — только если хозяин заходил.
        let index = day - f.bornDay   // номер дня жизни — от даты рождения в её поясе
        if index == 0, f.createdT >= start, f.createdT < end {
            add(.firstDay, f.createdT)
        } else if index > 0, let first = owned.first {
            if index % 365 == 0 {
                add(.birthday, first.t, count: index / 365)
            } else if friendDays.contains(index) {
                add(.days, first.t, count: index)
            }
        }
        return out.sorted { $0.t < $1.t }
    }

    // MARK: выбор

    /// Момент дня: лучший в каждом типе, повтор вчерашнего типа вдвое дешевле, в пул — не слабее 60 % лучшего,
    /// дальше взвешенно по очкам от StableHash(petId:card:day). Вехи, если есть, вытесняют остальное.
    static func choose(_ moments: [Moment], petId: String, day: Int, previous: MomentKind? = nil) -> Moment? {
        guard !moments.isEmpty else { return nil }
        var pool: [Moment] = []
        for k in MomentKind.allCases {
            let same = moments.filter { $0.kind == k }
            guard let top = same.map(\.score).max() else { continue }
            let ties = same.filter { $0.score == top }.sorted { $0.t < $1.t }
            var m = ties[pick("\(petId):card:\(day):\(k.rawValue)", ties.count)]
            if k == previous && !k.isMilestone && k != .rescue { m.score = max(1, m.score / 2) }
            m.score = max(1, m.score)
            pool.append(m)
        }
        if pool.contains(where: { $0.kind.isMilestone }) { pool = pool.filter { $0.kind.isMilestone } }
        let best = pool.map(\.score).max() ?? 1
        pool = pool.filter { Double($0.score) >= Double(best) * poolShare }
        var r = pick("\(petId):card:\(day)", pool.reduce(0) { $0 + $1.score })
        for m in pool {
            if r < m.score { return m }
            r -= m.score
        }
        return pool.last
    }

    private static func pick(_ seed: String, _ n: Int) -> Int {
        guard n > 1 else { return 0 }
        return Int(StableRandom.mix(StableHash.fnv1a(seed)) % UInt64(n))
    }

    // MARK: сборка

    /// Поза, клип (PetClips) и проп для снимка.
    static func look(_ m: Moment) -> (pose: Pose, clip: String?, prop: String?) {
        switch m.kind {
        case .feed, .treat: return (.eating, "eat_chew", "bowl")
        case .play: return (.happy, "gallop_jump", "ball")
        case .pets, .rescue: return (.loved, "happy_wag", nil)
        case .bath: return (.bath, "shake", "tub")
        case .find, .findFirst: return (.happy, "idle_wag", m.find)
        case .wake: return (.happy, "yawn", nil)
        case .morning: return (.idle, "play_bow", nil)
        case .steps: return (.happy, "walk", nil)
        case .firstDay: return (.happy, "head_tilt", nil)
        case .days: return (.happy, "hop", nil)
        case .birthday: return (.happy, "hop", "cake")
        }
    }

    /// Подстановки подписи. Нет значения — Lines возьмёт строку без этой подстановки.
    static func vars(_ m: Moment) -> [String: String] {
        var v: [String: String] = [:]
        if let id = m.find { v["item"] = Finds.name(id) }
        if let id = m.item { v["item"] = lowerFirst(Catalog.name(id)) }
        if let n = m.count {
            switch m.kind {
            case .steps: v["steps"] = grouped(n)
            case .pets, .days, .birthday: v["count"] = "\(n)"
            default: break
            }
        }
        return v
    }

    /// Запасная подпись, если в lines.json нет строк этого типа.
    static func fallback(_ k: MomentKind) -> String {
        switch k {
        case .feed, .treat: return "Вкусный был день."
        case .play: return "Играли весь день."
        case .pets: return "Меня гладили. Хорошо."
        case .bath: return "Чистый и пушистый."
        case .find, .findFirst: return "Принёс находку с прогулки."
        case .wake, .morning: return "Доброе утро вместе."
        case .steps: return "Много гуляли."
        case .rescue: return "Ты меня выручил. Спасибо."
        case .firstDay: return "Наш первый день."
        case .days: return "Мы друзья уже давно."
        case .birthday: return "С днём рождения меня!"
        }
    }

    static func make(_ m: Moment, day: Int, petId: String, tzOffsetMin tz: Int, lines: Lines = .shared) -> Postcard {
        let line = lines.pick("away", m.kind.lineKey, seed: petId, slot: day, vars: vars(m), maxLen: captionMax)
        let l = look(m)
        return Postcard(id: "c\(day)", day: day, kind: m.kind.rawValue, t: m.t, tz: tz, score: m.score,
                        caption: line?.text ?? fallback(m.kind), lineId: line?.id, find: m.find, item: m.item,
                        count: m.count, pose: l.pose.rawValue, clip: l.clip, prop: l.prop,
                        expiresT: DayKey.start(day + 1, tzOffsetMin: tz) + life, savedT: nil, image: nil)
    }

    /// Открытка за день или nil, если день пустой. previous — тип вчерашней открытки.
    static func card(for day: Int, in f: SaveFile, tzOffsetMin tz: Int, previous: MomentKind? = nil) -> Postcard? {
        guard let m = choose(moments(f, day: day, tzOffsetMin: tz), petId: f.petId, day: day, previous: previous) else {
            return nil
        }
        return make(m, day: day, petId: f.petId, tzOffsetMin: tz)
    }

    // MARK: жизнь открыток

    /// Убрать просроченные и собрать открытки за прошедшие дни (не старше 7). Зовётся из PetRunner.catchUp,
    /// то есть при любой записи: из приложения, виджета или интента. Возвращает новые открытки.
    @discardableResult
    static func refresh(_ f: inout SaveFile, now: Double) -> [Postcard] {
        let tz = f.owner.tzOffsetMin
        f.cards.pending.removeAll { $0.expiresT <= now }
        let today = DayKey.of(now, tzOffsetMin: tz)
        var from = max(DayKey.of(f.createdT, tzOffsetMin: tz), today - lifeDays)
        if let done = f.cards.doneDay { from = max(from, done + 1) }
        // День смерти и после — без открыток.
        let deathDay: Int? = f.pet.alive ? nil : DayKey.of(f.pet.diedAt ?? f.pet.t, tzOffsetMin: tz)
        var made: [Postcard] = []
        if from < today {
            for d in from..<today {
                if let dd = deathDay, d >= dd { break }
                if f.cards.card("c\(d)") != nil { continue }
                let previous = f.cards.card("c\(d - 1)")?.momentKind
                if let c = card(for: d, in: f, tzOffsetMin: tz, previous: previous), c.expiresT > now {
                    f.cards.pending.append(c)
                    made.append(c)
                }
            }
        }
        f.cards.doneDay = max(f.cards.doneDay ?? (today - 1), today - 1)
        // Кадры дня (PostcardPhotos): новым открыткам — кадр момента, кадры прошедших дней — прочь.
        PostcardPhotos.settle(&f, made: made.map(\.id), today: today)
        return made.map { f.cards.card($0.id) ?? $0 }
    }

    /// Открытки последних 7 дней (и сохранённые, и нет), свежие первыми. Ничего не пишет:
    /// досчитывает копию, так что виджет и экран видят открытку и до первой записи после полуночи.
    /// Если есть неразобранный прошедший день, копию сначала догоняем (PetRunner.catchUp): иначе события
    /// между pet.t и полуночью (возвращение с прогулки и т.п.) ещё не в журнале, и виджет показал бы
    /// не ту открытку (или никакой), что запишется при следующем открытии.
    static func active(_ f: SaveFile, now: Double) -> [Postcard] {
        var g = f
        if hasUnsettledDay(g, now: now) { PetRunner.catchUp(&g, now: now) }
        refresh(&g, now: now)
        let live = g.cards.pending + g.cards.album.filter { $0.expiresT > now }
        return live.sorted { $0.day > $1.day }
    }

    /// Есть ли прошедший местный день, за который refresh ещё не выдавал открытку (пояс — как в catchUp).
    static func hasUnsettledDay(_ f: SaveFile, now: Double) -> Bool {
        let tz = Clock.tzOffsetMin(at: now)
        let today = DayKey.of(now, tzOffsetMin: tz)
        var from = max(DayKey.of(f.createdT, tzOffsetMin: tz), today - lifeDays)
        if let done = f.cards.doneDay { from = max(from, done + 1) }
        return from < today
    }

    /// Самая свежая живая открытка.
    static func latest(_ f: SaveFile, now: Double) -> Postcard? { active(f, now: now).first }

    /// Альбом, свежие дни первыми.
    static func album(_ f: SaveFile) -> [Postcard] {
        f.cards.album.sorted { $0.day > $1.day }
    }

    enum SaveResult: String, Sendable {
        case saved, already, expired, notFound = "not_found", albumFull = "album_full"
    }

    /// Сохранить в альбом. Альбом полон — отказ (album_full): хозяин сам решает, что удалить.
    @discardableResult
    static func save(_ id: String, in f: inout SaveFile, now: Double) -> SaveResult {
        if f.cards.album.contains(where: { $0.id == id }) { return .already }
        let wasPending = f.cards.pending.contains { $0.id == id }
        refresh(&f, now: now)
        guard let i = f.cards.pending.firstIndex(where: { $0.id == id }) else { return wasPending ? .expired : .notFound }
        if f.cards.album.count >= PostcardBook.albumMax { return .albumFull }
        var c = f.cards.pending.remove(at: i)
        c.savedT = now
        f.cards.album.append(c)
        return .saved
    }

    /// Не сохранять: открытка уходит сразу, не дожидаясь срока. Повторно не соберётся (день уже разобран).
    static func discard(_ id: String, in f: inout SaveFile) {
        f.cards.pending.removeAll { $0.id == id }
    }

    /// Удалить из альбома.
    @discardableResult
    static func remove(_ id: String, in f: inout SaveFile) -> Bool {
        let n = f.cards.album.count
        f.cards.album.removeAll { $0.id == id }
        return f.cards.album.count != n
    }

    /// Снимок 3D положил кадр: запомнить имя файла у открытки (где бы она ни лежала).
    static func setImage(_ name: String?, for id: String, in f: inout SaveFile) {
        if let i = f.cards.pending.firstIndex(where: { $0.id == id }) { f.cards.pending[i].image = name }
        if let i = f.cards.album.firstIndex(where: { $0.id == id }) { f.cards.album[i].image = name }
    }

    // MARK: через стор

    /// Сохранить из экрана: догнать время и сохранить одной записью.
    @discardableResult
    static func save(_ id: String, store: PetStore = .shared, now: Double = Clock.now()) throws -> SaveResult {
        try store.mutate { f in
            PetRunner.catchUp(&f, now: now)
            return save(id, in: &f, now: now)
        }
    }

    static func discard(_ id: String, store: PetStore = .shared, now: Double = Clock.now()) throws {
        try store.mutate { f in
            PetRunner.catchUp(&f, now: now)
            discard(id, in: &f)
        }
    }

    static func remove(_ id: String, store: PetStore = .shared) throws {
        try store.mutate { f in _ = remove(id, in: &f) }
    }

    // MARK: мелочи

    private static func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

    /// 12500 → «12 500».
    static func grouped(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0 && (s.count - i) % 3 == 0 { out.append(" ") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}
