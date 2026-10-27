// Волна 39 C: достижения — единый список «за что», цель, прогресс из сейва, награда ✂️ и дата получения.
//
// Выплата — в Shards.settle (раздел 4): once-ключ ach.<id>, награда из PremiumConfig.achievements
// (economy.json → premium.sources.achievements), время — ShardLog.achT. Старые сейвы с ach.* в once второй раз
// не платят; даты у них нет — экран пишет просто «получено».
//
// Достижения хозяина: once переходит новому щенку (ShardLog.carriedOver), поэтому полученное остаётся полученным,
// даже если прогресс нового пса (уровень, трюки, рост) начался с нуля.

import Foundation

/// Одно достижение: что, за что и какая цель.
struct Achievement: Hashable, Sendable, Identifiable {
    let id: String
    let emoji: String
    /// Короткое название: «Ур. 10».
    let title: String
    /// За что, одной строкой.
    let note: String
}

/// Строка для экрана: достижение, прогресс, награда, получено ли и когда.
struct AchievementRow: Hashable, Sendable, Identifiable {
    let item: Achievement
    let progress: Int
    let goal: Int
    let reward: Int
    let got: Bool
    /// Когда получено; nil — не получено или старый сейв без даты.
    let t: Double?

    var id: String { item.id }
    /// Доля прогресса 0…1 (полученное — 1).
    var fraction: Double { got ? 1 : (goal > 0 ? min(1, Double(progress) / Double(goal)) : 0) }
}

enum Achievements {
    /// Порядок экрана: старые пять первыми (их id и награды не меняем), дальше по разделам.
    static let all: [Achievement] = [
        Achievement(id: "good_days_7", emoji: "📅", title: "Неделя заботы", note: "7 дней заботы"),
        Achievement(id: "good_days_30", emoji: "🗓", title: "Месяц заботы", note: "30 дней заботы"),
        Achievement(id: "good_days_100", emoji: "💯", title: "Сто дней", note: "100 дней заботы"),
        Achievement(id: "first_dish", emoji: "🍲", title: "Первое блюдо", note: "Приготовить что-нибудь на кухне"),
        Achievement(id: "first_trick", emoji: "🎓", title: "Первый трюк", note: "Выучить любой трюк"),
        // уровень
        Achievement(id: "level_5", emoji: "⭐", title: "Ур. 5", note: "Пёс дорос до 5 уровня"),
        Achievement(id: "level_10", emoji: "🌟", title: "Ур. 10", note: "Пёс дорос до 10 уровня"),
        Achievement(id: "level_20", emoji: "✨", title: "Ур. 20", note: "Пёс дорос до 20 уровня"),
        Achievement(id: "level_30", emoji: "👑", title: "Ур. 30", note: "Пёс дорос до 30 уровня"),
        // рост
        Achievement(id: "grow_teen", emoji: "🐕", title: "Подросток", note: "Щенок подрос"),
        Achievement(id: "grow_adult", emoji: "🦮", title: "Взрослый", note: "Пёс совсем вырос"),
        // двор
        Achievement(id: "yard_station", emoji: "🏭", title: "Первая станция", note: "Поставить станцию во дворе"),
        Achievement(id: "yard_gold", emoji: "🥇", title: "Золотая табличка", note: "Повесить золотую табличку станции"),
        Achievement(id: "yard_move", emoji: "🚚", title: "Переезд", note: "Перевезти двор в новый район"),
        Achievement(id: "yard_roof", emoji: "🏙", title: "На крыше", note: "Все переезды двора"),
        // места и находки
        Achievement(id: "trip_first", emoji: "🎒", title: "Первый поход", note: "Сходить в любое место"),
        Achievement(id: "trip_set", emoji: "🧺", title: "Полный набор", note: "Собрать все находки одного места"),
        Achievement(id: "trip_all", emoji: "🗺", title: "Все места", note: "Побывать в каждом месте на карте"),
        Achievement(id: "finds_all", emoji: "🦴", title: "Все находки", note: "Принести с прогулки находки всех видов"),
        // кухня и трюки
        Achievement(id: "recipes_all", emoji: "🧑‍🍳", title: "Все рецепты", note: "Приготовить каждое блюдо"),
        Achievement(id: "tricks_all", emoji: "🎪", title: "Все трюки", note: "Выучить все трюки"),
        // игры и челленджи
        Achievement(id: "games_all", emoji: "🎮", title: "Все игры", note: "Набрать очки в каждой мини-игре"),
        Achievement(id: "challenge_first", emoji: "🎯", title: "Первый челлендж", note: "Выполнить челлендж дня"),
        Achievement(id: "challenge_10", emoji: "🏅", title: "Десять челленджей", note: "Выполнить 10 челленджей"),
        // открытки
        Achievement(id: "postcard_first", emoji: "💌", title: "Первая открытка", note: "Сохранить открытку в альбом"),
        Achievement(id: "postcards_10", emoji: "📚", title: "Десять открыток", note: "10 открыток в альбоме"),
    ]

