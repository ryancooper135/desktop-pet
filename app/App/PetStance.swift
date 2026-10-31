// Положение тела Шибы и какие клипы играть: переходы между позами, основной цикл, фиджеты, реакции на действия.
// Чистая логика без RealityKit — её покрывает PetStanceTests. Проигрыватель — PetModel в PetStage.swift.

import Foundation

/// Как стоит тело. Между положениями — только через клипы-переходы, без телепорта.
enum Stance: String, Sendable, CaseIterable {
    case stand, sit, lie, sleep, dead
}

/// Реакция на действие: id растёт на каждое нажатие, kind — feed/item/pet/play/wake/bath, ok — получилось ли.
struct PetReaction: Sendable, Equatable {
    var id: Int = 0
    var kind: String = ""
    var ok: Bool = true
}

enum PetStance {
    // MARK: поза → положение и цикл

    static func stance(for pose: Pose) -> Stance {
        switch pose {
        case .sleep, .nap: return .sleep
        case .critical, .tired: return .lie
        case .dirty, .bath: return .sit
        case .dead: return .dead
        case .happy, .loved, .eating, .idle, .bored, .lonely, .sulky, .hungry: return .stand
        // Уходит и приходит шагом; пока гуляет, тела в комнате нет (PetStage прячет).
        case .away: return .stand
        }
    }

    /// Основной цикл позы. У смерти цикла нет: death играет один раз и стоит на последнем кадре.
    static func loop(for pose: Pose) -> String {
        switch pose {
        case .happy, .loved: return "idle_2"
        // Ест одним подходом (intro или реакция feed), потом довольная стойка.
        case .eating: return "idle_2"
        case .sleep, .nap: return "sleep"
        case .critical, .tired: return "lie"
        case .bored, .lonely, .sulky, .hungry: return "idle_headlow"
        case .dirty, .bath: return "sit"
        case .dead: return "death"
        case .idle: return "idle"
        case .away: return "walk"
        }
    }

    /// Клипы, на которые опираются правила без таблицы: контракт и части eat, которые режет сцена (EatClip).
    static let defaultClips: Set<String> = Set(PetClipNames.required).union(EatClip.parts)

    /// Что сыграть один раз при входе в позу, если реакция этого не сделала.
    static func intro(for pose: Pose, available: Set<String> = defaultClips) -> [String] {
        pose == .eating ? EatClip.meal(chews: EatClip.feedChews, available: available) : []
    }

    /// Intro при входе в позу после реакции played. Если реакция уже сыграла все его клипы (покормили —
    /// ядро следом прислало «ест»), второй раз не играем: иначе Шиба поднимал голову и ел второй круг.
    static func introSteps(for pose: Pose, after played: [String], available: Set<String> = defaultClips) -> [String] {
        let wanted = pick(Self.intro(for: pose, available: available), available: available)
        if !wanted.isEmpty && Set(wanted).isSubset(of: Set(played)) { return [] }
        return wanted
    }

    /// Поза, которую ядро пришлёт после удачного действия (как Presenter.pose: feed/item/cook → eating).
    /// Реакция сразу кончается циклом этой позы, а не циклом прежней — на стыке ничего не мелькает.
    static func poseAfter(reaction kind: String, ok: Bool) -> Pose? {
        ok && (kind == "feed" || kind == "item" || kind == Cooking.reactKind) ? .eating : nil
    }

    /// Цикл по умолчанию для положения: им заполняем паузу, пока поза ещё не пришла.
    static func restLoop(for stance: Stance) -> String {
        switch stance {
        case .stand: return "idle"
        case .sit: return "sit"
        case .lie: return "lie"
        case .sleep: return "sleep"
        case .dead: return "death"
        }
    }

    // MARK: переходы

    /// Клипы перехода из a в b. Из X в X — пусто; в смерть — death; из смерти — мгновенная смена.
    static func path(from a: Stance, to b: Stance) -> [String] {
        if a == b { return [] }
        if b == .dead { return ["death"] }
        switch (a, b) {
        case (.dead, _): return []
        case (.stand, .sit): return ["sit_in"]
        case (.stand, .lie): return ["lie_in"]
        case (.stand, .sleep): return ["lie_in", "sleep_in"]
        case (.sit, .stand): return ["sit_out"]
        case (.sit, .lie): return ["sit_out", "lie_in"]
        case (.sit, .sleep): return ["sit_out", "lie_in", "sleep_in"]
        case (.lie, .stand): return ["lie_out"]
        case (.lie, .sit): return ["lie_out", "sit_in"]
        case (.lie, .sleep): return ["sleep_in"]
        case (.sleep, .stand): return ["sleep_out", "lie_out"]
        case (.sleep, .lie): return ["sleep_out"]
        case (.sleep, .sit): return ["sleep_out", "lie_out", "sit_in"]
        default: return []
        }
    }

