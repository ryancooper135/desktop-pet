// Волна 18: «что нужно сейчас» и обучение жестам. Только решения, без UI: всё проверяется в NeedHintTests (и на Linux).
// • NeedHints.pick — одна плашка над панелью действий: главное желание из снимка (Presenter: wants().first, тот же
//   порог, что у пузыря мысли) → куда вести. Своей логики нужд здесь нет: желание, настроение и «можно ли» решает ядро
//   (PetEngine.wants / mood / act на копии / WalkPlan.gate), здесь только слова и маршрут.
// • NeedHints.gates — можно ли сейчас нажать кнопки панели и короткая причина на бейдж («2 мин», «спит», «устал»).
// • Tips — когда показывать обучение ласке и разовые подсказки жестов (щекотка, свайп вверх).
// Вкус (слова, пороги, сколько раз учить) — за Вадимом, вопросы в PROGRESS «Подсказки и жесты (волна 18)».

import Foundation
@preconcurrency import PetCore

/// Куда ведёт плашка: действие панели, обучение ласке, прогулка или никуда (тихая плашка).
enum HintGo: String, Equatable, Sendable {
    case feed, bath, play, pet, walk, none
}

/// Плашка «что нужно сейчас».
struct NeedHint: Equatable, Sendable {
    /// Желание ядра (WantKey: food, bath, sleep, play, pet, walk).
    let key: String
    /// Что сделать по тапу.
    let go: HintGo
    /// Крупно: «Покормить», «Сначала покормить», «Ещё раз — через 2 мин».
    let title: String
    /// Мелко: зачем или как («Проведи пальцем по спине», «Для прогулки сначала покормить»).
    let detail: String
    /// SF Symbol.
    let icon: String
    /// По этой шкале идёт беда.
    let urgent: Bool
    /// Сейчас ничего не сделать (откат, усталость) — плашка приглушённая, тап только объясняет.
    var quiet: Bool { go == .none }
    /// Что откроется следом: «Гулять» после «Сначала покормить».
    let then: String?
}

/// Можно ли сейчас нажать кнопку панели. Решает ядро (PetEngine.act на копии), здесь только бейдж.
struct ActGate: Equatable, Sendable {
    var ok: Bool
    /// Причина отказа ядра: cooldown, asleep, tired, bathing, away, dead.
    var reason: String? = nil
    /// Короткая причина на кнопку: «2 мин», «спит», «устал». nil — без бейджа.
    var badge: String? = nil
    /// Конец отката (cooldown).
    var until: Double? = nil

    static let open = ActGate(ok: true)
}

enum NeedHints {
    /// Кнопки панели, для которых считается gate (kind = PetAction.kind).
    static let kinds = ["feed", "pet", "play", "bath"]

    // MARK: можно ли нажать

    /// Все кнопки панели на момент t.
    static func gates(_ f: SaveFile, at t: Double) -> [String: ActGate] {
        gates(PetRunner.peek(f, at: t), Catalog.rules, PetRunner.owner(f, at: t))
    }

    /// s — стейт, уже досчитанный до нужного момента (s.t).
    static func gates(_ s: PetState, _ r: Rules, _ o: Owner) -> [String: ActGate] {
        var out: [String: ActGate] = [:]
        for k in kinds { out[k] = gate(k, s, r, o) }
        return out
    }

    static func gate(_ kind: String, _ s: PetState, _ r: Rules, _ o: Owner) -> ActGate {
        let a: Action
        switch kind {
        case "feed": a = PetAction.feed(Catalog.mainFood).core
        case "pet": a = .pet
        case "play": a = .play
        case "bath": a = .bath
        default: return .open
        }
        var c = s
        let res = PetEngine.act(&c, r, o, a)
        if res.ok { return .open }
        let reason = res.reason ?? "unavailable"
        switch reason {
        case "cooldown":
            let key = kind == "feed" ? Catalog.mainFood : kind
            let until = s.cooldowns[key]
            return ActGate(ok: false, reason: reason, badge: until.map { minutesLeft($0, now: s.t) }, until: until)
        case "asleep": return ActGate(ok: false, reason: reason, badge: "спит")
        case "tired": return ActGate(ok: false, reason: reason, badge: "устал")
        // Ванна и прогулка гасят всю панель сразу: бейдж тот же на всех кнопках, подробнее — таймер и записка.
        case "bathing": return ActGate(ok: false, reason: reason, badge: "моется")
        case "away": return ActGate(ok: false, reason: reason, badge: "гуляет")
        case "unwell": return ActGate(ok: false, reason: reason, badge: "плохо")
        default: return ActGate(ok: false, reason: reason)
        }
    }

