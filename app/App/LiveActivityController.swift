// Live Activity без пушей: запускает и обновляет только процесс приложения
// (в том числе когда его будит LiveActivityIntent из виджета, острова или контрола).
// Волна 34 J: что показывать, решает IslandEvents (§8): одно событие за раз — побег, последнее сердечко, голод,
// поход и «Я дома!», полная копилка, новый уровень. Всё хорошо или ночь хозяина — активности нет, закрываем.
// staleDate — момент, когда картинка сменится (из логики); вид после него (card.next) кладём заранее:
// снаружи активность не обновить. Система живёт с активностью до 8 часов — через 7 часов перезапускаем при входе.

@preconcurrency import ActivityKit
import Foundation
@preconcurrency import PetCore

@MainActor
enum LiveActivityController {
    static let restartAfter: Double = 7 * 3600
    static let minUpdateGap: Double = 5

    private static var lastPush: PetAttributes.ContentState?
    private static var lastPushT: Double = 0
    private static var calmTask: Task<Void, Never>?

    static var systemEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Что положить в активность на момент now: состояние (прежние поля + карточки события) и staleDate
    /// во времени ядра. nil — островок пустой (всё хорошо или ночь хозяина).
    static func plan(_ f: SaveFile, now: Double) -> (state: PetAttributes.ContentState, staleT: Double)? {
        let input = IslandFeed.input(f, now: now)
        let show = IslandEvents.show(input)
        guard show.current != nil else { return nil }
        let events = ForecastTools.upcoming(f, at: now, horizonH: 12)
        var state = PetAttributes.ContentState.make(f, at: now, events: events)
        // Кнопка «последнего сердечка» — то, что ядро примет в тот момент.
        let after = show.staleDate.map { IslandPlan.pick(f, at: $0) }
        let cards = IslandLook.cards(show, input, pickNow: IslandPlan.pick(f, at: now), pickAfter: after)
        state.card = cards.now
        state.next = cards.next
        // Реакцию на кнопку в карточках не рисуем: stale — только смена события.
        state.calmPose = nil
        state.calmLine = nil
        state.reactUntil = nil
        let staleT = show.staleDate ?? now + IslandEventsConfig.shared.maxStaleH * 3600
        return (state, staleT)
    }

    /// Привести остров к стейту. allowStart — можно ли запустить новую активность, если её нет
    /// (на входе в приложение и из контрола; после действий — только обновлять существующую).
    static func sync(_ f: SaveFile, allowStart: Bool, force: Bool = false) async {
        guard !Env.isUnitTest else { return }
        let running = Activity<PetAttributes>.activities
        guard f.island.enabled else {
            if !running.isEmpty { await endAll() }
            return
        }
        let now = Clock.now()
        guard let p = plan(f, now: now) else {
            // Событие кончилось (покормили, вернулся и погладили) или пришла ночь — островок пустеет.
            if !running.isEmpty { await endAll(resting: f, now: now) }
            return
        }
        let state = p.state
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSince1970: p.staleT - Clock.offset))

        // Запуск «из будущего» (часы перевели назад) — возраст неизвестен: перезапускаем, иначе ждали бы, пока часы догонят.
        let tooOld = f.island.startedT.map { now - $0 > restartAfter || $0 - now > 300 } ?? true
        // Имя в острове задаётся при запуске: сменили персонажа (волна 14) — перезапускаем при открытии.
        let renamed = running.contains { $0.attributes.name != f.petName }
        if running.isEmpty || ((tooOld || renamed) && allowStart) {
            guard allowStart, systemEnabled else { return }
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            do {
                let activity = try Activity.request(attributes: PetAttributes(name: f.petName), content: content, pushType: nil)
                let id = activity.id
                _ = try? PetStore.shared.mutate { (g: inout SaveFile) -> Void in
                    g.island.startedT = now
                    g.island.activityId = id
                }
                lastPush = state
                lastPushT = now
                scheduleResync(p.staleT, now: now)
            } catch {
                // Не разрешено или запуск из фона не дали — попробуем при следующем входе.
            }
            return
        }

        if !force, let last = lastPush, last.sameContent(as: state), now - lastPushT < minUpdateGap { return }
        for a in running { await a.update(content) }
        lastPush = state
        lastPushT = now
        scheduleResync(p.staleT, now: now)
    }

    /// К смене события — пересчитать остров (если процесс к тому времени ещё жив): следующее событие
    /// уже лежит в state.next, а это даст и новое «после».
    private static func scheduleResync(_ at: Double, now: Double) {
        calmTask?.cancel()
        calmTask = nil
        guard at > now else { return }
        let wait = at - now + 0.5
        calmTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            calmTask = nil
            await sync(PetStore.load(), allowStart: false, force: true)
        }
    }

    /// Закрыть с последним видом «Всё хорошо» (на экране блокировки повисит, пока длится реакция на кнопку).
    private static func endAll(resting f: SaveFile, now: Double) async {
        calmTask?.cancel()
        calmTask = nil
        let input = IslandFeed.input(f, now: now)
        var st = PetAttributes.ContentState.make(f, at: now, events: [])
        st.card = IslandLook.rest(name: f.petName, night: input.quiet?.asleep(now) ?? false, at: now)
        st.next = nil
        let until = f.lastAction.map { $0.t + IslandPlan.reactionHold } ?? now
        let policy: ActivityUIDismissalPolicy = until > now
            ? .after(Date(timeIntervalSince1970: until - Clock.offset)) : .immediate
        for a in Activity<PetAttributes>.activities {
            await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: policy)
        }
        lastPush = nil
    }

    static func endAll() async {
        calmTask?.cancel()
        calmTask = nil
        for a in Activity<PetAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        lastPush = nil
    }
}
