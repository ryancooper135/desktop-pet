// Две подсказки: «Правила» (как умирает щенок) и «Виджет и остров».
// Здесь только решения «показать или нет» и текст правил — без UI, всё проверяется в GuideTests.
// Цифры в тексте берутся из Catalog.rules и economy.json, а не пишутся руками.

import Foundation
@preconcurrency import PetCore

/// Какую подсказку показать. Identifiable — для .sheet(item:).
enum GuideKind: String, Identifiable, Hashable, Sendable {
    case rules, widget
    var id: String { rawValue }
}

/// Строчка экрана правил: иконка SF Symbols, заголовок, текст.
struct RuleItem: Identifiable, Hashable, Sendable {
    let id: String
    let icon: String
    let title: String
    let text: String
}

enum Guides {
    // MARK: настройки (вкус — за Вадимом)

    /// Правила показываем на этот день жизни (1 — день, когда щенок появился)…
    static let rulesDay = 3
    /// …или раньше: при первом уровне не ниже этого (2 — «Плохо»).
    static let rulesLevel = 2
    /// Гайд «виджет и остров»: не больше стольких показов…
    static let widgetMaxShows = 2
    /// …и повтор не раньше, чем через столько секунд.
    static let widgetRepeatS: Double = 7 * 86_400
    /// Пауза после удачной кормёжки: сначала пусть доиграет реакция на еду.
    static let widgetDelayS: Double = 3
    /// Прогноз «если совсем забыть»: шкалы ухода на этом уровне, старт — подъём хозяина.
    static let ignoreStartNeed: Double = 80
    /// Названия бед на экране правил.
    static let distressTitles: [Distress: String] = [.starve: "Голод", .dirty: "Грязь", .toska: "Тоска"]
    static let distressIcons: [Distress: String] = [.starve: "fork.knife", .dirty: "drop.fill", .toska: "cloud.rain.fill"]
    /// Копия WATCH из ядра (там internal): от этих шкал зависит, растут ли сердечки.
    static let watched: [Need] = [.food, .clean, .fun, .love]

    // MARK: когда показывать

    /// Местный календарный день (номер с эпохи) — так же, как в ядре: минуты UTC + смещение пояса.
    static func localDay(_ t: Double, tzOffsetMin: Int) -> Int {
        let m = (t / 60).rounded(.down) + Double(tzOffsetMin)
        return Int((m / 1440).rounded(.down))
    }

    /// День жизни: 1 — день появления, 2 — следующий календарный день и т. д.
    static func dayOfLife(createdT: Double, now: Double, tzOffsetMin: Int) -> Int {
        localDay(now, tzOffsetMin: tzOffsetMin) - localDay(createdT, tzOffsetMin: tzOffsetMin) + 1
    }

    static func shouldShowRules(flags: SaveFile.Flags, createdT: Double, now: Double, tzOffsetMin: Int,
                                level: Int, alive: Bool) -> Bool {
        guard alive, !flags.rulesShown else { return false }
        if level >= rulesLevel { return true }
        return dayOfLife(createdT: createdT, now: now, tzOffsetMin: tzOffsetMin) >= rulesDay
    }

    /// Вызывается после удачной кормёжки. hasWidget — стоит ли хоть один виджет, islandOn — остров включён и разрешён.
    static func shouldShowWidgetGuide(flags: SaveFile.Flags, now: Double, alive: Bool,
                                      hasWidget: Bool, islandOn: Bool) -> Bool {
        guard alive, flags.widgetHintCount < widgetMaxShows else { return false }
        if hasWidget && islandOn { return false }
        if let last = flags.widgetHintT, now - last < widgetRepeatS { return false }
        return true
    }

    // MARK: текст правил

    /// economy.json целиком: условия бед («food == 0») и death.permanent ядро наружу не отдаёт.
    nonisolated(unsafe) static let economy: JSONValue? = {
        guard let data = Catalog.resource("economy", "json") else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }()

    static func rulesItems(name: String, owner: Owner) -> [RuleItem] {
        rulesItems(Catalog.rules, economy: economy, name: name, owner: owner)
    }

