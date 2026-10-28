// Волна 33 D. Карта необычных мест: походы поверх обычной прогулки ядра (RESEARCH/20-tycoon-design.md §5).
// Ядро не трогаем. Прогулка (`outing`) остаётся прогулкой: шкалы, ранний возврат ночью или в беде, находка ядра
// в альбом прогулок — всё как было. Место сверху задаёт время похода и свою находку:
//   start  — прогулка уже идёт (или `go` сам её начинает): запоминаем место, until прогулки = время места;
//   settle — прогулка, к которой привязан поход, кончилась: ровно одна находка места (70/25/5, на месте дня ★
//            редкие ×2), мини-событие с текстом записки, 3 % — 1 ✂️, полный набор места — 8 ✂️ один раз,
//            повторка — +5 🪙, опыт пса в журнал (place.back) для DogLevel.
// Колодец эха — отдельная кнопка «Бросить монетку»: раз в сутки, 20 🪙, 10 % — 1 ✂️.
// Уровень пса и множитель роста приходят параметрами: DogLevel и Growth (агенты A и B) здесь не читаем.
// Случайность — только хеш (StableHash + StableRandom): тот же сейв даёт ту же находку на любом устройстве.
// Цифры и тексты — config/places.json, здесь те же значения по умолчанию.

import Foundation
@preconcurrency import PetCore

// MARK: - Конфиг

/// Редкость находки места.
enum FindTier: String, CaseIterable, Codable, Sendable {
    case common
    case rare
    case veryRare = "very_rare"

    var title: String {
        switch self {
        case .common: return "обычная"
        case .rare: return "редкая"
        case .veryRare: return "очень редкая"
        }
    }
}

/// Находка места. Очень редкие — будущие вещи (волна 34): role «toy» — игрушка в «Поиграть»,
/// «light» — свет в комнату, «decor» — на полку (ItemCatalog.decor). Пока только альбом.
struct PlaceFind: Hashable, Sendable {
    let id: String
    let name: String
    let emoji: String
    let tier: FindTier
    var role: String? = nil
}

/// Что событие делает, кроме записки.
enum PlaceEffect: Hashable, Sendable {
    case none
    /// Прибавка к шкале сразу при возвращении (полотенце +10 чистоты, мультик +10 веселья, мурчание +10 сил).
    case need(Need, Double)
    /// +1 🎟 не чаще раза в неделю (с понедельника), иначе — текст spent.
    case ticket
    /// Кадр в открытку: флаг в итоге, открытку собирает экран (волна 34).
    case photo
    /// Прогноз на завтра: {forecast} в тексте.
    case forecast
    /// Подсказка про «Бросить монетку».
    case well
}

/// Мини-событие похода. text — текст записки, spent — если эффект уже был (жетон на этой неделе).
struct PlaceEvent: Hashable, Sendable {
    let id: String
    let text: String
    var effect: PlaceEffect = .none
    var spent: String? = nil
}

/// Место на карте. about — подпись на бумажной карте (волна 34).
struct Place: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let emoji: String
    /// С какого уровня пса открыто.
    let level: Int
    /// Время похода у подростка без ускорения, минуты.
    let minutes: Int
    let about: String
    let finds: [PlaceFind]
    let events: [PlaceEvent]

    func finds(_ t: FindTier) -> [PlaceFind] { finds.filter { $0.tier == t } }
}

struct PlacesConfig: Hashable, Sendable {
    /// Шансы редкой и очень редкой находки, %; обычная — остаток.
    var rarePct = 25
    var veryRarePct = 5
    /// Место дня ★: оба редких шанса ×starX.
    var starX = 2.0
    var repeatCoins = 5
    var setShards = 8
    var shardChancePct = 3
    var xpTrip = 10
    var xpFirst = 15
    /// С уровня пса fastLevel походы короче в fastX раз.
    var fastLevel = 20
    var fastX = 0.9
    var wellPlace = "echo_well"
    var wellCoins = 20
    var wellChancePct = 10
    var wellShards = 1
    var forecasts: [String] = PlacesConfig.stubForecasts
    var places: [Place] = PlacesConfig.stubPlaces

    static let shared = PlacesConfig(json: PlacesConfig.file() ?? .null)

    /// places.json из бандла. Нет файла (Linux-сборка, файл не подключён) — значения по умолчанию.
    static func file() -> JSONValue? {
        guard let data = Catalog.resource("places", "json") else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let p = e["places"]
        rarePct = min(100, max(0, int(p["tiers_pct"]["rare"], rarePct)))
        veryRarePct = min(100 - rarePct, max(0, int(p["tiers_pct"]["very_rare"], veryRarePct)))
        starX = max(1, p["star_rare_x"].double ?? starX)
        repeatCoins = max(0, int(p["repeat_coins"], repeatCoins))
        setShards = max(0, int(p["set_shards"], setShards))
        shardChancePct = min(100, max(0, int(p["shard_chance_pct"], shardChancePct)))
        xpTrip = max(0, int(p["xp"]["trip"], xpTrip))
        xpFirst = max(0, int(p["xp"]["first_visit"], xpFirst))
        fastLevel = max(1, int(p["fast"]["level"], fastLevel))
        fastX = min(1, max(0.1, p["fast"]["x"].double ?? fastX))
        let w = p["well"]
        wellPlace = w["place"].string ?? wellPlace
        wellCoins = max(0, int(w["coins"], wellCoins))
        wellChancePct = min(100, max(0, int(w["chance_pct"], wellChancePct)))
        wellShards = max(0, int(w["shards"], wellShards))
        let fc = p["forecasts"].array.compactMap { $0.string }
        if !fc.isEmpty { forecasts = fc }
        // Список мест — целиком или никак: одно битое место — остаёмся на встроенном.
        let raw = p["list"].array
        let list = raw.compactMap(Self.place)
        if !raw.isEmpty, list.count == raw.count, Set(list.map(\.id)).count == list.count { places = list }
    }