    /// «2 мин» до конца отката: вверх, не меньше минуты (ноль минут не бывает — ещё нельзя).
    static func minutesLeft(_ until: Double, now: Double) -> String {
        "\(max(1, Int(((until - now) / 60).rounded(.up)))) мин"
    }

    // MARK: что нужно сейчас

    static func pick(_ snap: PetSnapshot, file f: SaveFile) -> NeedHint? {
        pick(snap, pet: PetRunner.peek(f, at: snap.t), Catalog.rules, PetRunner.owner(f, at: snap.t))
    }

    /// Плашка или nil (всё хорошо, спит, моется, гуляет, беда — там своя красная кнопка, умер).
    static func pick(_ snap: PetSnapshot, pet s: PetState, _ r: Rules, _ o: Owner) -> NeedHint? {
        guard snap.alive, !snap.critical, snap.level < 3 else { return nil }
        switch snap.main {
        case .none, .open, .wake: return nil      // моется, гуляет, дремлет
        default: break
        }
        // Дремлет: в панели «Разбудить», а голодного спящего плашка будила бы советом «покорми».
        if snap.sleeping || snap.pose == .nap || snap.pose == .sleep { return nil }
        guard let key = snap.want ?? moodWant(snap.mood) else { return nil }
        let urgent = snap.urgent
        let g = gates(s, r, o)
        switch key {
        case "food": return act("feed", key: key, urgent: urgent, gate: g["feed"], then: nil)
        case "bath": return act("bath", key: key, urgent: urgent, gate: g["bath"], then: nil)
        case "play": return act("play", key: key, urgent: urgent, gate: g["play"], then: nil)
        case "pet": return act("pet", key: key, urgent: urgent, gate: g["pet"], then: nil)
        case "sleep":
            return NeedHint(key: key, go: .none, title: "Пусть отдохнёт", detail: "Не играй с ним — силы вернутся сами",
                            icon: "moon.zzz.fill", urgent: urgent, then: nil)
        case "walk": return walk(s, r, o, urgent: urgent, gates: g)
        default: return nil
        }
    }

    /// Настроение без пузыря (желание слабее порога) → желание. sulky и ok — nil: просить нечего.
    static func moodWant(_ mood: String) -> String? {
        switch mood {
        case "hungry": return "food"
        case "smelly", "dirty": return "bath"
        case "bored": return "play"
        case "wants_love": return "pet"
        case "wants_walk": return "walk"
        case "tired": return "sleep"
        default: return nil
        }
    }

    /// Слова и значок кнопки панели.
    static func title(_ kind: String) -> String {
        switch kind {
        case "feed": return "Покормить"
        case "bath": return "Помыть"
        case "play": return "Поиграть"
        case "pet": return "Погладить"
        case "walk": return "Гулять"
        default: return ""
        }
    }

    static func icon(_ kind: String) -> String {
        switch kind {
        case "feed": return "fork.knife"
        case "bath": return "bathtub.fill"
        case "play": return "tennisball.fill"
        case "pet": return "hand.raised.fill"
        case "walk": return "figure.walk"
        default: return "pawprint.fill"
        }
    }

    /// Как сделать: подпись под заголовком плашки.
    static func how(_ kind: String) -> String {
        switch kind {
        case "feed": return "Голодный — нажми, и он поест"
        case "bath": return "Пора в ванну — нажми, и он помоется"
        case "play": return "Скучает — нажми, поиграйте"
        case "pet": return "Проведи пальцем по Шибе"
        default: return ""
        }
    }

    /// Плашка, ведущая к кнопке панели. then — «Гулять», если это шаг перед прогулкой.
    private static func act(_ kind: String, key: String, urgent: Bool, gate: ActGate?, then: String?) -> NeedHint {
        let go = HintGo(rawValue: kind) ?? .none
        let lead = then == nil ? title(kind) : "Сначала " + title(kind).lowercased()
        let detail = then == nil ? how(kind) : "Потом можно гулять"
        guard let gate, !gate.ok else {
            return NeedHint(key: key, go: go, title: lead, detail: detail, icon: icon(kind), urgent: urgent, then: then)
        }
        switch gate.reason {
        case "cooldown":
            let when = gate.badge.map { "через \($0)" } ?? "чуть позже"
            let what = kind == "pet" ? "Только что гладил" : "Только что было"
            return NeedHint(key: key, go: .none, title: "\(title(kind)) — \(when)", detail: what,
                            icon: "hourglass", urgent: urgent, then: then)
        case "tired":
            return NeedHint(key: key, go: .none, title: "Пусть отдохнёт", detail: "Устал — поиграете позже",
                            icon: "moon.zzz.fill", urgent: urgent, then: then)
        case "asleep":
            return NeedHint(key: key, go: .none, title: "Спит", detail: "Проснётся — тогда", icon: "moon.zzz.fill",
                            urgent: urgent, then: then)
        default:
            return NeedHint(key: key, go: .none, title: title(kind), detail: RefuseText.text(gate.reason ?? ""),
                            icon: icon(kind), urgent: urgent, then: then)
        }
    }

