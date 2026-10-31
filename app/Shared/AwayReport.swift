// «Пока тебя не было»: отчёт при входе в приложение (AwayReport) и его сборка из seen и событий (AwayBuilder).
// Волна 28: перенесено из AppModel.swift. Волна 52: «2.0» — переехало в Shared (чистая логика, тесты на Linux),
// лента из трёх блоков: что делал пёс (моменты), что накопилось (копилка двора одной кнопкой «Забрать всё»),
// что изменилось (погода, сезон, уровень, достижения) и одна подсказка «что сделать сейчас» с наградой.
// Здесь нет SwiftUI: Shared собирается и в виджет. Экран — App/Screens.swift (AwayScreen).

import Foundation
@preconcurrency import PetCore

// MARK: - «Пока тебя не было»

struct AwayReport: Identifiable, Sendable {
    /// Карточка-момент или чип перемены. title — коротко и без рода (свой персонаж: род имени не знаем),
    /// text — фраза из lines.json (голос пса) или пояснение для VoiceOver. tone — цвет плашки иконки на экране.
    struct Card: Identifiable, Hashable, Sendable {
        let id: String
        let icon: String
        let title: String
        let text: String
        let tone: Tone

        init(id: String, icon: String, title: String = "", text: String, tone: Tone = .vio) {
            self.id = id
            self.icon = icon
            self.title = title
            self.text = text
            self.tone = tone
        }
    }

    /// Цвета иконок макета волны 52 (design/wave52): еда, ласка, игра, мытьё, золото, ночь, фиолетовый.
    enum Tone: String, Hashable, Sendable {
        case food, love, play, wash, gold, night, vio
    }

    /// Одна подсказка «что сделать сейчас». action == nil — кнопка просто закрывает отчёт.
    struct Hint: Hashable, Sendable {
        /// sick / ask / need / task — откуда подсказка (для тестов и порядка).
        let kind: String
        let icon: String
        let tone: Tone
        /// «Сейчас», «Просьба», «Задание дня».
        let label: String
        let title: String
        let button: String
        /// «+6 🪙» или пусто, если за это сегодня уже ничего не дадут.
        let reward: String
        let action: PetAction?
    }

    let id: String
    let greet: String
    let subtitle: String
    /// Что делал пёс: не больше AwayBuilder.maxMiddle.
    let cards: [Card]
    /// Что накопилось во дворе к моменту входа (Yard.collect на копии сейва). nil — двор пуст или его нет.
    let stash: YardHarvest?
    /// Что изменилось: не больше AwayBuilder.maxChanges.
    let changes: [Card]
    let hint: Hint?
    let cta: String
    let died: Bool

    init(id: String, greet: String, subtitle: String, cards: [Card], stash: YardHarvest? = nil,
         changes: [Card] = [], hint: Hint? = nil, cta: String, died: Bool) {
        self.id = id
        self.greet = greet
        self.subtitle = subtitle
        self.cards = cards
        self.stash = stash
        self.changes = changes
        self.hint = hint
        self.cta = cta
        self.died = died
    }

    /// Строки блока «Накопилось» под суммой: «Кладовая: 3 порции», «Билетик», «Чаевые +5».
    var stashChips: [String] { stash.map(AwayBuilder.stashChips) ?? [] }
}

/// Сборка отчёта. Чистая функция от сейва и времени: всё, что пишет, — только в копию.
enum AwayBuilder {
    static let minAwayH = 0.5
    /// Моментов «что делал пёс» — не больше трёх (волна 52: «2–3 карточки-момента, без стены текста»).
    static let maxMiddle = 3
    static let maxChanges = 4

    /// Погода и сезон в момент t. По умолчанию — то, что видно в комнате (Weather.shown / Seasons.shown:
    /// под тестами ясно и осень, значит перемен нет). Тесты подставляют свои.
    typealias WeatherAt = @Sendable (Double) -> WeatherKind
    typealias SeasonAt = @Sendable (Double) -> Season