    private static func place(_ v: JSONValue) -> Place? {
        guard let id = v["id"].string, let name = v["name"].string,
              let level = v["level"].double, let minutes = v["minutes"].double, minutes >= 1 else { return nil }
        let finds = v["finds"].array.compactMap { (it: JSONValue) -> PlaceFind? in
            guard let fid = it["id"].string, let n = it["name"].string,
                  let tier = it["tier"].string.flatMap(FindTier.init(rawValue:)) else { return nil }
            return PlaceFind(id: fid, name: n, emoji: it["emoji"].string ?? "📦", tier: tier, role: it["role"].string)
        }
        let events = v["events"].array.compactMap { (it: JSONValue) -> PlaceEvent? in
            guard let eid = it["id"].string, let text = it["text"].string else { return nil }
            return PlaceEvent(id: eid, text: text, effect: effect(it["effect"]), spent: it["spent"].string)
        }
        // Каждой редкости хоть одна находка, хоть одно событие — иначе выбирать не из чего.
        guard finds.count == v["finds"].array.count, events.count == v["events"].array.count, !events.isEmpty,
              FindTier.allCases.allSatisfy({ t in finds.contains { $0.tier == t } }) else { return nil }
        return Place(id: id, name: name, emoji: v["emoji"].string ?? "📍", level: max(0, Int(level)),
                     minutes: Int(minutes), about: v["about"].string ?? "", finds: finds, events: events)
    }

    private static func effect(_ v: JSONValue) -> PlaceEffect {
        switch v["kind"].string {
        case "need":
            guard let n = v["need"].string.flatMap(Need.init(rawValue:)), let add = v["add"].double else { return .none }
            return .need(n, add)
        case "ticket": return .ticket
        case "photo": return .photo
        case "forecast": return .forecast
        case "well": return .well
        default: return .none
        }
    }

    func place(_ id: String) -> Place? { places.first { $0.id == id } }

    static let stubForecasts: [String] = [
        "солнечно, ветер с юга",
        "дождик к обеду, потом радуга",
        "облачно, но по-доброму",
        "туман и запах блинов",
        "ясно, хороший день для прогулки",
        "листопад, местами лужи"
    ]

