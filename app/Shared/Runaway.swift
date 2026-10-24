// Волна 32: мягкая смерть — «пёс убежал». Ядро по-прежнему ставит alive = false на последнем сердечке; этот
// модуль решает, можно ли вернуть того же пса (имя, память, вкусы, трюки, вещи — всё его) и чем за это платят.
//
// Как вернуть (любой путь, срок death.comeback.search_h с момента, когда хозяин увидел пустую комнату):
//   • поиски по следам — trails раз, между поисками не меньше trail_gap_h (то есть разные заходы);
//   • шаги — steps шагов после побега (шагомер, как «Шаги» в привычках);
//   • сразу за ✂️ клочки (shards; цену при слиянии взять из общей функции волны 32 D, сейчас — из конфига).
// Цена возвращения: пёс приходит уставший и грязный (back.needs, back.hearts) и часть монет (coins_lost_pct)
// уходит «на объявления о пропаже». Возраст, дом и альбом — как были.
// Без возврата: срок вышел, третий побег за window_days или часы переводили назад после побега —
// тогда только новый щенок (PetStore.startOver). Перевод часов назад не прощается, как и раньше (clock_back).

import Foundation
@preconcurrency import PetCore

struct RunawayConfig: Hashable, Sendable {
    var enabled = true
    var searchH: Double = 72
    var trails = 2
    var trailGapH: Double = 4
    var steps = 3000
    var shards = 30
    /// Сколько возвращений за окно можно; следующий побег — уже насовсем.
    var maxInWindow = 2
    var windowDays: Double = 30
    var backHearts: Double = 2.5
    var backNeeds: [String: Double] = ["food": 40, "clean": 20, "energy": 60, "fun": 30, "love": 30, "walk": 30]
    var coinsLostPct = 20

    static let shared = RunawayConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        let d = e["death"]
        let c = d["comeback"]
        guard !c.object.isEmpty else { return }
        enabled = !(d["permanent"].bool ?? false)
        if let v = c["search_h"].double { searchH = v }
        if let v = c["trails"].double { trails = Int(v) }
        if let v = c["trail_gap_h"].double { trailGapH = v }
        if let v = c["steps"].double { steps = Int(v) }
        if let v = c["shards"].double { shards = Int(v) }
        if let v = c["max_in_window"].double { maxInWindow = Int(v) }
        if let v = c["window_days"].double { windowDays = v }
        if let v = c["back"]["hearts"].double { backHearts = v }
        for (k, v) in c["back"]["needs"].object { if let x = v.double { backNeeds[k] = x } }
        if let v = c["coins_lost_pct"].double { coinsLostPct = Int(v) }
    }
}

enum Runaway {
    /// Поиски одного побега и история возвращений этого пса. Новому щенку не переходит.
    struct Log: Codable, Hashable, Sendable {
        /// Когда хозяин увидел пустую комнату (первая запись после смерти). nil — пёс дома.
        var since: Double?
        /// Моменты поисков по следам.
        var trails: [Double] = []
        /// Шаги, засчитанные после побега.
        var steps = 0
        /// Метка шагомера для поисков: до неё шаги уже засчитаны.
        var stepsT: Double?
        /// Почему вернуть уже нельзя: late, third, clock. nil — можно.
        var lost: String?
        /// Когда пёс возвращался (для «третьего побега за 30 дней»).
        var comebacks: [Double] = []

        var isEmpty: Bool { since == nil && trails.isEmpty && steps == 0 && stepsT == nil && lost == nil && comebacks.isEmpty }
    }

    enum Way: String, Sendable { case trails, steps, shards }

    /// Что показывать в пустой комнате.
    struct Status: Hashable, Sendable {
        var canReturn: Bool
        /// late / third / clock / off, когда вернуть нельзя.
        var lost: String?
        var hoursLeft: Double
        var trails: Int
        var trailsNeed: Int
        /// Можно ли искать по следам прямо сейчас (не чаще раза за заход).
        var trailReady: Bool
        /// Через сколько часов следующий поиск, если сейчас нельзя.
        var trailInH: Double
        var steps: Int
        var stepsNeed: Int
        var shardsCost: Int
        var shardsHave: Int
        /// Нашёлся: условий хватает — осталось нажать «Вернуть домой».
        var found: Bool
    }

    /// Стоимость возвращения в ✂️. При слиянии волны 32 подменить на общую функцию цен D.
    static func shardsCost(_ cfg: RunawayConfig = .shared) -> Int { cfg.shards }