    static let shownWeather: WeatherAt = { Weather.shown(at: $0, tzOffsetMin: Clock.tzOffsetMin(at: $0)) }
    static let shownSeason: SeasonAt = { Seasons.shown(at: $0, tzOffsetMin: Clock.tzOffsetMin(at: $0)) }

    static func make(_ f: SaveFile, prev: PetState, now: Double,
                     weatherAt: WeatherAt = shownWeather, seasonAt: SeasonAt = shownSeason) -> AwayReport? {
        guard prev.alive, now > prev.t else { return nil }
        let r = ItemPerks.rules(f)
        let o = PetRunner.owner(f, at: now)
        let s = PetEngine.awaySummary(prev, r, o, now: now, journal: f.timedActs(from: prev.t, to: now))
        let notable = s.events.contains { $0.kind != "sleep" && $0.kind != "wake" }
        guard s.awayH >= minAwayH, s.show || notable || s.died else { return nil }

        let lines = Lines.shared
        let seed = f.petId
        let slot = Int(now / 3600)
        var cards: [AwayReport.Card] = []
        func add(_ key: String, _ icon: String, _ title: String, _ tone: AwayReport.Tone,
                 _ vars: [String: String] = [:]) {
            guard cards.count < maxMiddle, !cards.contains(where: { $0.id == key }),
                  let text = lines.away(key, seed: seed, slot: slot, vars: vars) else { return }
            cards.append(AwayReport.Card(id: key, icon: icon, title: title, text: text, tone: tone))
        }

        if s.died {
            let cause = s.events.last(where: { $0.kind == "death" })?.key
            cards.append(AwayReport.Card(id: "death", icon: "heart.slash", title: "Беда",
                                         text: deathText(cause, name: f.petName), tone: .love))
            // Волна 32: убежал, но ещё можно найти — так и говорим, а не «больше нет».
            if let st = Runaway.status(f, at: now), st.canReturn {
                return AwayReport(id: "away-\(Int(now))", greet: Runaway.title(f.petName, st),
                                  subtitle: subtitle(s.awayH), cards: cards,
                                  cta: "Его ещё можно найти — поиски на главном экране.", died: true)
            }
            return AwayReport(id: "away-\(Int(now))", greet: PetNames.gone(f.petName),
                              subtitle: subtitle(s.awayH), cards: cards,
                              cta: "Можно начать заново с новым щенком.", died: true)
        }

        // Волна 34 H: вернулся из похода — что принёс с места и что там было.
        if let t = f.trip.last, t.t > prev.t {
            for (i, text) in Places.awayLines(t).enumerated() where cards.count < maxMiddle {
                cards.append(AwayReport.Card(id: "place\(i)", icon: i == 0 ? "map.fill" : "sparkles",
                                             title: i == 0 ? "Поход" : "Что там было", text: text,
                                             tone: i == 0 ? .play : .gold))
            }
        }
        // Сходил погулять: находка уже в альбоме — первой карточкой, это самое приятное.
        if let b = s.events.last(where: { $0.kind == "back_home" }) {
            add("back_home", "figure.walk", "Прогулка", .play, ["item": Finds.name(b.key ?? "")])
        }
        // Кухня с автокормушкой выручила, пока никого не было.
        if s.events.contains(where: { $0.kind == "autofeed" }) {
            add("autofed", "fork.knife", "Кормушка выручила", .food)
        }
        if s.sleptH >= 3 {
            add("slept", "moon.zzz.fill", "Сон · \(Int(s.sleptH.rounded())) ч", .night)
        } else if s.events.contains(where: { $0.kind == "nap" }) {
            add("nap", "moon.fill", "Дрёма", .night)
        }
        if s.events.contains(where: { $0.kind == "heart" }) {
            add("heart_lost", "heart.slash.fill", "Минус сердечко", .love)
        }
        let mood = PetEngine.mood(s.state, r, o, now: now)
        let lonely = s.events.contains { ($0.kind == "distress" && $0.key == "toska") || ($0.kind == "low" && $0.key == "love") }
        if mood == .sulky {
            add("sulked", "cloud.fill", "Обида", .wash)
        } else if lonely {
            add("missed", "heart.fill", "Тоска по тебе", .love)
        }

        let steps = f.journal.filter { $0.kind == "act.steps" && $0.ok == true && $0.t > prev.t && $0.t <= now }
            .reduce(0) { $0 + ($1.value ?? 0) }
        if steps > 0 { add("steps", "shoeprints.fill", "Шаги вместе", .play, ["steps": "\(steps)"]) }

        let remote = f.journal.filter {
            $0.kind.hasPrefix("act.") && $0.ok == true && $0.t > prev.t && $0.t <= now
                && $0.source != nil && $0.source != .app && $0.source != .steps
        }.count
        if remote > 0, cards.count < maxMiddle {
            cards.append(AwayReport.Card(id: "remote", icon: "hand.wave.fill", title: "Забота издалека",
                                         text: "Ты заботился издалека: \(remote) \(times(remote)). Я заметил.",
                                         tone: .vio))
        }

        // Одна история «сам по себе»: стабильно по petId и часу, но с оглядкой на шкалы.
        let fun = s.state.needs[.fun] ?? 100
        let love = s.state.needs[.love] ?? 100
        let own: String
        if fun < 30 {
            own = "played_alone"
        } else if love < 30 {
            own = "waited_door"
        } else {
            let pool = ["chased_fly", "waited_door", "played_alone", "zoomies"]
            own = pool[Int(StableHash.fnv1a("\(seed):own:\(slot)") % UInt64(pool.count))]
        }
        let story = ownStory(own)
        add(own, story.icon, story.title, story.tone)

        if cards.isEmpty { add("nothing", "leaf.fill", "Тихо и спокойно", .play) }

        let greet = lines.away(s.greet ?? "welcome", seed: seed, slot: slot) ?? "Ты вернулся!"
        let cta = lines.away(s.cta ?? "cta_ok", seed: seed, slot: slot) ?? "Я тут. Загляни ко мне."
        return AwayReport(id: "away-\(Int(now))", greet: greet, subtitle: subtitle(s.awayH), cards: cards,
                          stash: stash(f, now: now),
                          changes: changes(f, from: prev.t, to: now, weatherAt: weatherAt, seasonAt: seasonAt),
                          hint: hint(f, now: now), cta: cta, died: false)
    }