    /// Восемь мест §5. Тест сверяет с config/places.json.
    static let stubPlaces: [Place] = [
        Place(id: "bus_stop", name: "Остановка без автобуса", emoji: "🚏", level: 2, minutes: 30,
              about: "Будка посреди поля. На расписании 1997 год, автобусов с тех пор не было.",
              finds: [
                PlaceFind(id: "bus_stop.ticket", name: "Билетик-корешок", emoji: "🎫", tier: .common),
                PlaceFind(id: "bus_stop.button", name: "Пуговица", emoji: "🔘", tier: .common),
                PlaceFind(id: "bus_stop.wrapper", name: "Фантик", emoji: "🍬", tier: .common),
                PlaceFind(id: "bus_stop.badge", name: "Значок «Маршрут 0»", emoji: "📛", tier: .rare),
                PlaceFind(id: "bus_stop.postcard", name: "Старая открытка", emoji: "💌", tier: .rare),
                PlaceFind(id: "bus_stop.key", name: "Ключ от ниоткуда", emoji: "🗝", tier: .veryRare, role: "decor"),
              ],
              events: [
                PlaceEvent(id: "wait", text: "Посидел на лавке и подождал. Вдали гудел автобус, но так и не приехал."),
                PlaceEvent(id: "paper", text: "Ветер принёс газету. Новостей в ней нет, только кроссворд, разгаданный наполовину."),
                PlaceEvent(id: "pigeon", text: "Рядом сел голубь. Посидели вдвоём, помолчали."),
              ]),
        Place(id: "laundry", name: "Прачечная 24/7", emoji: "🧺", level: 5, minutes: 40,
              about: "Пустая прачечная с мигающей вывеской. Барабаны крутятся сами, внутри всегда тепло.",
              finds: [
                PlaceFind(id: "laundry.sock", name: "Носок в полоску", emoji: "🧦", tier: .common),
                PlaceFind(id: "laundry.clothespin", name: "Прищепка", emoji: "📎", tier: .common),
                PlaceFind(id: "laundry.coin", name: "Монетка", emoji: "🪙", tier: .common),
                PlaceFind(id: "laundry.plaid", name: "Тёплый плед-лоскут", emoji: "🧣", tier: .rare),
                PlaceFind(id: "laundry.ring", name: "Кольцо от стирки", emoji: "💍", tier: .rare),
                PlaceFind(id: "laundry.twin_sock", name: "Носок-близнец", emoji: "🧦", tier: .veryRare, role: "decor"),
              ],
              events: [
                PlaceEvent(id: "drum", text: "Смотрел в барабан и крутил головой, пока всё не закружилось."),
                PlaceEvent(id: "towel", text: "Машинка пискнула «готово» и выдала тёплое полотенце. Вытерся — стал чище.", effect: .need(.clean, 10)),
                PlaceEvent(id: "foam", text: "Из сушилки вылетело облако пены. Пахло лавандой и немножко им."),
              ]),
        Place(id: "cat_hill", name: "Холм-кот", emoji: "⛰", level: 8, minutes: 50,
              about: "Травяной холм, который дышит. Если присмотреться, из травы торчат усы: это спит огромный кот.",
              finds: [
                PlaceFind(id: "cat_hill.fur", name: "Клочок шерсти", emoji: "🧶", tier: .common),
                PlaceFind(id: "cat_hill.daisy", name: "Ромашка", emoji: "🌼", tier: .common),
                PlaceFind(id: "cat_hill.cone", name: "Шишка", emoji: "🌰", tier: .common),
                PlaceFind(id: "cat_hill.bell", name: "Кошачий колокольчик", emoji: "🔔", tier: .rare),
                PlaceFind(id: "cat_hill.feather", name: "Перо", emoji: "🪶", tier: .rare),
                PlaceFind(id: "cat_hill.dream", name: "Сон кота", emoji: "🔮", tier: .veryRare, role: "decor"),
              ],
              events: [
                PlaceEvent(id: "sigh", text: "Холм вздохнул: трава поднялась и опустилась. Кажется, ему снилось хорошее."),
                PlaceEvent(id: "eye", text: "Холм приоткрыл один глаз. Пёс замер и не шевелился, пока глаз не закрылся."),
                PlaceEvent(id: "purr", text: "Холм замурчал. Пёс прилёг в траву и проспал десять минут.", effect: .need(.energy, 10)),
              ]),
        Place(id: "arcade", name: "Аркада «Пиксель»", emoji: "🕹", level: 11, minutes: 60,
              about: "Заброшенный зал игровых автоматов. Света нет, а экраны всё равно светятся.",
              finds: [
                PlaceFind(id: "arcade.token", name: "Жетон", emoji: "🪙", tier: .common),
                PlaceFind(id: "arcade.mushroom_button", name: "Кнопка-грибок", emoji: "🍄", tier: .common),
                PlaceFind(id: "arcade.joystick", name: "Кусок джойстика", emoji: "🕹", tier: .common),
                PlaceFind(id: "arcade.cartridge", name: "Картридж без надписи", emoji: "💾", tier: .rare),
                PlaceFind(id: "arcade.scoreboard", name: "Табло рекордов", emoji: "📟", tier: .rare),
                PlaceFind(id: "arcade.pixel_ball", name: "Призовой мячик-пиксель", emoji: "🟨", tier: .veryRare, role: "toy"),
              ],
              events: [
                PlaceEvent(id: "record", text: "Автомат сам включился и показал таблицу рекордов. Первая строчка — твоя."),
                PlaceEvent(id: "token", text: "Из автомата выпал жетон. Принёс его тебе: +1 🎟.", effect: .ticket,
                           spent: "Из автомата выпал жетон, но жетон на этой неделе уже был. Оставил его там."),
                PlaceEvent(id: "bits", text: "Экран показал пса в восемь бит. Похож, только квадратнее."),
              ]),
        Place(id: "forest_tv", name: "Телевизор в лесу", emoji: "📺", level: 15, minutes: 75,
              about: "Старый ламповый телевизор на пне посреди ельника. Провода нет, а он работает.",
              finds: [
                PlaceFind(id: "forest_tv.antenna", name: "Антенна-рожки", emoji: "📡", tier: .common),
                PlaceFind(id: "forest_tv.mushroom", name: "Гриб", emoji: "🍄", tier: .common),
                PlaceFind(id: "forest_tv.tape", name: "Лента от кассеты", emoji: "📼", tier: .common),
                PlaceFind(id: "forest_tv.remote", name: "Пульт без кнопок", emoji: "🎛", tier: .rare),
                PlaceFind(id: "forest_tv.cassette", name: "Кассета «Пёс и я»", emoji: "📼", tier: .rare),
                PlaceFind(id: "forest_tv.static_jar", name: "Помеха в банке", emoji: "🫙", tier: .veryRare, role: "decor"),
              ],
              events: [
                PlaceEvent(id: "face", text: "Помехи на экране сложились в собачью морду. Он гавкнул на неё, она — на него."),
                PlaceEvent(id: "forecast", text: "Телевизор показал прогноз на завтра: {forecast}.", effect: .forecast),
                PlaceEvent(id: "cartoon", text: "Включился мультик. Пёс досмотрел до конца и остался очень доволен.", effect: .need(.fun, 10)),
              ]),
        Place(id: "lighthouse", name: "Маяк в поле", emoji: "🗼", level: 19, minutes: 90,
              about: "Маяк среди пшеницы. До моря сто километров, а он всё равно светит.",
              finds: [
                PlaceFind(id: "lighthouse.wheat", name: "Колосок", emoji: "🌾", tier: .common),
                PlaceFind(id: "lighthouse.shell", name: "Ракушка", emoji: "🐚", tier: .common),
                PlaceFind(id: "lighthouse.bulb", name: "Лампочка", emoji: "💡", tier: .common),
                PlaceFind(id: "lighthouse.flag", name: "Флажок", emoji: "🚩", tier: .rare),
                PlaceFind(id: "lighthouse.keeper_key", name: "Ключ смотрителя", emoji: "🔑", tier: .rare),
                PlaceFind(id: "lighthouse.light", name: "Кусочек света", emoji: "✨", tier: .veryRare, role: "light"),
              ],
              events: [
                PlaceEvent(id: "howl", text: "Свет маяка прошёл над пшеницей. Пёс не удержался и завыл."),
                PlaceEvent(id: "thanks", text: "С маяка сбросили записку: «Спасибо, что зашёл». Кто — не видно."),
                PlaceEvent(id: "foxes", text: "В пшенице бегала стайка лис. Звали играть, но он постеснялся."),
              ]),
        Place(id: "echo_well", name: "Колодец эха", emoji: "🪣", level: 24, minutes: 105,
              about: "Старый каменный колодец. Отвечает лаем на лай, иногда не своим голосом.",
              finds: [
                PlaceFind(id: "echo_well.pebble", name: "Камешек", emoji: "🪨", tier: .common),
                PlaceFind(id: "echo_well.moss", name: "Мох", emoji: "🌿", tier: .common),
                PlaceFind(id: "echo_well.bucket", name: "Ведёрко", emoji: "🪣", tier: .common),
                PlaceFind(id: "echo_well.holed_coin", name: "Монета с дыркой", emoji: "🪙", tier: .rare),
                PlaceFind(id: "echo_well.echo_bottle", name: "Эхо в бутылке", emoji: "🍾", tier: .rare),
                PlaceFind(id: "echo_well.letter", name: "Письмо со дна", emoji: "✉️", tier: .veryRare, role: "decor"),
              ],
              events: [
                PlaceEvent(id: "echo", text: "Гавкнул в колодец. Колодец ответил, но другим голосом."),
                PlaceEvent(id: "coins", text: "На дне блестят монетки. Можно бросить свою на удачу, раз в день.", effect: .well),
                PlaceEvent(id: "bubbles", text: "Из колодца вылетели пузыри. Один лопнул прямо на носу."),
              ]),
        Place(id: "rocket", name: "Картонная ракета", emoji: "🚀", level: 30, minutes: 120,
              about: "Ракета из коробок и скотча на пустыре. «Полёт» назначен на завтра.",
              finds: [
                PlaceFind(id: "rocket.tape", name: "Скотч", emoji: "🧻", tier: .common),
                PlaceFind(id: "rocket.nut", name: "Гайка", emoji: "🔩", tier: .common),
                PlaceFind(id: "rocket.foil_star", name: "Звезда из фольги", emoji: "⭐", tier: .common),
                PlaceFind(id: "rocket.helmet", name: "Шлем-дуршлаг", emoji: "🪖", tier: .rare),
                PlaceFind(id: "rocket.moon_map", name: "Карта Луны", emoji: "🗺", tier: .rare),
                PlaceFind(id: "rocket.moon_stone", name: "Лунный камень", emoji: "🌑", tier: .veryRare, role: "decor"),
              ],
              events: [
                PlaceEvent(id: "countdown", text: "Начался обратный отсчёт. На нуле ракета чихнула дымом и осталась на месте."),
                PlaceEvent(id: "cabin", text: "Посидел в кабине в шлеме-дуршлаге. Вышел отличный кадр для открытки.", effect: .photo),
                PlaceEvent(id: "star", text: "Над ракетой упала звезда. Он что-то загадал, но не говорит что."),
              ]),
    ]
}

