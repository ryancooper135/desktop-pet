// «Пока тебя не было»: отчёт при входе в приложение (AwayReport) и его сборка из seen и событий (AwayBuilder).
// Перенесено из AppModel.swift без изменений (волна 28).

import Foundation
@preconcurrency import PetCore

// MARK: - «Пока тебя не было»

struct AwayReport: Identifiable, Sendable {
    struct Card: Identifiable, Hashable, Sendable {
        let id: String
        let icon: String
        let text: String
    }

    let id: String
    let greet: String
    let subtitle: String
    let cards: [Card]
    let cta: String
    let died: Bool
}

/// Лента из 3–6 карточек по away-ключам lines.json. Последняя — подсказка, кнопку рисует экран.
enum AwayBuilder {
    static let minAwayH = 0.5
    static let maxMiddle = 4

    static func make(_ f: SaveFile, prev: PetState, now: Double) -> AwayReport? {
        guard prev.alive, now > prev.t else { return nil }
        let r = Catalog.rules
        let o = PetRunner.owner(f, at: now)
        let s = PetEngine.awaySummary(prev, r, o, now: now, journal: f.timedActs(from: prev.t, to: now))
        let notable = s.events.contains { $0.kind != "sleep" && $0.kind != "wake" }
        guard s.awayH >= minAwayH, s.show || notable || s.died else { return nil }

        let lines = Lines.shared
        let seed = f.petId
        let slot = Int(now / 3600)
        var cards: [AwayReport.Card] = []
        func add(_ key: String, _ icon: String, _ vars: [String: String] = [:]) {
            guard cards.count < maxMiddle, let text = lines.away(key, seed: seed, slot: slot, vars: vars) else { return }
            cards.append(AwayReport.Card(id: key, icon: icon, text: text))
        }

        if s.died {
            let cause = s.events.last(where: { $0.kind == "death" })?.key
            cards.append(AwayReport.Card(id: "death", icon: "heart.slash",
                                         text: deathText(cause, name: f.petName)))
            return AwayReport(id: "away-\(Int(now))", greet: PetNames.gone(f.petName),
                              subtitle: subtitle(s.awayH), cards: cards,
                              cta: "Можно начать заново с новым щенком.", died: true)
        }

        // Сходил погулять: находка уже в альбоме — первой карточкой, это самое приятное.
        if let b = s.events.last(where: { $0.kind == "back_home" }) {
            add("back_home", "figure.walk", ["item": Finds.name(b.key ?? "")])
        }
        // Кухня с автокормушкой выручила, пока никого не было.
        if s.events.contains(where: { $0.kind == "autofeed" }) {
            add("autofed", "fork.knife")
        }
        if s.sleptH >= 3 {
            add("slept", "moon.zzz")
        } else if s.events.contains(where: { $0.kind == "nap" }) {
            add("nap", "moon")
        }
        if s.events.contains(where: { $0.kind == "heart" }) {
            add("heart_lost", "heart.slash")
        }
        let mood = PetEngine.mood(s.state, r, o, now: now)
        let lonely = s.events.contains { ($0.kind == "distress" && $0.key == "toska") || ($0.kind == "low" && $0.key == "love") }
        if mood == .sulky {
            add("sulked", "cloud")
        } else if lonely {
            add("missed", "heart")
        }

        let steps = f.journal.filter { $0.kind == "act.steps" && $0.ok == true && $0.t > prev.t && $0.t <= now }
            .reduce(0) { $0 + ($1.value ?? 0) }
        if steps > 0 { add("steps", "figure.walk", ["steps": "\(steps)"]) }

        let remote = f.journal.filter {
            $0.kind.hasPrefix("act.") && $0.ok == true && $0.t > prev.t && $0.t <= now
                && $0.source != nil && $0.source != .app && $0.source != .steps
        }.count
        if remote > 0, cards.count < maxMiddle {
            cards.append(AwayReport.Card(id: "remote", icon: "hand.wave",
                                         text: "Ты заботился издалека: \(remote) \(times(remote)). Я заметил."))
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
        add(own, "pawprint")

        if cards.isEmpty { add("nothing", "leaf") }

        let greet = lines.away(s.greet ?? "welcome", seed: seed, slot: slot) ?? "Ты вернулся!"
        let cta = lines.away(s.cta ?? "cta_ok", seed: seed, slot: slot) ?? "Я тут. Загляни ко мне."
        return AwayReport(id: "away-\(Int(now))", greet: greet, subtitle: subtitle(s.awayH),
                          cards: cards, cta: cta, died: false)
    }

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
