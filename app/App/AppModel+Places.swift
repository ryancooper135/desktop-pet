// Волна 34 H: экран «Карта» — походы в места (Places) из приложения.
// Вся логика в Shared/Places.swift; здесь только запись в стор, тосты и проводка листа.

import Foundation
@preconcurrency import PetCore

extension AppModel {
    /// Уровень пса (DogLevel) — от него открываются места.
    var placeLevel: Int { file.map { DogLevel.level($0) } ?? 1 }

    /// Множитель времени похода от роста (щенок дольше, взрослый быстрее).
    var placeTimeX: Double { file.flatMap { Growth.mods($0)["trip_time_x"] } ?? 1 }

    /// Есть ли куда идти: до уровня 2 мест нет — «Гулять» работает как раньше, без карты.
    var hasPlaces: Bool { !Places.unlocked(dogLevel: placeLevel).isEmpty }

    /// Поход, который идёт сейчас (на время снимка).
    var placeTrip: ActiveTrip? { file.flatMap { Places.walking($0, now: snap.t) } }

    /// «Пойти» на карте: прогулка ядра + поход (Places.go) одной записью. Вышло — карта закрывается, пёс уходит
    /// из комнаты как после «Гулять». Отказ — тост с причиной; экран и так показывает её под кнопкой.
    func goPlace(_ id: String) {
        let now = Clock.now()
        let before = try? PetStore.shared.read()
        let r: Result<ActiveTrip, PlaceRefusal>
        do {
            r = try Places.perform(id, dogLevel: placeLevel, growthX: placeTimeX, now: now)
        } catch {
            refuse(RefuseText.text("store"))
            return
        }
        refresh(now: now)
        switch r {
        case .failure(let why):
            refuse(Places.refusalText(why))
        case .success(let a):
            var delta: [String: Int] = [:]
            if let before, let after = file {
                delta = AppActions.delta(PetRunner.peek(before, at: now), PetRunner.peek(after, at: now))
            }
            showMap = false
            let text = Places.awayNote(a, tzOffsetMin: file?.owner.tzOffsetMin ?? 0, now: now)
            // Лист ещё уезжает: уход из комнаты — когда её видно.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let self else { return }
                self.react("walk")
                self.settle(.walk, ActOutcome(ok: true, reason: nil), delta: delta)
                self.show(text, emoji: Places.place(a.place)?.emoji)
            }
            Task { await AppActions.shared.afterChange() }
        }
    }

    /// «Просто погулять» с карты — обычная прогулка ядра, как «Гулять» до карты.
    func walkPlain() {
        showMap = false
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.act(.walk)
        }
    }

    /// «Бросить монетку» у Колодца эха: раз в сутки за 🪙. Ответ — тостом.
    func throwCoin() {
        let now = Clock.now()
        let r: Result<WellResult, PlaceRefusal>
        do {
            r = try Places.performWish(dogLevel: placeLevel, now: now)
        } catch {
            refuse(RefuseText.text("store"))
            return
        }
        refresh(now: now)
        switch r {
        case .failure(let why):
            refuse(Places.refusalText(why))
        case .success(let w):
            Feel.success()
            show(w.text, emoji: "🪣")
            Task { await AppActions.shared.afterChange() }
        }
    }

    /// Вернулся из похода при открытом приложении: досчитать поход (находка места, событие); тост скажет refresh.
    /// Зовётся из noteWalk после праздника прогулки — пауза, чтобы всплывашка находки ядра успела показаться.
    /// Волна 36 O: поход мог досчитать кто-то другой (тикер, виджет, интент, вход) — тост всё равно один,
    /// его выдаёт TripHerald в notePlaceNews, а не тот, кто первым сделал settle.
    func notePlaceBack() {
        guard let f = file, f.trip.active != nil || tripHerald.due(f, now: Clock.now()) != nil else { return }
        placeBackWaiting = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self else { return }
            let now = Clock.now()
            let changed = (try? PetStore.shared.mutate { (f: inout SaveFile) -> Bool in
                let before = f.trip.count
                PetRunner.catchUp(&f, now: now)
                return f.trip.count != before
            }) ?? false
            self.placeBackWaiting = false
            self.refresh(now: now)
            if changed { Task { await AppActions.shared.afterChange() } }
        }
    }

    /// Тост «Сходил: …» о свежем походе — ровно один раз, после паузы notePlaceBack и не поверх отчёта
    /// «Пока тебя не было» (закроют — RootView позовёт refresh, и тост выйдет тогда).
    func notePlaceNews(_ f: SaveFile, now: Double) {
        guard !placeBackWaiting, away == nil else { return }
        guard let r = tripHerald.take(f, now: now), let line = Places.awayLines(r).first else { return }
        show(line, emoji: Places.place(r.place)?.emoji)
    }
}
