// Волна 18: «что нужно сейчас» и обучение жестам. Только решения, без UI: всё проверяется в NeedHintTests (и на Linux).
// • NeedHints.pick — одна плашка над панелью действий: главное желание из снимка (Presenter: wants().first, тот же
//   порог, что у пузыря мысли) → куда вести. Своей логики нужд здесь нет: желание, настроение и «можно ли» решает ядро
//   (PetEngine.wants / mood / act на копии / WalkPlan.gate), здесь только слова и маршрут.
// • NeedHints.gates — можно ли сейчас нажать кнопки панели и короткая причина на бейдж («2 мин», «спит», «устал»).
// • Tips — когда показывать обучение ласке и разовые подсказки жестов (щекотка, свайп вверх).
// Вкус (слова, пороги, сколько раз учить) — за Вадимом, вопросы в PROGRESS «Подсказки и жесты (волна 18)».
// Волна 20: слова сверены с тем, что на экране. «Голодный», «скучает», «пора в ванну» — только когда шкала и правда
// ниже порога, к которому ведёт строка статуса («Проголодается через…» = ещё не голодный); см. NeedHints.isLow.

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

    // MARK: «уже плохо» — общий порог для слов

    /// Шкалы, по которым идут уровень «Просит» и таймер «Проголодается / Испачкается / Заскучает / Затоскует через…»
    /// (PetEngine.WATCH в ядре, там он internal). Тест сверяет с ядром.
    static let watched: [Need] = [.food, .clean, .fun, .love]
    /// Силы «на нуле» — как настроение tired у ядра (PetEngine.moods: energy < 20). Тест сверяет.
    static let tiredBelow: Double = 20

    /// Шкала уже «плохая»: можно говорить «голодный», «скучает», «пора в ванну». Пока она не ниже порога, строка
    /// статуса ещё считает время до него («Проголодается через 59 мин») — и слово «голодный» спорило бы с ней.
    static func isLow(_ n: Need, _ v: Double, _ r: Rules) -> Bool {
        if watched.contains(n) { return v < r.warnLow }
        if n == .energy { return v < tiredBelow }
        return false
    }

    // MARK: что нужно сейчас

    static func pick(_ snap: PetSnapshot, file f: SaveFile) -> NeedHint? {
        pick(snap, pet: PetRunner.peek(f, at: snap.t), Catalog.rules, PetRunner.owner(f, at: snap.t))
    }

    /// Плашка или nil (всё хорошо, спит, моется, гуляет, беда — там своя красная кнопка, умер).
    /// Тексты писались под Шибу («Проведи пальцем по Шибе») — для своего персонажа их правит PetNames.adapt.
    static func pick(_ snap: PetSnapshot, pet s: PetState, _ r: Rules, _ o: Owner) -> NeedHint? {
        guard let h = pickRaw(snap, pet: s, r, o) else { return nil }
        guard !PetNames.isShiba(snap.name) else { return h }
        return NeedHint(key: h.key, go: h.go, title: PetNames.adapt(h.title, name: snap.name),
                        detail: PetNames.adapt(h.detail, name: snap.name), icon: h.icon, urgent: h.urgent, then: h.then)
    }

    private static func pickRaw(_ snap: PetSnapshot, pet s: PetState, _ r: Rules, _ o: Owner) -> NeedHint? {
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
        case "food", "bath", "play", "pet":
            let kind = key == "food" ? "feed" : key
            // Ещё не голодный (строка статуса: «Проголодается через…») — «Подкормить», как под кнопкой «Гулять».
            let soft = kind == "feed" && !isLow(.food, s.needs[.food] ?? 0, r)
            return act(kind, key: key, urgent: urgent, gate: g[kind], lead: soft ? "Подкормить" : nil,
                       detail: how(kind, s, r))
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

    /// Какую шкалу поднимает кнопка панели.
    static func need(_ kind: String) -> Need? {
        switch kind {
        case "feed": return .food
        case "bath": return .clean
        case "play": return .fun
        case "pet": return .love
        default: return nil
        }
    }

    /// Как сделать: подпись под заголовком плашки. Слово о состоянии («голодный», «скучает») — только если
    /// шкала уже ниже порога (isLow); желание ядра бывает и раньше — тогда мягче.
    static func how(_ kind: String, _ s: PetState, _ r: Rules) -> String {
        let low = need(kind).map { isLow($0, s.needs[$0] ?? 0, r) } ?? false
        return how(kind, low: low)
    }

    static func how(_ kind: String, low: Bool = true) -> String {
        switch kind {
        case "feed": return low ? "Голодный — нажми, и он поест" : "Не прочь перекусить — нажми, и он поест"
        case "bath": return low ? "Пора в ванну — нажми, и он помоется" : "Ванна не помешает — нажми, и он помоется"
        case "play": return low ? "Скучает — нажми, поиграйте" : "Хочет поиграть — нажми, поиграйте"
        case "pet": return "Проведи пальцем по Шибе"
        default: return ""
        }
    }

    /// Плашка, ведущая к кнопке панели. lead — заголовок («Сначала подкормить» перед прогулкой), detail — подпись,
    /// then — «Гулять», если это шаг перед прогулкой.
    private static func act(_ kind: String, key: String, urgent: Bool, gate: ActGate?, lead: String? = nil,
                            detail: String, then: String? = nil) -> NeedHint {
        let go = HintGo(rawValue: kind) ?? .none
        // На откате — тем же глаголом, что в заголовке: «Подкормить — через 3 мин», а не «Покормить».
        let verb = lead.map { $0.hasPrefix("Сначала ") ? capitalized(String($0.dropFirst(8))) : $0 } ?? title(kind)
        let lead = lead ?? title(kind)
        guard let gate, !gate.ok else {
            return NeedHint(key: key, go: go, title: lead, detail: detail, icon: icon(kind), urgent: urgent, then: then)
        }
        switch gate.reason {
        case "cooldown":
            let when = gate.badge.map { "через \($0)" } ?? "чуть позже"
            let what = kind == "pet" ? "Только что гладил" : "Только что было"
            return NeedHint(key: key, go: .none, title: "\(verb) — \(when)", detail: what,
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
            // Волна 20: заголовок — то же слово, что под кнопкой «Гулять» («подкормить», если он не голодный),
            // подпись — та шкала, что держит, и её число: «Сытость 35, для прогулки нужно 40».
            let lacks = WalkPlan.lacks(s, r)
            if let fix = w.fix, let l = lacks.first(where: { WalkPlan.fixKind($0.need) == fix }) {
                return act(fix, key: "walk", urgent: urgent, gate: g[fix], lead: "Сначала " + WalkPlan.todoWord(l),
                           detail: walkWhy(l), then: "Гулять")
            }
            // Не хватает сил: кнопки «отдохнуть» нет, ждём.
            let detail = lacks.first.map(walkWhy) ?? w.toast
            return NeedHint(key: "walk", go: .none, title: "Сначала пусть отдохнёт", detail: detail,
                            icon: "moon.zzz.fill", urgent: urgent, then: "Гулять")
        case "too_late":
            return NeedHint(key: "walk", go: .none, title: "Гулять — завтра", detail: w.toast,
                            icon: "figure.walk", urgent: urgent, then: nil)
        case "asleep":
            // «Завтра» — только ночью; днём он дремлет и проснётся сегодня.
            let night = PetEngine.petNight(s.t, r, o)
            return NeedHint(key: "walk", go: .none, title: night ? "Гулять — завтра" : "Гулять — когда проснётся",
                            detail: w.toast, icon: "figure.walk", urgent: urgent, then: nil)
        default:
            return NeedHint(key: "walk", go: .none, title: "Гулять — позже", detail: w.toast,
                            icon: "figure.walk", urgent: urgent, then: nil)
        }
    }

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// «Сытость 35, для прогулки нужно 40» — число то же, что на шкале.
    static func walkWhy(_ l: WalkLack) -> String {
        "\(Catalog.needName(l.need)) \(l.value), для прогулки нужно \(l.required)"
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

    /// Волна 25: доля высоты сцены, где идёт дорожка пальца-обучения. На 0.5 она лежала на животе Шибы
    /// (ui-89), а знакомство учит «Веди по спине» — 0.44 приходится на спину. Засчитывает ласку любая точка сцены.
    static let tutorY: Double = 0.44
    /// Подпись пальца-обучения ласке; своему персонажу — «по питомцу» (PetNames).
    static func petTutorText(name: String) -> String { PetNames.adapt("Проведи пальцем по Шибе", name: name) }
    /// VoiceOver: «Подсказка: проведи пальцем по Шибе, чтобы погладить».
    static func petTutorLabel(name: String) -> String {
        PetNames.adapt("Подсказка: проведи пальцем по Шибе, чтобы погладить", name: name)
    }

    /// Показать ли палец «Проведи пальцем по Шибе». petReady — ядро примет .pet (не на откате, жив, дома).
    static func showPetTutor(_ log: TipLog, wantsPet: Bool, petReady: Bool, now: Double) -> Bool {
        guard petReady else { return false }
        if log.strokes < learnedStrokes { return true }
        guard wantsPet else { return false }
        guard let last = log.lastStrokeT else { return true }
        return now - last >= refreshAfterS
    }

    /// Следующая разовая подсказка жеста или nil. Не раньше первого поглаживания: сначала главное.
    /// name — кто в комнате: «Четыре быстрых тапа по питомцу» у своего персонажа.
    static func nextGesture(_ log: TipLog, name: String = PetNames.shiba) -> GestureTip? {
        guard log.strokes >= 1, let g = gestures.first(where: { !log.seen.contains($0.key) }) else { return nil }
        return GestureTip(key: g.key, icon: g.icon, text: PetNames.adapt(g.text, name: name))
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