    /// В каком положении окажется тело после этих клипов.
    static func endStance(after clips: [String], from start: Stance) -> Stance {
        var s = start
        for c in clips {
            switch c {
            case "sit_in": s = .sit
            case "sit_out", "lie_out": s = .stand
            case "lie_in", "sleep_out": s = .lie
            case "sleep_in": s = .sleep
            case "death": s = .dead
            case "play_dead_out": s = .stand
            default: break
            }
        }
        return s
    }

    // MARK: фиджеты простоя

    /// Короткие вставки в простое по положению. Из optional — только если клип есть.
    static let fidgetTable: [Stance: [String]] = [
        .stand: ["idle_2", "ear_flick", "head_tilt", "sniff", "look_l", "look_r", "yawn"],
        .sit: ["ear_flick", "head_tilt"],
        .lie: ["ear_flick", "yawn"],
    ]

    static func fidgets(for stance: Stance) -> [String] {
        fidgetTable[stance] ?? []
    }

    // MARK: реакции

    /// Одноразовая реакция телом. Клипы стоя (hit, eat, прыжок) — только из положения stand, иначе был бы телепорт:
    /// если действие поднимает питомца, проигрыватель сначала играет переход, потом реакцию уже стоя.
    static func reaction(kind: String, ok: Bool, stance: Stance, lookX: Float? = nil,
                         available: Set<String> = defaultClips) -> [String] {
        if stance == .dead { return [] }
        if let trick = Trick(kind: kind) {
            return trickClips(trick, ok: ok, stance: stance, available: available)
        }
        if kind == Brush.journalKind {
            return brushClips(ok: ok, stance: stance, lookX: lookX, available: available)
        }
        // Тап по псу с заметным характером (Traits.tapKind): стоя — клип черты, сидя и лёжа — повёл ухом.
        if let trait = Traits.tapTrait(kind) {
            if stance == .sleep { return [] }
            return pick(stance == .stand ? Traits.tapClips(trait) : ["ear_flick"], available: available)
        }
        // Итог «Блок Дуо» (волна 12) — радость: подпрыгнул и виляет.
        if kind == BlockDuo.reactKind {
            return joyClips(stance: stance, available: available)
        }
        // Новый уровень или подрос (волна 57: раньше играл трюк «Прыжок», его больше нет) — встал, прыжок, виляет.
        if kind == levelUpKind {
            if stance == .sleep || stance == .dead { return [] }
            let body = pick(["hop", "happy_wag"], available: available)
            if body.isEmpty || stance == .stand { return body }
            return pick(path(from: stance, to: .stand), available: available) + body
                + pick(path(from: .stand, to: stance), available: available)
        }
        if !ok {
            return stance == .sleep ? [] : pick(ReactBeat.refuse, available: available)
        }
        let standing = stance == .stand
        var out: [String] = []
        switch kind {
        case "pet":
            if standing {
                // Ласка, а не удар: виляние хвостом (волна 32: без head_tilt — шея набок читалась кривой мордой,
                // ласка тянулась 2,7 с). Наклон телом к руке, зажмуривание и виляние задом кладёт поверх
                // PetChoreo.petting. Без этих клипов — старый «тычок» с той стороны, где рука.
                out = pick(ReactBeat.pet, available: available)
                if out.isEmpty {
                    let left: Bool
                    if let x = lookX, x != 0 { left = x < 0 } else { left = Bool.random() }
                    out = [left ? "hit_left" : "hit_right"]
                }
            } else {
                out = ["ear_flick"]
            }
        case "play":
            if standing {
                // play_bow запускает игру с мячом (PetChoreo); без него — прыжок.
                let fun = pick(["play_bow", "hop"], available: available)
                out = fun.first.map { [$0] } ?? ["jump_to_idle"]
            }
        // блюдо с кухни (Cooking) ест как обычную еду — те же клипы
        // Поел — вильнул хвостом (волна 32): у еды есть конец, миска уезжает на нём.
        case "feed", Cooking.reactKind:
            if standing {
                let meal = EatClip.meal(chews: EatClip.feedChews, available: available)
                out = meal.isEmpty ? [] : meal + pick(ReactBeat.afterMeal, available: available)
            }
        case "item":
            if standing { out = EatClip.meal(chews: EatClip.itemChews, available: available) }
        case "wake":
            switch stance {
            // Открыл глаза, зевнул лёжа, встал (волна 32: зевок — без него подъём читался как рывок).
            case .sleep: out = ReactBeat.wakeFromSleep
            case .lie: out = ["lie_out"]
            default: out = []
            }
        case "bath":
            // Волна 32: стоя отклик — сесть в ванну (поза «в ванне», sit_in); отряхивается он после неё (drive).
            // Раньше отряхивался стоя до ванны. Уже сидит (грязный) — повёл ухом.
            if stance == .sit { out = ReactBeat.bathSitting }
        default:
            out = []
        }
        return pick(out, available: available)
    }