    /// Иконка, заголовок и цвет истории «сам по себе».
    static func ownStory(_ key: String) -> (icon: String, title: String, tone: AwayReport.Tone) {
        switch key {
        case "played_alone": return ("tennisball.fill", "Мячик сам с собой", .play)
        case "waited_door": return ("door.left.hand.open", "У двери", .love)
        case "chased_fly": return ("ladybug.fill", "Охота на муху", .food)
        case "zoomies": return ("hare.fill", "Бег по кругу", .gold)
        default: return ("pawprint.fill", "Сам по себе", .vio)
        }
    }

    // MARK: Что накопилось

    /// Что даст «Забрать всё» прямо сейчас — тот же Yard.collect, но на копии сейва. Пусто — nil.
    static func stash(_ f: SaveFile, now: Double) -> YardHarvest? {
        var g = f
        let h = Yard.collect(in: &g, now: now, dogLevel: DogLevel.level(f))
        return h.isEmpty ? nil : h
    }

    /// «Забрать всё»: ровно то же, что ручной сбор во дворе (AppModel.collectYard → yardWrite): Yard.collect
    /// и награды записи (задание дня «Собрать копилку», достижения). Своей логики начисления здесь нет.
    @discardableResult
    static func collectAll(in f: inout SaveFile, now: Double) -> YardHarvest {
        let h = Yard.collect(in: &f, now: now, dogLevel: DogLevel.level(f))
        PetRunner.settleRewards(&f, now: now)
        return h
    }