    /// Хочет гулять: можно — ведём к «Гулять»; не готов — к первому, чего не хватает (тот же порядок, что в WalkPlan).
    private static func walk(_ s: PetState, _ r: Rules, _ o: Owner, urgent: Bool, gates g: [String: ActGate]) -> NeedHint? {
        let w = WalkPlan.gate(s, r, o)
        if w.ok {
            return NeedHint(key: "walk", go: .walk, title: "Гулять", detail: "Лапы чешутся — \(w.hint)",
                            icon: "figure.walk", urgent: urgent, then: nil)
        }
        switch w.reason {
        case "not_ready":
            if let fix = w.fix {
                return act(fix, key: "walk", urgent: urgent, gate: g[fix], then: "Гулять")
            }
            // Не хватает сил: кнопки «отдохнуть» нет, ждём.
            return NeedHint(key: "walk", go: .none, title: "Сначала пусть отдохнёт", detail: w.toast,
                            icon: "moon.zzz.fill", urgent: urgent, then: "Гулять")
        case "too_late", "asleep":
            return NeedHint(key: "walk", go: .none, title: "Гулять — завтра", detail: w.toast,
                            icon: "figure.walk", urgent: urgent, then: nil)
        default:
            return NeedHint(key: "walk", go: .none, title: "Гулять — позже", detail: w.toast,
                            icon: "figure.walk", urgent: urgent, then: nil)
        }
    }
}

// MARK: - Обучение жестам

/// Что хозяин уже умеет (волна 18). Хозяйское знание: новому щенку переходит, пустое в файл не пишется.
struct TipLog: Codable, Hashable, Sendable {
    /// Сколько раз удачно погладил пальцем (жест, не кнопка).
    var strokes = 0
    /// Когда гладил пальцем последний раз.
    var lastStrokeT: Double?
    /// Разовые подсказки, что уже показаны или выучены: tickle, swipe.
    var seen: [String] = []

    var isEmpty: Bool { strokes == 0 && lastStrokeT == nil && seen.isEmpty }
}

/// Разовая подсказка жеста: значок и строчка.
struct GestureTip: Equatable, Sendable {
    let key: String
    let icon: String
    let text: String
}

enum Tips {
    // MARK: настройки (вкус — за Вадимом)

    /// Столько удачных поглаживаний — и жест выучен: обучение само больше не всплывает…
    static let learnedStrokes = 3
    /// …кроме случая, когда Шиба просит ласки, а пальцем не гладили столько секунд.
    static let refreshAfterS: Double = 3 * 86_400
    /// Подсказка жеста держится столько секунд и уходит сама.
    static let gestureTipFor: Double = 9
    /// Порядок разовых подсказок. Первая — после первого поглаживания пальцем.
    static let gestures: [GestureTip] = [
        GestureTip(key: "tickle", icon: "hand.tap.fill", text: "Четыре быстрых тапа по Шибе — щекотка"),
        GestureTip(key: "swipe", icon: "chevron.up", text: "Свайп вверх — все шкалы"),
    ]

    /// Показать ли палец «Проведи пальцем по Шибе». petReady — ядро примет .pet (не на откате, жив, дома).
    static func showPetTutor(_ log: TipLog, wantsPet: Bool, petReady: Bool, now: Double) -> Bool {
        guard petReady else { return false }
        if log.strokes < learnedStrokes { return true }
        guard wantsPet else { return false }
        guard let last = log.lastStrokeT else { return true }
        return now - last >= refreshAfterS
    }

    /// Следующая разовая подсказка жеста или nil. Не раньше первого поглаживания: сначала главное.
    static func nextGesture(_ log: TipLog) -> GestureTip? {
        guard log.strokes >= 1 else { return nil }
        return gestures.first { !log.seen.contains($0.key) }
    }

    /// Хозяин погладил пальцем.
    static func noteStroke(_ log: inout TipLog, at t: Double) {
        log.strokes += 1
        log.lastStrokeT = t
    }

    /// Подсказка показана или жест сделан сам — больше не показывать.
    static func markSeen(_ log: inout TipLog, _ key: String) {
        if !log.seen.contains(key) { log.seen.append(key) }
    }
}