    /// Реакция на новый уровень/рост (AppModel+Level). Строка совпадает с ReactBeat (там — "levelup").
    static let levelUpKind = "levelup"

    /// Радость (итог «Блок Дуо»): стоя подпрыгнул и виляет, сидя и лёжа — повёл ухом и не встаёт. Спящего не будим.
    static func joyClips(stance: Stance, available: Set<String> = defaultClips) -> [String] {
        switch stance {
        case .stand: return pick(["hop", "happy_wag"], available: available)
        case .sit, .lie: return pick(["ear_flick"], available: available)
        case .sleep, .dead: return []
        }
    }

    /// Расчёсывание (Brush): дочесали — отряхнулся, подпрыгнул, виляет (сидящий/лежащий сначала встаёт); против шерсти — дёрнулся
    /// от щётки (стоя — «тычок» с той стороны, где палец), сидя и лёжа — повёл ухом. Спящему не до щётки.
    static func brushClips(ok: Bool, stance: Stance, lookX: Float? = nil, available: Set<String> = defaultClips) -> [String] {
        if stance == .dead || stance == .sleep { return [] }
        if ok {
            // Волна 11: довольный финал — отряхнулся, подпрыгнул и гордо виляет (≈3 с вместо одного shake).
            // Без клипа shake (старая модель) — хотя бы вильнул хвостом.
            let shake = pick(["shake"], available: available)
            let body = shake.isEmpty ? pick(["happy_wag"], available: available)
                : shake + pick(["hop", "happy_wag"], available: available)
            if body.isEmpty || stance == .stand { return body }
            return pick(path(from: stance, to: .stand), available: available) + body
        }
        if stance == .stand {
            let left: Bool
            if let x = lookX, x != 0 { left = x < 0 } else { left = Bool.random() }
            return pick([left ? "hit_left" : "hit_right"], available: available)
        }
        return pick(["ear_flick"], available: available)
    }

    /// Трюк (Tricks): удача — его клипы, нет — склонил голову и понюхал («Не понял…»). Клипы трюков — из стойки
    /// «стоит»: сидящий или лежащий сначала встаёт, после трюка возвращается в своё положение. Спящему не до трюков.
    /// «Сидеть» сидящему и «Лежать» лежащему — без вставания: повёл ухом/головой и остался, как велели.
    static func trickClips(_ trick: Trick, ok: Bool, stance: Stance, available: Set<String> = defaultClips) -> [String] {
        if stance == .dead || stance == .sleep { return [] }
        if ok, let stay = stayClips[trick], stay.stance == stance {
            return pick(stay.clips, available: available)
        }
        let body = pick(ok ? trick.clips : Tricks.failClips, available: available)
        if body.isEmpty { return [] }
        if stance == .stand { return body }
        return pick(path(from: stance, to: .stand), available: available) + body
            + pick(path(from: .stand, to: stance), available: available)
    }

    /// Команда, которую пёс уже выполняет: короткая вставка из фиджетов этой стойки и удержание позы.
    /// Волна 57: «Лапу» и «Дай пять» сидящий даёт не вставая, «Ползи» лежащий — не вставая.
    static let stayClips: [Trick: (stance: Stance, clips: [String])] = [
        .sit: (.sit, ["head_tilt", "sit"]),
        .paw: (.sit, ["paw"]),
        .five: (.sit, ["high_five"]),
        .lie: (.lie, ["ear_flick", "lie"]),
        .crawl: (.lie, ["crawl", "crawl"]),
    ]

    /// Оставляет только клипы, которые есть. Нет клипа — шаг пропускается.
    static func pick(_ names: [String], available: Set<String>) -> [String] {
        names.filter { available.contains($0) }
    }
}