    /// Чипы под суммой: кладовая, билетик, чаевые, гостинец соседей.
    static func stashChips(_ h: YardHarvest) -> [String] {
        var out: [String] = []
        let portions = h.portions.values.reduce(0, +)
        if portions > 0 { out.append("Кладовая: \(portions) \(EconText.plural(portions, "порция", "порции", "порций"))") }
        if h.tickets > 0 { out.append(h.tickets == 1 ? "Билетик" : "Билетики ×\(h.tickets)") }
        switch h.tip {
        case .bonus where h.bonus > 0: out.append("Чаевые +\(h.bonus)")
        case .ingredient: out.append("Гостинец соседей")
        default: break
        }
        return out
    }

    // MARK: Что изменилось

    static func changes(_ f: SaveFile, from t0: Double, to t1: Double,
                        weatherAt: WeatherAt = shownWeather, seasonAt: SeasonAt = shownSeason) -> [AwayReport.Card] {
        var out: [AwayReport.Card] = []
        let s0 = seasonAt(t0), s1 = seasonAt(t1)
        if s0 != s1 {
            let c = seasonCard(s1)
            out.append(AwayReport.Card(id: "season", icon: c.icon, title: c.title, text: c.title, tone: c.tone))
        }
        let w0 = weatherAt(t0), w1 = weatherAt(t1)
        if w0 != w1 {
            let c = weatherCard(w1, was: w0)
            out.append(AwayReport.Card(id: "weather", icon: c.icon, title: c.title, text: c.title, tone: .wash))
        }
        if let up = f.level.lastUp, up.t > t0, up.t <= t1 {
            let reward = up.coins > 0 ? ": +\(up.coins) 🪙" : ""
            out.append(AwayReport.Card(id: "level", icon: "arrow.up.circle.fill", title: "Уровень \(up.level)",
                                       text: "Новый уровень \(up.level)\(reward)", tone: .vio))
        }
        let got = f.shardLog.achT.filter { $0.value > t0 && $0.value <= t1 }.sorted { ($0.value, $0.key) < ($1.value, $1.key) }
        for (id, _) in got {
            guard let a = Achievements.item(id) else { continue }
            out.append(AwayReport.Card(id: "ach.\(id)", icon: "trophy.fill", title: "«\(a.title)»",
                                       text: "Достижение «\(a.title)»", tone: .gold))
        }
        return Array(out.prefix(maxChanges))
    }

    static func seasonCard(_ s: Season) -> (icon: String, title: String, tone: AwayReport.Tone) {
        switch s {
        case .winter: return ("snowflake", "Наступила зима", .wash)
        case .spring: return ("camera.macro", "Наступила весна", .play)
        case .summer: return ("sun.max.fill", "Наступило лето", .gold)
        case .autumn: return ("leaf.fill", "Наступила осень", .food)
        }
    }

    static func weatherCard(_ w: WeatherKind, was: WeatherKind) -> (icon: String, title: String) {
        switch w {
        case .clear: return ("sun.max.fill", was.wet || was == .snow ? "Распогодилось" : "Выглянуло солнце")
        case .cloudy: return ("cloud.fill", "Затянуло тучами")
        case .rain: return ("cloud.rain.fill", "Пошёл дождь")
        case .storm: return ("cloud.bolt.rain.fill", "Гроза")
        case .snow: return ("cloud.snow.fill", "Пошёл снег")
        }
    }

    // MARK: Подсказка

