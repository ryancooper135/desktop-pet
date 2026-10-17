// Live Activity без пушей: запускает и обновляет только процесс приложения
// (в том числе когда его будит LiveActivityIntent из виджета, острова или контрола).
// Система живёт с активностью до 8 часов, поэтому через 7 часов перезапускаем её сами.
// Реакция на действие в острове: staleDate = её конец (вьюхи переключаются сами), и, пока процесс жив,
// через столько же досылаем спокойное состояние.

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
        let events = ForecastTools.upcoming(f, at: now, horizonH: 12)
        let state = PetAttributes.ContentState.make(f, at: now, events: events)
        var staleT = ForecastTools.staleDate(PetRunner.peek(f, at: now), events: events, now: now,
                                             startedT: f.island.startedT).timeIntervalSince1970
        if let ru = state.reactUntil, ru > now { staleT = min(staleT, ru) }
        let content = ActivityContent(state: state,
                                      staleDate: Date(timeIntervalSince1970: staleT - Clock.offset))

        let tooOld = f.island.startedT.map { now - $0 > restartAfter } ?? true
        if running.isEmpty || (tooOld && allowStart) {
            guard allowStart, systemEnabled else { return }
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            do {
                let activity = try Activity.request(attributes: PetAttributes(name: f.name), content: content, pushType: nil)
                let id = activity.id
                _ = try? PetStore.shared.mutate { (g: inout SaveFile) -> Void in
                    g.island.startedT = now
                    g.island.activityId = id
                }
                lastPush = state
                lastPushT = now
                scheduleCalm(state.reactUntil, now: now)
            } catch {
                // Не разрешено или запуск из фона не дали — попробуем при следующем входе.
            }
            return
        }

        if !force, let last = lastPush, last.sameContent(as: state), now - lastPushT < minUpdateGap { return }
        for a in running { await a.update(content) }
        lastPush = state
        lastPushT = now
        scheduleCalm(state.reactUntil, now: now)
    }

    /// После реакции — обновить остров спокойным состоянием (если процесс к тому времени ещё жив).
    private static func scheduleCalm(_ until: Double?, now: Double) {
        calmTask?.cancel()
        calmTask = nil
        guard let until, until > now else { return }
        let wait = until - now + 0.5
        calmTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            calmTask = nil
            await sync(PetStore.load(), allowStart: false, force: true)
        }
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
