// Состояние экрана. Источник правды — стор (state.json); модель только держит последнюю копию и снимок.
// «Сейчас» всегда считается от часов: тикер раз в 30 секунд пересчитывает снимок (peek), ничего не пишет.
//
// Вход в приложение: догнать время, срок подписи, собрать «Пока тебя не было» от seen, запомнить seen.
// Уход в фон: снова запомнить seen — действия за сессию не попадают в следующий отчёт.

import Foundation
import Observation
@preconcurrency import PetCore

struct Toast: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let ok: Bool
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var file: SaveFile? = nil
    private(set) var snap: PetSnapshot
    var away: AwayReport? = nil
    var toast: Toast? = nil
    /// Стор не читается: показываем экран ошибки, нового щенка сами не заводим.
    private(set) var storeError: String? = nil
    var showNeeds = false
    var showSettings = false

    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init() {
        LaunchSeed.applyOnce()
        let now = Clock.now()
        do {
            // mutate сам заведёт щенка, если файла ещё нет (первый запуск).
            let f = try PetStore.shared.mutate { (f: inout SaveFile) -> SaveFile in f }
            // Сначала snap (без значения по умолчанию), потом остальное: у @Observable init-аксессоры.
            snap = Presenter.make(f, at: now)
            file = f
        } catch {
            snap = Presenter.make(SaveFile.fresh(now: now), at: now)
            storeError = error.localizedDescription
        }
        NotificationScheduler.registerCategories()
    }

    // MARK: жизненный цикл

    func becameActive() {
        let now = Clock.now()
        if Env.isUnitTest || storeError != nil {
            refresh(now: now)
            return
        }
        let expires = ProvisioningProfile.expirationDate()
        do {
            let result = try PetStore.shared.mutate { (f: inout SaveFile) -> (report: AwayReport?, paused: Bool) in
                let prev = f.seen ?? f.pet
                // Сначала срок подписи: если сборка истекала, это время питомцу прощается (sign_pause).
                PetRunner.applyBuild(&f, expires: expires, now: now)
                let paused = f.journal.last?.kind == "sign_pause" && f.journal.last?.t == now
                PetRunner.catchUp(&f, now: now)
                let report = paused ? nil : AwayBuilder.make(f, prev: prev, now: now)
                f.seen = f.pet
                f.lastSeenT = now
                return (report, paused)
            }
            if let report = result.report, away == nil { away = report }
            if result.paused { show("Пока подпись не работала, время для \(snap.name) стояло") }
        } catch {
            storeError = error.localizedDescription
        }
        refresh(now: now)
        startTicker()
        Task { await AppActions.shared.afterActivation() }
    }

    func wentBackground() {
        ticker?.cancel()
        ticker = nil
        if Env.isUnitTest || storeError != nil { return }
        let now = Clock.now()
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in
            PetRunner.catchUp(&f, now: now)
            f.seen = f.pet
            f.lastSeenT = now
        }
        Task { await AppActions.shared.afterBackground() }
    }

    /// Перечитать стор и пересчитать снимок на now. Ничего не пишет.
    func refresh(now: Double = Clock.now()) {
        if storeError != nil { return }
        do {
            guard let f = try PetStore.shared.read() else { return }
            file = f
            snap = Presenter.make(f, at: now)
        } catch {
            storeError = error.localizedDescription
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                self?.refresh()
            }
        }
    }

    // MARK: действия с экрана

    func act(_ a: PetAction) {
        Task { _ = await AppActions.shared.perform(a, source: .app) }
    }

    /// Тап по питомцу: в беде — самое срочное, иначе погладить.
    func tapPet() {
        guard snap.alive else { return }
        if snap.level >= 3, let a = snap.main.action {
            act(a)
        } else if snap.main == .wake {
            act(.wake)
        } else if snap.main != .none {
            act(.pet)
        }
    }

    func doMain() {
        if let a = snap.main.action { act(a) }
    }

    func setBedtime(minute: Int) {
        do {
            try PetRunner.setBedtime(minute: minute)
            refresh()
            Task { await AppActions.shared.afterChange() }
        } catch {
            show(RefuseText.text("store"), ok: false)
        }
    }

    /// Новый щенок: после смерти или при испорченном сторе. Старый файл уходит в state.broken-<t>.json.
    func startOver() {
        do {
            try PetStore.shared.startOver(now: Clock.now())
            storeError = nil
            away = nil
            refresh()
            Task { await AppActions.shared.afterChange() }
        } catch {
            storeError = error.localizedDescription
        }
    }

    /// «Попробовать снова» на экране ошибки: только чтение. Файла нет — ошибка остаётся, решает хозяин.
    func retryStore() {
        do {
            if let f = try PetStore.shared.read() {
                storeError = nil
                file = f
                snap = Presenter.make(f, at: Clock.now())
                becameActive()
            } else {
                storeError = "Сохранение отложено в сторону, восстановить не из чего."
            }
        } catch {
            storeError = error.localizedDescription
        }
    }

    func show(_ text: String, ok: Bool = true) {
        toast = Toast(text: text, ok: ok)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if Task.isCancelled { return }
            self?.toast = nil
        }
    }

    /// pet://home, pet://needs, pet://settings
    func open(_ url: URL) {
        guard url.scheme == "pet" else { return }
        switch url.host {
        case "needs": showNeeds = true
        case "settings": showSettings = true
        default:
            showNeeds = false
            showSettings = false
        }
    }
}

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
                                         text: deathText(cause, name: f.name)))
            return AwayReport(id: "away-\(Int(now))", greet: "\(f.name) больше нет",
                              subtitle: subtitle(s.awayH), cards: cards,
                              cta: "Можно начать заново с новым щенком.", died: true)
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

    static func times(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return "раз" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "раза" }
        return "раз"
    }

    static func deathText(_ cause: String?, name: String) -> String {
        switch cause {
        case "starve": return "\(name) слишком долго был голодным."
        case "dirty": return "\(name) слишком долго был грязным."
        case "toska": return "\(name) затосковал без тебя."
        default: return "\(name) не дождался."
        }
    }
}

// MARK: - Сиды для тестов и отладки

/// PET_RESET=1 — стереть стор; PET_AWAY_H=<часы> — будто приложение не открывали столько часов;
/// PET_SEED=critical|nap|bath — готовое состояние. Срабатывает один раз за запуск.
enum LaunchSeed {
    @MainActor private static var done = false

    @MainActor
    static func applyOnce() {
        guard !done else { return }
        done = true
        if Env.value("PET_RESET") == "1" { PetStore.reset() }
        let away = Env.value("PET_AWAY_H").flatMap { Double($0) }
        let seed = Env.value("PET_SEED")
        guard away != nil || seed != nil else { return }
        let now = Clock.now()
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in
            if let h = away, h > 0 {
                let t = now - h * 3600
                f.pet.t = t
                f.seen = f.pet
                f.lastSeenT = t
            }
            switch seed {
            case "critical":
                PetRunner.catchUp(&f, now: now)
                f.pet.needs[.food] = 0
                f.pet.needs[.clean] = 15
                f.pet.needs[.energy] = 20
                f.pet.needs[.fun] = 10
                f.pet.needs[.love] = 10
                f.pet.hearts = 1
                f.seen = f.pet
                f.lastSeenT = now
            case "nap":
                PetRunner.catchUp(&f, now: now)
                f.pet.napUntil = now + 40 * 60
            case "bath":
                PetRunner.catchUp(&f, now: now)
                f.pet.bathUntil = now + 10 * 60
            default:
                break
            }
        }
    }
}