// MARK: - Сохранение

/// Поход, который идёт сейчас. from — начало прогулки ядра: по нему видно, что вернулся именно с неё.
struct ActiveTrip: Codable, Hashable, Sendable {
    var place: String
    var from: Double
    var start: Double
    var until: Double
    /// Пошёл на место дня ★ (шанс редкой ×2).
    var star: Bool
}

/// Итог похода — для записки на экране и тоста. Последний хранится в TripLog.last.
struct TripResult: Codable, Hashable, Sendable {
    var place: String
    var find: String
    var tier: FindTier
    /// Первая такая находка — в альбом; иначе повторка (+coins).
    var isNew: Bool
    var coins = 0
    /// Случайный клочок за поход: 0 или 1.
    var shards = 0
    /// За полный набор места: 0 или setShards (один раз на место).
    var setShards = 0
    var xp = 0
    var event: String
    /// Текст записки события (уже с подстановками).
    var note: String
    var star = false
    var ticket = false
    var photo = false
    var t: Double
    /// Волна 34: взрослый иногда приносит вторую находку (Growth.perks.findDoublePct). nil — одна.
    /// Опциональные — старые сейвы без этих ключей читаются.
    var extra: String? = nil
    var extraTier: FindTier? = nil
    var extraNew: Bool? = nil
}

/// Поле `trip` в SaveFile. Пустое не пишется — старые сейвы читаются без него.
struct TripLog: Codable, Hashable, Sendable {
    var active: ActiveTrip?
    /// Сколько походов закончено — номер следующего в хеше.
    var count = 0
    /// Место → сколько раз был.
    var visits: [String: Int] = [:]
    /// Находка места → сколько раз приносил.
    var album: [String: Int] = [:]
    /// Места, за полный набор которых уже заплачено.
    var sets: [String] = []
    /// Неделя последнего жетона из аркады (Shards.week), 0 — не было.
    var ticketWeek = 0
    /// Сутки последней монетки в колодец, 0 — не бросали.
    var wellDay = 0
    /// Опыт пса от походов всего (тот же опыт — в журнале place.back).
    var xp = 0
    var last: TripResult?

    init() {}

    var isEmpty: Bool { self == TripLog() }

    enum CodingKeys: String, CodingKey {
        case active, count, visits, album, sets, ticketWeek, wellDay, xp, last
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = try? c.decodeIfPresent(ActiveTrip.self, forKey: .active)
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        visits = (try? c.decodeIfPresent([String: Int].self, forKey: .visits)) ?? [:]
        album = (try? c.decodeIfPresent([String: Int].self, forKey: .album)) ?? [:]
        sets = (try? c.decodeIfPresent([String].self, forKey: .sets)) ?? []
        ticketWeek = (try? c.decodeIfPresent(Int.self, forKey: .ticketWeek)) ?? 0
        wellDay = (try? c.decodeIfPresent(Int.self, forKey: .wellDay)) ?? 0
        xp = (try? c.decodeIfPresent(Int.self, forKey: .xp)) ?? 0
        last = try? c.decodeIfPresent(TripResult.self, forKey: .last)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(active, forKey: .active)
        if count != 0 { try c.encode(count, forKey: .count) }
        if !visits.isEmpty { try c.encode(visits, forKey: .visits) }
        if !album.isEmpty { try c.encode(album, forKey: .album) }
        if !sets.isEmpty { try c.encode(sets, forKey: .sets) }
        if ticketWeek != 0 { try c.encode(ticketWeek, forKey: .ticketWeek) }
        if wellDay != 0 { try c.encode(wellDay, forKey: .wellDay) }
        if xp != 0 { try c.encode(xp, forKey: .xp) }
        try c.encodeIfPresent(last, forKey: .last)
    }
}

/// Волна 36 O: тост «Сходил: …» ровно один раз, кто бы ни досчитал поход — пауза notePlaceBack, тикер, виджет,
/// интент или вход в приложение. Помнит номер последнего рассказанного похода (TripLog.count растёт на каждом
/// settle). Ничего не пишет в сейв: живёт в памяти приложения.
struct TripHerald: Hashable, Sendable {
    /// Тост только о свежем возвращении: старше — его уже покажет (или показал) отчёт «Пока тебя не было».
    static let window: Double = 3600

    private(set) var petId: String?
    /// Походов рассказано (= TripLog.count на момент последнего взгляда).
    private(set) var told = 0

    init() {}

    /// Всё, что уже есть в сейве, считать рассказанным: первый взгляд, отчёт «Пока тебя не было» с карточкой места.
    mutating func sync(_ f: SaveFile) {
        petId = f.petId
        told = f.trip.count
    }