    /// Одна подсказка «что сделать сейчас»: болеет → просьба пса → нужда (PetStatusLogic) → задание дня.
    /// Награда — честная: монеты просьбы, монеты задания или монеты за уход с учётом дневного потолка.
    static func hint(_ f: SaveFile, now: Double) -> AwayReport.Hint? {
        let st = PetStatusLogic.of(f, now: now)
        if st.kind == .sick, let act = st.act, let a = act.action {
            return AwayReport.Hint(kind: "sick", icon: act.icon, tone: .love, label: "Сейчас", title: st.title,
                                   button: act.title, reward: careReward(f, a, now: now), action: a)
        }
        if let ask = DogAsks.shown(f, now: now), let k = ask.kind, let a = askAction(k) {
            return AwayReport.Hint(kind: "ask", icon: icon(k), tone: tone(k), label: "Просьба",
                                   title: DogAskText.line(k), button: DogAskText.button(k),
                                   reward: ask.coins > 0 ? "+\(ask.coins) 🪙" : "", action: a)
        }
        if st.kind == .need, let act = st.act, let a = act.action {
            return AwayReport.Hint(kind: "need", icon: act.icon, tone: tone(a.kind), label: "Сейчас",
                                   title: st.title, button: act.title, reward: careReward(f, a, now: now), action: a)
        }
        let board = DailyTasks.board(f, now: now)
        if let t = board.items.first(where: { !$0.done && askAction($0.id) != nil }), let a = askAction(t.id) {
            return AwayReport.Hint(kind: "task", icon: icon(t.id), tone: tone(t.id), label: "Задание дня",
                                   title: "\(DailyTaskText.name(t)) · \(DailyTaskText.progress(t))",
                                   button: taskButton(t.id), reward: DailyTaskText.reward(t), action: a)
        }
        return nil
    }

    /// Монеты за уход этим действием сегодня: по economy.json, но не выше остатка дневного потолка.
    static func careReward(_ f: SaveFile, _ a: PetAction, now: Double) -> String {
        let n = min(EconomyConfig.shared.careCoins[a.kind] ?? 0, Economy.careLeftToday(f, at: now))
        return n > 0 ? "+\(n) 🪙" : ""
    }

    /// Действие для просьбы пса или задания дня с тем же id. Поход, двор, кухня — не отсюда.
    static func askAction(_ k: String) -> PetAction? {
        switch k {
        case "feed": return .feed(Catalog.mainFood)
        case "bath": return .bath
        case "pet": return .pet
        case "play": return .play
        case "brush": return .brush
        case "walk": return .walk
        default: return nil
        }
    }

    static func taskButton(_ k: String) -> String {
        switch k {
        case "walk": return "Гулять"
        default: return DogAskText.button(k)
        }
    }

    static func icon(_ k: String) -> String {
        switch k {
        case "feed": return "fork.knife"
        case "bath": return "bathtub.fill"
        case "pet": return "hand.raised.fill"
        case "play": return "tennisball.fill"
        case "brush": return "sparkles"
        case "walk": return "figure.walk"
        default: return "star.fill"
        }
    }

    static func tone(_ k: String) -> AwayReport.Tone {
        switch k {
        case "feed": return .food
        case "bath", "wash": return .wash
        case "pet": return .love
        case "play", "walk": return .play
        case "brush": return .gold
        default: return .vio
        }
    }

    // MARK: Тексты

    static func subtitle(_ h: Double) -> String {
        if h < 1 { return "Тебя не было \(Int((h * 60).rounded())) мин" }
        if h < 48 { return "Тебя не было \(Int(h.rounded())) ч" }
        return "Тебя не было \(Int((h / 24).rounded())) дн"
    }

    static func times(_ n: Int) -> String { EconText.plural(n, "раз", "раза", "раз") }

    static func deathText(_ cause: String?, name: String) -> String {
        // Свой персонаж (волна 14): род имени не знаем — фразы без «был» и «дождался».
        if !PetNames.isShiba(name) {
            switch cause {
            case "starve": return "Слишком долго без еды."
            case "dirty": return "Слишком долго без мытья."
            case "toska": return "Слишком долго без тебя — тоска взяла своё."
            default: return "Помощь не успела."
            }
        }
        switch cause {
        case "starve": return "\(name) слишком долго был голодным."
        case "dirty": return "\(name) слишком долго был грязным."
        case "toska": return "\(name) затосковал без тебя."
        default: return "\(name) не дождался."
        }
    }
}