    /// Вызывается при каждой записи (PetRunner.catchUp): пёс умер — заводим поиски, проверяем сроки и часы.
    static func observe(_ f: inout SaveFile, now: Double, _ cfg: RunawayConfig = .shared) {
        guard !f.pet.alive else {
            if f.runaway.since != nil || f.runaway.lost != nil { f.runaway.since = nil; f.runaway.lost = nil; f.runaway.trails = []; f.runaway.steps = 0; f.runaway.stepsT = nil }
            return
        }
        guard cfg.enabled else { return }
        let died = f.pet.diedAt ?? f.pet.t
        if f.runaway.since == nil {
            f.runaway.since = max(now, died)
            f.runaway.stepsT = f.runaway.since
            let recent = f.runaway.comebacks.filter { died - $0 < cfg.windowDays * 86400 && died >= $0 }
            if recent.count >= cfg.maxInWindow { f.runaway.lost = "third" }
        }
        guard f.runaway.lost == nil else { return }
        // Часы назад после побега (или смерть «из будущего») — поиски закрыты насовсем, как clock_back у живого.
        if died - now > 300 || (f.runaway.since ?? now) - now > 300 || (f.runaway.trails.last ?? now) - now > 300 {
            f.runaway.lost = "clock"
            return
        }
        if now - (f.runaway.since ?? now) > cfg.searchH * 3600 && !found(f, cfg) { f.runaway.lost = "late" }
    }

    private static func found(_ f: SaveFile, _ cfg: RunawayConfig) -> Bool {
        f.runaway.trails.count >= cfg.trails || f.runaway.steps >= cfg.steps
    }

    static func status(_ f: SaveFile, at now: Double, _ cfg: RunawayConfig = .shared) -> Status? {
        guard !f.pet.alive else { return nil }
        var g = f
        observe(&g, now: now, cfg)
        let log = g.runaway
        let since = log.since ?? now
        let left = max(0, cfg.searchH - (now - since) / 3600)
        let nextTrail = (log.trails.last.map { $0 + cfg.trailGapH * 3600 } ?? now) - now
        let lost: String? = cfg.enabled ? log.lost : "off"
        return Status(canReturn: lost == nil, lost: lost, hoursLeft: left,
                      trails: min(log.trails.count, cfg.trails), trailsNeed: cfg.trails,
                      trailReady: lost == nil && nextTrail <= 0 && log.trails.count < cfg.trails,
                      trailInH: max(0, nextTrail / 3600),
                      steps: min(log.steps, cfg.steps), stepsNeed: cfg.steps,
                      shardsCost: shardsCost(cfg), shardsHave: g.econ.wallet.shards,
                      found: lost == nil && found(g, cfg))
    }

    enum Outcome: Equatable, Sendable {
        case ok
        /// Пёс нашёлся этим поиском — можно возвращать.
        case found
        case no(String)
    }

    /// «Искать по следам»: один поиск за заход (trail_gap_h).
    @discardableResult
    static func searchTrail(_ f: inout SaveFile, now: Double, _ cfg: RunawayConfig = .shared) -> Outcome {
        observe(&f, now: now, cfg)
        guard let st = status(f, at: now, cfg) else { return .no("alive") }
        guard st.canReturn else { return .no(st.lost ?? "lost") }
        guard st.trails < st.trailsNeed else { return .found }
        guard st.trailReady else { return .no("later") }
        f.runaway.trails.append(now)
        f.log("runaway.trail", t: now, value: f.runaway.trails.count)
        return found(f, cfg) ? .found : .ok
    }

    /// Шаги после побега (AppActions.syncSteps, пока пса нет).
    @discardableResult
    static func addSteps(_ n: Int, _ f: inout SaveFile, now: Double, _ cfg: RunawayConfig = .shared) -> Outcome {
        observe(&f, now: now, cfg)
        guard let st = status(f, at: now, cfg) else { return .no("alive") }
        guard st.canReturn else { return .no(st.lost ?? "lost") }
        let wasFound = st.found
        f.runaway.steps += max(0, n)
        f.runaway.stepsT = now
        if n > 0 { f.log("runaway.steps", t: now, value: n) }
        return !wasFound && found(f, cfg) ? .found : .ok
    }

    /// Окно шагомера для поисков: с прошлой метки. nil — пёс дома или искать уже нельзя.
    static func stepsFrom(_ f: SaveFile, at now: Double, _ cfg: RunawayConfig = .shared) -> Double? {
        guard let st = status(f, at: now, cfg), st.canReturn, !st.found else { return nil }
        let from = f.runaway.stepsT ?? f.runaway.since ?? now
        return now - from >= PetRunner.stepsMinGapS ? from : nil
    }

