// Волна 31 «для всех»: слова для VoiceOver и правила Reduce Motion / Dynamic Type без SwiftUI — гоняются в WSL
// (Tests/A11yTests.swift). Вью только подставляют: сводку сцены, действия VoiceOver по уходу, сторону миски
// и коридора в мини-играх, вежливые оговорки игр «для глаз», шаги тряски отказа, потолок крупного шрифта.
// Зрячий текст не меняется: всё отсюда читает только VoiceOver (или растёт только при крупном шрифте).

import Foundation
@preconcurrency import PetCore

enum A11y {

    // MARK: сцена

    /// Порядок шкал в сводке — как в листе «Как там …» (VisibleNeeds.all живёт в Shared/Views, сюда не видно).
    static let needOrder: [Need] = [.food, .clean, .energy, .fun, .love, .walk]

    /// Шкала целым процентом 0…100.
    static func percent(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        return Int(Swift.min(100, Swift.max(0, v)).rounded())
    }

    /// Желание пузыря глаголом: «хочет играть». Ключ ядра (WantKey) без пары — по тексту пузыря.
    /// Формы без рода: «хочет ласки», а не «соскучился» — свой персонаж может быть кем угодно.
    static func wantPhrase(_ want: String?, thought: String? = nil) -> String? {
        switch want {
        case "food": return "хочет есть"
        case "bath": return "хочет помыться"
        case "sleep": return "хочет спать"
        case "play": return "хочет играть"
        case "pet": return "хочет ласки"
        case "walk": return "хочет гулять"
        default:
            guard let t = thought?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
            return "хочет: \(EconText.lowerFirst(t))"
        }
    }

    /// «сытость 70 %, чистота 40 %, …» — в заданном порядке, только известные шкалы.
    static func needsLine(_ needs: [Need: Double], order: [Need] = needOrder) -> String {
        order.compactMap { n in
            needs[n].map { "\(EconText.lowerFirst(Catalog.needName(n))) \(percent($0)) %" }
        }.joined(separator: ", ")
    }

    /// Значение сцены для VoiceOver (подпись — поза: «Шиба спокоен»): «хочет играть; сытость 70 %, …».
    /// Ушедшему — пусто: подпись уже всё сказала.
    static func stageValue(_ s: PetSnapshot, order: [Need] = needOrder) -> String {
        guard s.alive else { return "" }
        var parts: [String] = []
        if let w = wantPhrase(s.want, thought: s.wantText) { parts.append(w) }
        let line = needsLine(s.needs, order: order)
        if !line.isEmpty { parts.append(line) }
        return parts.joined(separator: "; ")
    }

    /// Уход прямо со сцены: VoiceOver-действия «Покормить», «Погладить», … — те же, что кнопки панели.
    /// Нельзя (откат, спит, гуляет) — действие всё равно есть: ядро откажет тостом с причиной, как кнопке.
    enum StageAct: String, CaseIterable, Sendable {
        case wake, feed, pet, play, bath

        var title: String {
            switch self {
            case .wake: return "Разбудить"
            case .feed: return "Покормить"
            case .pet: return "Погладить"
            case .play: return "Поиграть"
            case .bath: return "Помыть"
            }
        }
    }

    /// Какие действия ухода предложить на сцене. «Разбудить» — только в дрёму, как на панели. Ушедшему — ничего.
    static func stageActs(pose: Pose, alive: Bool) -> [StageAct] {
        guard alive, pose != .dead else { return [] }
        let care: [StageAct] = [.feed, .pet, .play, .bath]
        return pose == .nap ? [.wake] + care : care
    }

    // MARK: мини-игры

    enum Game: String, CaseIterable, Sendable {
        case catchBall, blockDuo, zombie
    }

    /// Оговорка для VoiceOver в описании игры (видимый текст не меняется). Что можно — подсказываем как,
    /// чего нельзя — честно и вежливо. Имя «Шиба» вью адаптирует через PetNames.adapt.
    static func gameNote(_ g: Game) -> String {
        switch g {
        case .catchBall:
            return "С VoiceOver: выбери миску и смахивай вверх или вниз, чтобы двигать её. Мячики не озвучиваются — игра больше для глаз, прости."
        case .blockDuo:
            return "Эта игра для глаз: фигуры перетаскивают пальцем по полю, с VoiceOver в неё пока не сыграть. Прости! Монеты дают и две другие игры."
        case .zombie:
            return "С VoiceOver: выбери коридор и смахивай вверх или вниз, чтобы вести Шибу, а лаять — кнопкой «Гав». Зомби не озвучиваются — игра больше для глаз, прости."
        }
    }

    /// Шаг «смахни вверх/вниз» (accessibilityAdjustableAction): шестая часть хода, не дальше краёв.
    static func nudge(_ x: Double, up: Bool, range: ClosedRange<Double>, parts: Double = 6) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0, parts > 0 else { return x }
        let step = span / parts
        return Swift.min(range.upperBound, Swift.max(range.lowerBound, x + (up ? step : -step)))
    }

    /// Где сейчас миска или пёс — словами, по доле хода слева направо.
    static func side(_ x: Double, in range: ClosedRange<Double>) -> String {
        let span = range.upperBound - range.lowerBound
        let f = span > 0 ? (x - range.lowerBound) / span : 0.5
        switch f {
        case ..<0.2: return "слева"
        case ..<0.4: return "левее середины"
        case ..<0.6: return "посередине"
        case ..<0.8: return "правее середины"
        default: return "справа"
        }
    }

    // MARK: движение и шрифт

    /// Тряска отказа (pt по x) — одна на всё приложение: кнопки панели, карточки Кухни и Дома, круги игр.
    static let refuseShake: [Double] = [0, -6, 6, -3, 0]

    /// Тряска отказа и подобные качания: с Reduce Motion — только первый шаг (стоит на месте).
    /// Отклик отказа остаётся: щелчок Feel.denied и строка с причиной.
    static func steps<T>(_ steps: [T], reduce: Bool) -> [T] {
        reduce ? Array(steps.prefix(1)) : steps
    }

    /// Во сколько раз крупный шрифт может вырасти на листах (petFont): на AccessibilityXL системный текст
    /// растёт примерно вдвое с лишним, а карточки с ценой и кнопкой в строке так не помещаются даже стопкой.
    static let fontCap = 2.0

    /// Кегль под Dynamic Type с потолком: не меньше исходного (мелкий шрифт не сжимает), не больше base × cap.
    static func scaled(base: Double, scaled: Double, cap: Double = fontCap) -> Double {
        guard scaled.isFinite else { return base }
        return Swift.min(base * cap, Swift.max(base, scaled))
    }

    /// К какому стилю Dynamic Type привязать кегль: близкий по размеру системный стиль растёт так же.
    /// 0 caption2 · 1 caption · 2 footnote · 3 subheadline · 4 body · 5 title3 · 6 title2.
    static func styleRank(size: Double) -> Int {
        switch size {
        case ..<11.5: return 0
        case ..<12.5: return 1
        case ..<14.5: return 2
        case ..<16.5: return 3
        case ..<19.5: return 4
        case ..<21.5: return 5
        default: return 6
        }
    }
}