    static func rulesItems(_ r: Rules, economy e: JSONValue?, name: String, owner: Owner) -> [RuleItem] {
        var out: [RuleItem] = []
        let maxH = Int(r.heartsMax.rounded())
        out.append(RuleItem(id: "hearts", icon: "heart.fill", title: "\(maxH) \(plural(maxH, "сердечко", "сердечка", "сердечек"))",
                            text: "Это его жизнь. Пока есть хоть одно — \(name) с тобой."))

        for d in Distress.allCases {
            guard let rule = r.distress[d] else { continue }
            let when = e?["care"]["hearts"]["distress"][d.rawValue]["when"].string.map(condText) ?? d.rawValue
            out.append(RuleItem(id: "distress.\(d.rawValue)", icon: distressIcons[d] ?? "exclamationmark.circle",
                                title: distressTitles[d] ?? d.rawValue,
                                text: "Если \(when), через \(hours(rule.graceH)) начнут уходить сердечки: по одному за \(hours(rule.hoursPerHeart))."))
        }
        out.append(RuleItem(id: "stack", icon: "plus.circle.fill", title: "Беды складываются",
                            text: "Если бед несколько сразу, сердечки уходят быстрее."))

        out.append(RuleItem(id: "night", icon: "moon.fill", title: "Ночью не страшно",
                            text: "Пока ты спишь (\(hm(owner.bedMin))–\(hm(owner.wakeMin))), сердечки не уходят и беды не копятся. Считаются только часы, когда ты не спишь."))

        let deathWord = (e?["death"]["permanent"].bool ?? true) ? "Это навсегда — вернуть его будет нельзя." : "Потом его можно будет вернуть."
        out.append(RuleItem(id: "last", icon: "heart.slash.fill", title: "Последнее сердечко",
                            text: "Ниже одного сердечки не падают. Дальше идёт последний шанс: \(hours(r.lastChanceH)) твоего бодрствования, пока \(name) в беде. Не помог — \(name) умрёт. \(deathWord) В первые \(hours(r.noDeathAfterWakeH)) после твоего подъёма этого не случится."))

        if let h = ignoreDeathH(r, owner: owner) {
            out.append(RuleItem(id: "ignore", icon: "hourglass", title: "Если совсем забыть",
                                text: "Без ухода совсем \(name) продержится \(roughly(h)). Пара заходов в день — и всё хорошо."))
        }

        let names = joinRu(watched.map { Catalog.needName($0).lowercased() })
        var regen = "Сердечки возвращаются сами — одно примерно за \(hours(1 / max(r.regenPerH, 0.0001))), если \(names) не ниже \(num(r.regenAllGe)) и бед нет."
        if r.regenNightX <= 0 { regen += " Ночью не растут." }
        else if abs(r.regenNightX - 0.5) < 0.01 { regen += " Ночью вдвое медленнее." }
        else if r.regenNightX < 1 { regen += " Ночью медленнее." }
        out.append(RuleItem(id: "regen", icon: "arrow.clockwise.heart.fill", title: "Сердечки растут", text: regen))

        var help = "Когда ему плохо, жми «Спасти» — там самое срочное."
        if let item = r.items[Catalog.healItem], case .number(let plus)? = item["hearts"] {
            var line = "\(Catalog.name(Catalog.healItem)) даёт +\(num(plus)) \(plus == 1 ? "сердечко" : "сердечка")"
            if case .number(let cd)? = item["cooldown_h"] { line += ", не чаще раза в \(hours(cd))" }
            help = line + ". " + help
        }
        out.append(RuleItem(id: "help", icon: "cross.case.fill", title: "Как помочь", text: help))
        return out
    }

    /// Сколько часов проживёт щенок без ухода: шкалы ухода на ignoreStartNeed, старт — подъём хозяина.
    static func ignoreDeathH(_ r: Rules, owner: Owner, horizonH: Double = 168) -> Double? {
        let day = 20_000.0 * 86_400
        let t0 = day - Double(owner.tzOffsetMin * 60) + Double(owner.wakeMin * 60)
        var s = PetEngine.newPet(r, t: t0)
        for n in watched { s.needs[n] = ignoreStartNeed }
        guard let death = PetEngine.forecast(s, r, owner, horizonH: horizonH).first(where: { $0.kind == .death }) else { return nil }
        return (death.t - t0) / 3600
    }

    // MARK: формат

    /// «food == 0» → «сытость на нуле», «fun < 10 && love < 10» → «настроение ниже 10 и ласка ниже 10».
    static func condText(_ expr: String) -> String {
        expr.components(separatedBy: "||").map { or in
            or.components(separatedBy: "&&").map { atomText($0.trimmingCharacters(in: .whitespaces)) }.joined(separator: " и ")
        }.joined(separator: " или ")
    }

    private static func atomText(_ a: String) -> String {
        for op in ["<=", ">=", "==", "!=", "<", ">"] {
            guard let range = a.range(of: op) else { continue }
            let left = a[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let right = a[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let what = Need(rawValue: left).map { Catalog.needName($0).lowercased() } ?? left
            let v = Double(right).map(num) ?? right
            switch op {
            case "==": return right == "0" ? "\(what) на нуле" : "\(what) ровно \(v)"
            case "!=": return "\(what) не \(v)"
            case "<": return "\(what) ниже \(v)"
            case "<=": return "\(what) не выше \(v)"
            case ">": return "\(what) выше \(v)"
            default: return "\(what) не ниже \(v)"
            }
        }
        return a
    }

    /// 2 → «2», 0.5 → «0,5».
    static func num(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        if r == r.rounded() { return String(Int(r)) }
        return String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
    }

    static func hours(_ h: Double) -> String { "\(num(h)) ч" }

    /// 59.3 → «около 2,5 суток», 20 → «около 20 ч».
    static func roughly(_ h: Double) -> String {
        if h < 36 { return "около \(Int(h.rounded())) ч" }
        return "около \(num((h / 24 * 2).rounded() / 2)) суток"
    }

    static func hm(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        EconText.plural(n, one, few, many)
    }

    /// [a, b, c] → «a, b и c».
    static func joinRu(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " и " + parts[parts.count - 1]
    }
}