    /// Вернуть пса домой: найден поисками/шагами или платим клочками.
    static func bringBack(_ f: inout SaveFile, way: Way, now: Double, _ cfg: RunawayConfig = .shared) -> Outcome {
        observe(&f, now: now, cfg)
        guard let st = status(f, at: now, cfg) else { return .no("alive") }
        guard st.canReturn else { return .no(st.lost ?? "lost") }
        switch way {
        case .trails, .steps:
            guard st.found else { return .no("not_found") }
        case .shards:
            guard f.econ.wallet.shards >= st.shardsCost else { return .no("shards") }
            f.econ.wallet.shards -= st.shardsCost
        }
        let lost = coinsLost(f.econ.wallet.coins, cfg)
        f.econ.wallet.coins -= lost
        var p = f.pet
        p.alive = true
        p.diedAt = nil
        p.cause = nil
        p.hearts = cfg.backHearts
        p.lastChanceH = nil
        p.lastHeartLossT = nil
        p.napUntil = nil
        p.bathUntil = nil
        p.outing = nil
        for k in Array(p.grace.keys) { p.grace[k] = 0 }
        for (k, v) in cfg.backNeeds {
            if let n = Need(rawValue: k) { p.needs[n] = v }
        }
        p.t = now
        f.pet = p
        f.runaway.comebacks.append(now)
        f.runaway.since = nil
        f.runaway.trails = []
        f.runaway.steps = 0
        f.runaway.stepsT = nil
        f.runaway.lost = nil
        f.log("runaway.back", t: now, key: way.rawValue, value: lost)
        return .ok
    }

    static func coinsLost(_ coins: Int, _ cfg: RunawayConfig = .shared) -> Int {
        max(0, coins) * cfg.coinsLostPct / 100
    }

    // MARK: тексты

    /// Заголовок пустой комнаты. Без глагола в прошедшем: имя бывает любого рода.
    static func title(_ name: String, _ st: Status) -> String {
        let shiba = PetNames.isShiba(name)
        if !st.canReturn { return st.lost == "third" ? "\(shiba ? PetNames.shiba : name) теперь в новой семье" : PetNames.gone(name) }
        if st.found { return "Нашли! Пора домой" }
        return shiba ? "Шибы нет дома" : "Дома пусто"
    }

    /// Строка под заголовком: что сделать и сколько осталось.
    static func detail(_ st: Status) -> String {
        switch st.lost {
        case "late": return "Поиски не успели. Можно взять нового щенка — дом и вещи останутся."
        case "third": return "Третий побег за месяц. Его приютили добрые люди. Дом и вещи ждут нового щенка."
        case "clock": return "Часы перевели назад — следы потерялись. Можно взять нового щенка."
        case "off": return "Можно взять нового щенка — дом и вещи останутся."
        default: break
        }
        if st.found { return "После возвращения: сил мало, шерсть грязная, часть монет — на объявления о пропаже." }
        return "Тоска выгнала из дома. Найди по следам (\(st.trails) из \(st.trailsNeed)) или пройди \(st.stepsNeed) шагов (\(st.steps)). Осталось \(hoursText(st.hoursLeft))."
    }

    static func hoursText(_ h: Double) -> String {
        let n = Int(h.rounded(.up))
        if n >= 24 {
            let d = Int((h / 24).rounded(.down)), rest = n - d * 24
            return rest > 0 ? "\(d) \(days(d)) \(rest) ч" : "\(d) \(days(d))"
        }
        return "\(max(n, 1)) ч"
    }

    private static func days(_ d: Int) -> String {
        let m10 = d % 10, m100 = d % 100
        if m10 == 1 && m100 != 11 { return "сутки" }
        return "суток"
    }

    /// Тост после поиска или возвращения.
    static func toast(_ o: Outcome, way: Way? = nil) -> String {
        switch o {
        case .found: return "Нашёлся! Веди домой"
        case .ok: return way == nil ? "Следы ведут дальше. Поищем в другой заход" : "Снова дома"
        case .no(let r):
            switch r {
            case "later": return "Сегодня уже искали. Загляни попозже"
            case "shards": return "Не хватает клочков"
            case "not_found": return "Сначала найди по следам или шагами"
            default: return "Вернуть уже нельзя"
            }
        }
    }
}