    /// Что рассказать сейчас: последний поход, если о нём ещё не говорили, пёс дома и жив, а вернулся недавно.
    func due(_ f: SaveFile, now: Double) -> TripResult? {
        guard petId == f.petId, f.trip.count > told, f.trip.active == nil, f.pet.alive,
              let r = f.trip.last, now - r.t < Self.window else { return nil }
        return r
    }

    /// Забрать новость (ровно один раз). Новый пёс или откат сейва — просто запомнить, что есть.
    mutating func take(_ f: SaveFile, now: Double) -> TripResult? {
        let r = due(f, now: now)
        sync(f)
        return r
    }
}

// MARK: - Походы

enum PlaceRefusal: Error, Hashable, Sendable {
    case unknown
    /// Откроется с этого уровня пса.
    case locked(level: Int)
    /// Пёс не гуляет: поход идёт только поверх прогулки.
    case noOuting
    /// Уже в походе.
    case busy
    case dead
    /// Прогулку не пустило ядро: код отказа (asleep, not_ready, bathing…).
    case walk(String)
    /// Колодец: сегодня монетку уже бросали.
    case notToday
    /// Колодец: не хватает монет.
    case notEnough(need: Int)
}

/// Итог «Бросить монетку».
struct WellResult: Hashable, Sendable {
    let coins: Int
    let shards: Int
    let text: String
}

/// Карточка места для бумажной карты (волна 34).
struct PlaceCard: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let emoji: String
    let about: String
    let open: Bool
    /// Место дня.
    let star: Bool
    /// Время похода сейчас (с ростом и уровнем), минуты.
    let minutes: Int
    let have: Int
    let total: Int
    let visits: Int
    /// «Откроется на 11 уровне» / «Находки 3 из 6» / «Всё найдено».
    let line: String
}

enum Places {
    /// Причины ✂️ в ShardGain.reason.
    static let shardReason = "place"
    static let setReason = "place_set"
    static let wellReason = "well"

    static func hash(_ s: String) -> UInt64 { StableRandom.mix(StableHash.fnv1a(s)) }

    static func place(_ id: String, _ cfg: PlacesConfig = .shared) -> Place? { cfg.place(id) }

    static func isOpen(_ p: Place, dogLevel: Int) -> Bool { dogLevel >= p.level }

    /// Открытые места по порядку карты.
    static func unlocked(dogLevel: Int, _ cfg: PlacesConfig = .shared) -> [Place] {
        cfg.places.filter { isOpen($0, dogLevel: dogLevel) }
    }

    /// Время похода: минуты места × рост (щенок 1,3 / подросток 1 / взрослый 0,85) × 0,9 с уровня 20.
    static func minutes(_ p: Place, growthX: Double = 1, dogLevel: Int, _ cfg: PlacesConfig = .shared) -> Int {
        let x = max(0.1, growthX) * (dogLevel >= cfg.fastLevel ? cfg.fastX : 1)
        return max(1, Int((Double(p.minutes) * x).rounded()))
    }

    /// Место дня ★: одно из открытых, по хешу пса и местных суток. Нет открытых — nil.
    /// Волна 36 O: сутки — DayKey.of (пояс телефона на момент now), как у уровня и всех дневных счётчиков.
    static func placeOfDay(_ f: SaveFile, dogLevel: Int, now: Double, _ cfg: PlacesConfig = .shared) -> String? {
        let open = unlocked(dogLevel: dogLevel, cfg)
        guard !open.isEmpty else { return nil }
        let day = DayKey.of(now)
        return open[Int(hash("\(f.petId):star:\(day)") % UInt64(open.count))].id
    }

    /// Шансы находки в процентах: обычная, редкая, очень редкая (сумма 100).
    static func odds(star: Bool, _ cfg: PlacesConfig = .shared) -> [FindTier: Int] {
        let x = star ? cfg.starX : 1
        let vr = min(100, Int((Double(cfg.veryRarePct) * x).rounded()))
        let rr = min(100 - vr, Int((Double(cfg.rarePct) * x).rounded()))
        return [.common: 100 - vr - rr, .rare: rr, .veryRare: vr]
    }

    static func tier(_ u: UInt64, star: Bool, _ cfg: PlacesConfig = .shared) -> FindTier {
        let o = odds(star: star, cfg)
        let v = Int(u % 100)
        if v < o[.veryRare]! { return .veryRare }
        if v < o[.veryRare]! + o[.rare]! { return .rare }
        return .common
    }

    /// Куда ушёл сейчас: поход привязан к идущей прогулке. Для виджета «ушёл на Маяк».
    static func current(_ f: SaveFile, _ cfg: PlacesConfig = .shared) -> Place? {
        guard let a = f.trip.active, let out = f.pet.outing, out.from == a.from else { return nil }
        return cfg.place(a.place)
    }

    /// Можно ли идти на место (без проверки прогулки — её решает ядро).
    static func check(_ id: String, _ f: SaveFile, dogLevel: Int, _ cfg: PlacesConfig = .shared) -> PlaceRefusal? {
        guard let p = cfg.place(id) else { return .unknown }
        if !f.pet.alive { return .dead }
        if !isOpen(p, dogLevel: dogLevel) { return .locked(level: p.level) }
        if f.trip.active != nil { return .busy }
        return nil
    }

    /// Поход поверх уже идущей прогулки. Прогулки нет — отказ noOuting: ядро не обходим.
    /// until прогулки становится временем места; ночь питомца обрезает поход, как и прогулку.
    static func start(_ id: String, in f: inout SaveFile, dogLevel: Int, growthX: Double = 1, now: Double,
                      _ cfg: PlacesConfig = .shared) -> Result<ActiveTrip, PlaceRefusal> {
        PetRunner.catchUp(&f, now: now)
        settle(&f, now: now, cfg)
        if let r = check(id, f, dogLevel: dogLevel, cfg) { return .failure(r) }
        guard let out = f.pet.outing, let p = cfg.place(id) else { return .failure(.noOuting) }
        let begin = max(out.from, now)
        var mins = minutes(p, growthX: growthX, dogLevel: dogLevel, cfg)
        let o = PetRunner.owner(f, at: begin)
        for k in 1...mins where PetEngine.petNight(begin + Double(k) * 60, Catalog.rules, o) {
            mins = k
            break
        }
        let trip = ActiveTrip(place: id, from: out.from, start: begin, until: begin + Double(mins) * 60,
                              star: placeOfDay(f, dogLevel: dogLevel, now: begin, cfg) == id)
        f.pet.outing?.until = trip.until
        f.trip.active = trip
        f.log("place.go", t: begin, key: id, value: mins)
        // Задание дня «сходить в место», опыт и достижения — этой же записью (волна 42 J).
        PetRunner.settleRewards(&f, now: now)
        return .success(trip)
    }

