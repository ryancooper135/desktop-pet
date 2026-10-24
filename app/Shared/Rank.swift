// Волна 32: «из грязи в князи». Щенок начинает бродяжкой — колтуны, миска и подстилка, 20 монет;
// звание растёт от того, что видно глазами: ступеньки дома (сумма уровней шести линий HomeShop) и шерсть (Coat).
// Дом переживает щенка, поэтому новый щенок в хорошем доме стартует не с нуля; шерсть у каждого своя.
// Числа и названия — economy.json rank. Чистая функция, ничего не хранит. Показывается в «Доме» (HouseScreen).
// Только Foundation и PetCore: гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

struct RankConfig: Hashable, Sendable {
    var titles = ["Бродяжка", "Найдёныш", "Домашний", "Любимец", "Барин", "Князь"]
    /// С какого числа ступенек начинается звание; at[0] = 0.
    var at = [0, 2, 5, 9, 14, 20]
    /// Ступеньки за стадию шерсти: Колтуны, Лохматый, Обычный, Гладкий.
    var coatPoints = [0, 1, 2, 3]

    static let shared = RankConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        let r = e["rank"]
        let titles = r["titles"].array.compactMap(\.string)
        let at = r["at"].array.compactMap(\.double).map { Int($0) }
        if !titles.isEmpty, titles.count == at.count, at.first == 0, at == at.sorted() {
            self.titles = titles
            self.at = at
        }
        let coat = r["coat_points"].array.compactMap(\.double).map { Int($0) }
        if coat.count == CoatStage.allCases.count { coatPoints = coat }
    }
}

enum Rank {
    struct Info: Equatable, Sendable {
        let index: Int
        let title: String
        let points: Int
        let homePoints: Int
        let coatPoints: Int
        /// Следующее звание и сколько ступенек до него; nil — выше некуда.
        let next: String?
        let toNext: Int
        /// Доля пути до следующего звания, 0..1 (на вершине — 1).
        let progress: Double

        var isTop: Bool { next == nil }
    }

    /// Ступеньки дома: сумма уровней всех линий (стартовые бесплатные — 0).
    static func homePoints(_ f: SaveFile) -> Int {
        HomeLine.allCases.reduce(0) { $0 + HomeShop.level(f, $1) }
    }

    static func of(_ f: SaveFile, now: Double, _ c: RankConfig = .shared) -> Info {
        info(home: homePoints(f), coat: Coat.look(f, now: now).stage, c)
    }

    static func info(home: Int, coat: CoatStage, _ c: RankConfig = .shared) -> Info {
        let cp = c.coatPoints.indices.contains(coat.rank) ? c.coatPoints[coat.rank] : 0
        let pts = max(0, home) + max(0, cp)
        let i = max(0, (c.at.lastIndex { pts >= $0 }) ?? 0)
        let top = i >= c.at.count - 1
        let next = top ? nil : c.titles[i + 1]
        let toNext = top ? 0 : c.at[i + 1] - pts
        let span = top ? 1 : max(1, c.at[i + 1] - c.at[i])
        let progress = top ? 1 : min(1, max(0, Double(pts - c.at[i]) / Double(span)))
        return Info(index: i, title: c.titles[i], points: pts, homePoints: max(0, home), coatPoints: cp,
                    next: next, toNext: toNext, progress: progress)
    }

    // MARK: тексты

    static func steps(_ n: Int) -> String {
        "\(n) " + EconText.plural(n, "ступенька", "ступеньки", "ступенек")
    }

    /// «Звание: Бродяжка».
    static func title(_ i: Info) -> String { "Звание: \(i.title)" }

    /// «До «Найдёныш» — ещё 2 ступеньки» / «Выше некуда — настоящий князь!».
    static func nextLine(_ i: Info) -> String {
        guard let n = i.next else { return "Выше некуда — настоящий \(i.title.lowercased())!" }
        return "До «\(n)» — ещё \(steps(i.toNext))"
    }

    /// Откуда берутся ступеньки — одна строка под полоской.
    static let hint = "Ступеньки дают улучшения дома и ухоженная шерсть."
}