    static func item(_ id: String) -> Achievement? { all.first { $0.id == id } }

    /// Ключ в ShardLog.once.
    static func key(_ id: String) -> String { "ach.\(id)" }

    /// Цель: сколько нужно.
    static func goal(_ id: String) -> Int {
        switch id {
        case "good_days_7": return 7
        case "good_days_30": return 30
        case "good_days_100": return 100
        case "level_5": return 5
        case "level_10": return 10
        case "level_20": return 20
        case "level_30": return 30
        case "grow_teen": return Int(GrowthConfig.shared.teen.rounded(.up))
        case "grow_adult": return Int(GrowthConfig.shared.adult.rounded(.up))
        case "yard_roof": return YardConfig.shared.gloryX.count
        case "trip_all": return PlacesConfig.shared.places.count
        case "finds_all": return Finds.all.count
        case "recipes_all": return CookConfig.shared.recipes.count
        case "tricks_all": return Trick.allCases.count
        case "games_all": return Shards.recordGames.count
        case "challenge_10", "postcards_10": return 10
        default: return 1
        }
    }

    /// Прогресс из сейва (может быть больше цели).
    static func progress(_ id: String, _ f: SaveFile) -> Int {
        switch id {
        case "good_days_7", "good_days_30", "good_days_100": return f.shardLog.goodDays
        case "first_dish": return f.cooking.total.values.contains { $0 > 0 } ? 1 : 0
        case "first_trick": return f.tricks.items.values.contains { $0.learned != nil } ? 1 : 0
        case "level_5", "level_10", "level_20", "level_30": return DogLevel.level(f)
        case "grow_teen", "grow_adult": return Int(f.growth.points)
        case "yard_station": return f.yard.stations.values.contains { $0 > 0 } ? 1 : 0
        case "yard_gold": return f.yard.gold.isEmpty ? 0 : 1
        case "yard_move", "yard_roof": return f.yard.moves
        case "trip_first": return f.trip.count
        case "trip_set": return f.trip.sets.count
        case "trip_all": return PlacesConfig.shared.places.filter { (f.trip.visits[$0.id] ?? 0) > 0 }.count
        case "finds_all": return Finds.kinds(f.pet.finds)
        case "recipes_all": return CookConfig.shared.recipes.filter { (f.cooking.total[$0.id] ?? 0) > 0 }.count
        case "tricks_all": return Trick.allCases.filter { f.tricks.items[$0.rawValue]?.learned != nil }.count
        case "games_all": return Shards.records(f).values.filter { $0 > 0 }.count
        case "challenge_first", "challenge_10": return f.challenge.count
        case "postcard_first", "postcards_10": return f.cards.album.count
        default: return 0
        }
    }

    /// Цель достигнута сейчас (без учёта «уже получено»).
    static func done(_ id: String, _ f: SaveFile) -> Bool { progress(id, f) >= goal(id) }