    /// Кнопка места на карте: прогулка (если ещё не гуляет) и поход. Место проверяем до прогулки,
    /// чтобы закрытое место не отправило пса просто гулять.
    static func go(_ id: String, in f: inout SaveFile, dogLevel: Int, growthX: Double = 1,
                   source: ActionSource = .app, now: Double,
                   _ cfg: PlacesConfig = .shared) -> Result<ActiveTrip, PlaceRefusal> {
        PetRunner.catchUp(&f, now: now)
        settle(&f, now: now, cfg)
        if let r = check(id, f, dogLevel: dogLevel, cfg) { return .failure(r) }
        if f.pet.outing == nil {
            let res = PetRunner.apply(.walk, source: source, to: &f, now: now)
            guard res.ok else { return .failure(.walk(res.reason ?? "unavailable")) }
        }
        return start(id, in: &f, dogLevel: dogLevel, growthX: growthX, now: now, cfg)
    }

    /// Через стор: одна запись под замком.
    static func perform(_ id: String, dogLevel: Int, growthX: Double = 1, store: PetStore = .shared,
                        now: Double = Clock.now()) throws -> Result<ActiveTrip, PlaceRefusal> {
        try store.mutate { f in go(id, in: &f, dogLevel: dogLevel, growthX: growthX, now: now) }
    }

    /// Вернулся: прогулка, к которой привязан поход, кончилась (звать после PetRunner.catchUp).
    /// Ровно одна находка места, событие, награды. Повторный вызов — nil. Пёс умер в походе — поход
    /// снимается без наград.
    /// Волна 34: зовётся из PetRunner.catchUp. doublePct — шанс второй находки; nil — по росту пса (Growth.perks).
    @discardableResult
    static func settle(_ f: inout SaveFile, now: Double, doublePct: Int? = nil,
                       _ cfg: PlacesConfig = .shared) -> TripResult? {
        guard let a = f.trip.active else { return nil }
        if let out = f.pet.outing, out.from == a.from { return nil }   // ещё гуляет
        f.trip.active = nil
        guard f.pet.alive, let p = cfg.place(a.place) else { return nil }

        let n = f.trip.count
        f.trip.count += 1
        let back = max(a.start, min(now, a.until))
        let day = DayKey.of(a.start)   // волна 36 O: сутки по DayKey, как у уровня (был owner.tzOffsetMin)
        let key = "\(f.petId):place:\(p.id):\(day):\(n)"

        // Находка: редкость, потом вещь внутри редкости.
        let tier = Self.tier(hash(key + ":tier"), star: a.star, cfg)
        let pool = p.finds(tier)
        let find = pool[Int(hash(key + ":find") % UInt64(pool.count))]
        let had = f.trip.album[find.id] ?? 0
        f.trip.album[find.id] = had + 1

        let ev = p.events[Int(hash(key + ":event") % UInt64(p.events.count))]
        var r = TripResult(place: p.id, find: find.id, tier: tier, isNew: had == 0, event: ev.id, note: ev.text,
                           star: a.star, t: back)
        if had > 0, cfg.repeatCoins > 0 {
            f.econ.wallet.coins += cfg.repeatCoins
            r.coins = cfg.repeatCoins
        }
        // Вторая находка взрослого: свой бросок по тому же ключу, своя редкость. До проверки набора — она тоже в счёт.
        let dbl = doublePct ?? Growth.perks(f).findDoublePct
        if dbl > 0, Int(hash(key + ":double") % 100) < dbl {
            let tier2 = Self.tier(hash(key + ":tier2"), star: a.star, cfg)
            let pool2 = p.finds(tier2)
            let x = pool2[Int(hash(key + ":find2") % UInt64(pool2.count))]
            let had2 = f.trip.album[x.id] ?? 0
            f.trip.album[x.id] = had2 + 1
            r.extra = x.id
            r.extraTier = tier2
            r.extraNew = had2 == 0
            if had2 > 0, cfg.repeatCoins > 0 {
                f.econ.wallet.coins += cfg.repeatCoins
                r.coins += cfg.repeatCoins
            }
        }

        ScrapSinks.grantFinds(&f, now: back)   // волна 35 L: очень редкая находка — ещё и вещь в коллекции
        // Полный набор — один раз на место.
        if !f.trip.sets.contains(p.id), p.finds.allSatisfy({ (f.trip.album[$0.id] ?? 0) > 0 }) {
            f.trip.sets.append(p.id)
            r.setShards = cfg.setShards
            pay(&f, setReason, cfg.setShards, now: now)
        }
        // Случайный клочок: один на поход.
        if Int(hash(key + ":shard") % 100) < cfg.shardChancePct {
            r.shards = 1
            pay(&f, shardReason, 1, now: now)
        }

        switch ev.effect {
        case .none, .well:
            break
        case .need(let need, let add):
            f.pet.needs[need] = min(100, max(0, (f.pet.needs[need] ?? 0) + add))
        case .ticket:
            let week = Shards.week(DayKey.of(back))
            if week > f.trip.ticketWeek {   // неделя назад (перелёт на запад) второй жетон не даёт
                f.trip.ticketWeek = week
                f.econ.wallet.tickets += 1
                r.ticket = true
            } else if let s = ev.spent {
                r.note = s
            }
        case .photo:
            r.photo = true
        case .forecast:
            r.note = r.note.replacingOccurrences(of: "{forecast}", with: forecast(f, day: day + 1, cfg))
        }

        let first = (f.trip.visits[p.id] ?? 0) == 0
        f.trip.visits[p.id, default: 0] += 1
        r.xp = cfg.xpTrip + (first ? cfg.xpFirst : 0)
        f.trip.xp += r.xp
        f.trip.last = r
        f.log("place.back", t: back, key: p.id, value: r.xp)
        // Опыт пса начисляет DogLevel: за возвращение — ev.back_home (поход идёт поверх прогулки), за первый раз — trip.first.
        if first { f.log("trip.first", t: back, key: p.id) }
        return r
    }

    /// Прогноз на сутки day: погоды в приложении нет — слово по хешу.
    static func forecast(_ f: SaveFile, day: Int, _ cfg: PlacesConfig = .shared) -> String {
        guard !cfg.forecasts.isEmpty else { return "ясно" }
        return cfg.forecasts[Int(hash("\(f.petId):forecast:\(day)") % UInt64(cfg.forecasts.count))]
    }

    /// Клочки — как у остальных источников: кошелёк, shardLog.earned и last (тост «+1 ✂️ …»).
    private static func pay(_ f: inout SaveFile, _ reason: String, _ n: Int, now: Double) {
        guard n > 0 else { return }
        f.econ.wallet.shards += n
        f.shardLog.earned += n
        f.shardLog.last = ShardGain(reason: reason, shards: n, t: now)
    }

    // MARK: Колодец

    static func canWish(_ f: SaveFile, dogLevel: Int, now: Double, _ cfg: PlacesConfig = .shared) -> Bool {
        wishRefusal(f, dogLevel: dogLevel, now: now, cfg) == nil
    }

    static func wishRefusal(_ f: SaveFile, dogLevel: Int, now: Double, _ cfg: PlacesConfig = .shared) -> PlaceRefusal? {
        guard let w = cfg.place(cfg.wellPlace) else { return .unknown }
        if !isOpen(w, dogLevel: dogLevel) { return .locked(level: w.level) }
        if !f.pet.alive { return .dead }
        // Сутки назад не откатываются (DayKey): перелёт на запад второй монетки в те же сутки не даёт.
        if f.trip.wellDay >= DayKey.of(now) { return .notToday }
        if f.econ.wallet.coins < cfg.wellCoins { return .notEnough(need: cfg.wellCoins - f.econ.wallet.coins) }
        return nil
    }

    /// «Бросить монетку»: раз в местные сутки, монеты списываются всегда, клочок — по хешу суток.
    static func wish(_ f: inout SaveFile, dogLevel: Int, now: Double,
                     _ cfg: PlacesConfig = .shared) -> Result<WellResult, PlaceRefusal> {
        if let r = wishRefusal(f, dogLevel: dogLevel, now: now, cfg) { return .failure(r) }
        guard Economy.spend(&f, coins: cfg.wellCoins) else { return .failure(.notEnough(need: cfg.wellCoins)) }
        let day = DayKey.of(now)
        f.trip.wellDay = day
        let got = Int(hash("\(f.petId):well:\(day)") % 100) < cfg.wellChancePct ? cfg.wellShards : 0
        pay(&f, wellReason, got, now: now)
        f.log("place.well", t: now, key: cfg.wellPlace, value: got)
        let text = got > 0 ? "Плюх! Со дна блеснул клочок: +\(got) ✂️" : "Плюх! Колодец ответил эхом. Завтра можно ещё."
        return .success(WellResult(coins: cfg.wellCoins, shards: got, text: text))
    }

    static func performWish(dogLevel: Int, store: PetStore = .shared,
                            now: Double = Clock.now()) throws -> Result<WellResult, PlaceRefusal> {
        try store.mutate { f in wish(&f, dogLevel: dogLevel, now: now) }
    }

    // MARK: Альбом и карта

    /// Сколько разных находок места уже есть.
    static func have(_ f: SaveFile, _ p: Place) -> Int {
        p.finds.filter { (f.trip.album[$0.id] ?? 0) > 0 }.count
    }

    static func find(_ id: String, _ cfg: PlacesConfig = .shared) -> PlaceFind? {
        for p in cfg.places { if let x = p.finds.first(where: { $0.id == id }) { return x } }
        return nil
    }

    /// Карточки всех мест по порядку карты.
    static func cards(_ f: SaveFile, dogLevel: Int, growthX: Double = 1, now: Double,
                      _ cfg: PlacesConfig = .shared) -> [PlaceCard] {
        let star = placeOfDay(f, dogLevel: dogLevel, now: now, cfg)
        return cfg.places.map { p in
            let open = isOpen(p, dogLevel: dogLevel)
            let have = Self.have(f, p)
            let line = !open ? lockText(p) : (have >= p.finds.count ? "Всё найдено" : "Находки \(have) из \(p.finds.count)")
            return PlaceCard(id: p.id, name: p.name, emoji: p.emoji, about: p.about, open: open, star: star == p.id,
                             minutes: minutes(p, growthX: growthX, dogLevel: dogLevel, cfg), have: have,
                             total: p.finds.count, visits: f.trip.visits[p.id] ?? 0, line: line)
        }
    }

    // MARK: Экран карты (волна 34)

    /// Поход, который идёт на самом деле: прогулка ядра, досчитанная до now, — та же, к которой он привязан.
    /// Сейв в сторе догоняется только при записи, поэтому смотрим через peek, а не f.pet.outing.
    static func walking(_ f: SaveFile, now: Double) -> ActiveTrip? {
        guard let a = f.trip.active, let out = PetRunner.peek(f, at: now).outing, out.from == a.from else { return nil }
        return a
    }

    /// Почему «Пойти» сейчас нельзя — текстом для кнопки; nil — можно. Сначала место (закрыто, уже в походе),
    /// потом ядро прогулки (WalkPlan.gate: голодный, спит, поздно…). Уже гуляет просто так — поход пойдёт поверх.
    static func goBlock(_ id: String, _ f: SaveFile, dogLevel: Int, now: Double,
                        _ cfg: PlacesConfig = .shared) -> String? {
        var g = f
        PetRunner.catchUp(&g, now: now)
        if let r = check(id, g, dogLevel: dogLevel, cfg) { return refusalText(r) }
        if g.pet.outing != nil { return nil }
        let gate = WalkPlan.gate(g, at: now)
        return gate.ok ? nil : gate.toast
    }