    /// Что достигнуто по сейву — в порядке списка. Платит Shards.settle.
    static func reached(_ f: SaveFile) -> [String] { all.map(\.id).filter { done($0, f) } }

    /// Получено (оплачено) — по once, а не по прогрессу: новый щенок полученного не теряет.
    static func got(_ id: String, _ f: SaveFile) -> Bool { f.shardLog.once.contains(key(id)) }

    static func reward(_ id: String, _ cfg: PremiumConfig = .shared) -> Int { cfg.achievements[id] ?? 0 }

    /// Строки экрана: полученные и нет — в порядке списка.
    static func rows(_ f: SaveFile, _ cfg: PremiumConfig = .shared) -> [AchievementRow] {
        all.map { a in
            let g = goal(a.id)
            let has = got(a.id, f)
            return AchievementRow(item: a, progress: min(g, max(0, progress(a.id, f))), goal: g,
                                  reward: reward(a.id, cfg), got: has, t: has ? f.shardLog.achT[a.id] : nil)
        }
    }

    static func gotCount(_ f: SaveFile) -> Int { all.filter { got($0.id, f) }.count }

    // MARK: Тексты

    /// «Получено 4 из 25».
    static func summary(_ f: SaveFile) -> String { "Получено \(gotCount(f)) из \(all.count)" }

    /// Награда на карточке: «+5 ✂️».
    static func rewardText(_ n: Int) -> String { "+\(n) ✂️" }

    /// Прогресс неполученного: «3 / 7».
    static func progressText(_ r: AchievementRow) -> String { "\(r.progress) / \(r.goal)" }

    /// Статус полученного: «Получено 17 октября» или просто «Получено» (старый сейв без даты).
    static func gotText(_ r: AchievementRow) -> String {
        guard let t = r.t else { return "Получено" }
        return "Получено \(Postcards.dateLabel(DayKey.of(t)))"
    }

    /// VoiceOver одной фразой: «Ур. 10. Пёс дорос до 10 уровня. Получено 17 октября. Награда 3 клочка».
    static func speech(_ r: AchievementRow) -> String {
        let state = r.got ? gotText(r) : "Пока \(r.progress) из \(r.goal)"
        return "\(r.item.title). \(r.item.note). \(state). Награда \(EconText.shards(r.reward))"
    }

    /// Подпись начисления для тоста ✂️ и истории: «за достижение «Ур. 10»».
    static func reasonText(_ reason: String) -> String? {
        guard reason.hasPrefix("ach."), let a = item(String(reason.dropFirst(4))) else { return nil }
        return "за достижение «\(a.title)»"
    }

    /// Тост при получении: «Достижение: Ур. 10 · +3 ✂️»; несколько разом — одной строкой. also — обычная выплата
    /// того же действия (день заботы): дописывается в тот же тост, второго тоста подряд нет (волна 40 E).
    static func toast(_ ids: [String], also: ShardGain? = nil, _ cfg: PremiumConfig = .shared) -> String? {
        let items = ids.compactMap(item)
        guard let first = items.first else { return nil }
        let sum = items.reduce(0) { $0 + reward($1.id, cfg) }
        let head = items.count == 1 ? "Достижение: \(first.title)" : "Достижения: \(items.count) новых"
        let main = sum > 0 ? "\(head) · \(rewardText(sum))" : head
        guard let g = also, g.shards > 0, !g.reason.hasPrefix("ach.") else { return main }
        return "\(main) · \(Shards.gainText(g))"
    }

    /// Свежие для тоста: получены не раньше 10 с назад и позже показанного (shownT). Самые новые — по времени.
    static func fresh(_ f: SaveFile, now: Double, shownT: Double?) -> (ids: [String], t: Double)? {
        let recent = f.shardLog.achT.filter { now - $0.value < 10 && $0.value <= now + 1 && $0.value > (shownT ?? -.infinity) }
        guard let t = recent.values.max() else { return nil }
        let ids = all.map(\.id).filter { recent[$0] != nil }
        return (ids, t)
    }
}