    /// Где точка пса на тропе: 0 — двор, 1 — место. Первую половину похода идёт туда, вторую — обратно.
    static func trail(_ a: ActiveTrip, now: Double) -> Double {
        let p = min(1, max(0, (now - a.start) / max(1, a.until - a.start)))
        return p < 0.5 ? p * 2 : (1 - p) * 2
    }

    /// «вернётся в 14:20» / «вот-вот вернётся».
    static func backText(_ a: ActiveTrip, tzOffsetMin: Int, now: Double) -> String {
        a.until <= now ? "вот-вот вернётся" : "вернётся в \(Finds.clock(a.until, tzOffsetMin: tzOffsetMin))"
    }

    /// Записка на месте пса во время похода: «Ушёл на 🗼 Маяк, вернусь в 14:20».
    static func awayNote(_ a: ActiveTrip, tzOffsetMin: Int, now: Double, _ cfg: PlacesConfig = .shared) -> String {
        let to = cfg.place(a.place).map { "\($0.emoji) \($0.name)" } ?? a.place
        if a.until <= now { return "Ушёл: \(to), вот-вот вернусь" }
        return "Ушёл: \(to), вернусь в \(Finds.clock(a.until, tzOffsetMin: tzOffsetMin))"
    }

    /// Две карточки «Пока тебя не было»: что принёс с места и что там было.
    static func awayLines(_ r: TripResult, _ cfg: PlacesConfig = .shared) -> [String] {
        let p = cfg.place(r.place)
        let to = p.map { "\($0.emoji) \($0.name)" } ?? r.place
        var got = find(r.find, cfg).map { "\($0.emoji) \($0.name)" } ?? r.find
        if let id = r.extra, let x = find(id, cfg) { got += " и \(x.emoji) \(x.name)" }
        let fresh = r.isNew || r.extraNew == true
        return ["Сходил: \(to). Принёс \(got)" + (fresh ? " — новое в альбоме." : "."), r.note]
    }

    /// Строка «Мест» в альбоме: находки места по порядку — сколько раз приносил (0 — ещё нет).
    static func albumRow(_ f: SaveFile, _ p: Place) -> [(find: PlaceFind, count: Int)] {
        let order: [FindTier] = [.common, .rare, .veryRare]
        return order.flatMap { p.finds($0) }.map { ($0, f.trip.album[$0.id] ?? 0) }
    }

    // MARK: Тексты

    static func lockText(_ p: Place) -> String { "Откроется на \(p.level) уровне" }

    /// «30 мин», «1 ч», «1 ч 45 мин».
    static func durationText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) мин" }
        return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
    }

    /// Записка после похода: место, событие, находка, награды — по строке.
    static func noteLines(_ r: TripResult, _ cfg: PlacesConfig = .shared) -> [String] {
        let p = cfg.place(r.place)
        var out = [(r.star ? "★ " : "") + (p?.name ?? r.place), r.note]
        if let x = find(r.find, cfg) {
            out.append("Принёс: " + findLine(x, r.tier, isNew: r.isNew, cfg))
        }
        if let id = r.extra, let x = find(id, cfg) {
            out.append("И ещё: " + findLine(x, r.extraTier ?? x.tier, isNew: r.extraNew ?? false, cfg))
        }
        if r.setShards > 0 { out.append("Весь набор места собран: +\(r.setShards) ✂️") }
        if r.shards > 0 { out.append("В шерсти застрял клочок: +\(r.shards) ✂️") }
        return out
    }

    /// «🔦 Фонарик (редкая) — новое в альбоме» / «🔦 Фонарик — такое уже есть, +5 🪙».
    static func findLine(_ x: PlaceFind, _ tier: FindTier, isNew: Bool, _ cfg: PlacesConfig = .shared) -> String {
        let rare = tier == .common ? "" : " (\(tier.title))"
        if isNew { return "\(x.emoji) \(x.name)\(rare) — новое в альбоме" + (ScrapSinks.item(forFind: x.id) != nil ? " и в коллекции" : "") }
        return "\(x.emoji) \(x.name) — такое уже есть" + (cfg.repeatCoins > 0 ? ", +\(cfg.repeatCoins) 🪙" : "")
    }

    static func noteText(_ r: TripResult, _ cfg: PlacesConfig = .shared) -> String {
        noteLines(r, cfg).joined(separator: "\n")
    }

    /// Подпись ✂️ — её спрашивает Shards.reasonText.
    static func reasonText(_ reason: String) -> String? {
        switch reason {
        case shardReason: return "нашёлся в походе"
        case setReason: return "за полный набор места"
        case wellReason: return "из колодца"
        default: return nil
        }
    }

    static func refusalText(_ r: PlaceRefusal) -> String {
        switch r {
        case .unknown: return "Такого места нет на карте"
        case .locked(let level): return "Откроется на \(level) уровне"
        case .noOuting: return "Сначала пусть выйдет гулять"
        case .busy: return "Уже в походе"
        case .dead: return "Пса нет дома"
        case .walk(let reason): return WalkRefusal.text(reason)
        case .notToday: return "Сегодня монетку уже бросали"
        case .notEnough(let need): return "Не хватает \(need) 🪙"
        }
    }
}

/// Короткие слова отказа прогулки ядра — для кнопки места.
enum WalkRefusal {
    static func text(_ reason: String) -> String {
        switch reason {
        case "asleep": return "Спит — пусть выспится"
        case "bathing": return "Сейчас в ванне"
        case "unwell": return "Сначала помоги ему"
        case "not_ready": return "Не готов: поесть, помыться, отдохнуть"
        case "too_late": return "Поздно: скоро ночь"
        case "away": return "Уже гуляет"
        case "dead": return "Пса нет дома"
        default: return "Сейчас не получится"
        }
    }
}
