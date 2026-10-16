// Live Activity: атрибуты и состояние. Состояние — плоская выжимка из PetSnapshot, без ядра:
// ActivityKit кодирует его в JSON и передаёт в процесс виджетов.
// Реакция на действие живёт reactUntil секунд: до этого pose/line — реакция, после (staleDate) — calmPose/calmLine.

import ActivityKit
import Foundation
@preconcurrency import PetCore

struct PetAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var pose: Pose
        var want: String?
        var wantIcon: String?
        var line: String
        var hearts: Double
        var heartsMax: Double
        var level: Int
        var main: MainAct
        var timerStart: Double?
        var timerEnd: Double?
        var timerKind: String?
        var updatedAt: Double
        // Остров. Optional — чтобы JSON старой версии тоже читался.
        var primary: IslandAct?
        var secondary: IslandAct?
        var calmPose: Pose?
        var calmLine: String?
        var reactUntil: Double?
        /// Шкала, к которой идёт таймер «low» (food, clean, fun, love…).
        var timerNeed: String?

        init(pose: Pose, want: String?, wantIcon: String?, line: String, hearts: Double, heartsMax: Double,
             level: Int, main: MainAct, timerStart: Double?, timerEnd: Double?, timerKind: String?, updatedAt: Double,
             primary: IslandAct? = nil, secondary: IslandAct? = nil, calmPose: Pose? = nil, calmLine: String? = nil,
             reactUntil: Double? = nil, timerNeed: String? = nil) {
            self.pose = pose
            self.want = want
            self.wantIcon = wantIcon
            self.line = line
            self.hearts = hearts
            self.heartsMax = heartsMax
            self.level = level
            self.main = main
            self.timerStart = timerStart
            self.timerEnd = timerEnd
            self.timerKind = timerKind
            self.updatedAt = updatedAt
            self.primary = primary
            self.secondary = secondary
            self.calmPose = calmPose
            self.calmLine = calmLine
            self.reactUntil = reactUntil
            self.timerNeed = timerNeed
        }

        init(_ s: PetSnapshot) {
            self.init(pose: s.pose, want: s.want, wantIcon: s.wantIcon, line: s.islandLine,
                      hearts: s.hearts, heartsMax: s.heartsMax, level: s.level, main: s.main,
                      timerStart: s.timer?.start, timerEnd: s.timer?.end, timerKind: s.timer?.kind, updatedAt: s.t,
                      primary: IslandAct.from(s.main))
        }

        /// Полное состояние острова на момент t: кнопки из IslandPlan, реакция на IslandPlan.reactionHold секунд.
        static func make(_ f: SaveFile, at t: Double, events: [ForecastEvent]) -> ContentState {
            let hold = IslandPlan.reactionHold
            let calm = Presenter.make(f, at: t, upcoming: events, reactionWindow: 0)
            let live = Presenter.make(f, at: t, upcoming: events, reactionWindow: hold)
            var st = ContentState(live)
            let pick = IslandPlan.pick(f, at: t)
            st.primary = pick.primary
            st.secondary = pick.secondary
            if let la = f.lastAction, live.pose != calm.pose || live.islandLine != calm.islandLine {
                st.calmPose = calm.pose
                st.calmLine = calm.islandLine
                st.reactUntil = la.t + hold
            }
            if live.timer?.kind == "low", let e = ForecastTools.nextLow(events, after: t) {
                st.timerNeed = IslandPlan.timerNeed(key: e.key)?.rawValue
            }
            return st
        }

        /// Большая кнопка: из плана острова, у старых состояний — из main.
        var bigAct: IslandAct { primary ?? IslandAct.from(main) }

        /// Маленькая кнопка рядом, если есть и отличается от большой.
        var smallAct: IslandAct? {
            guard let s = secondary, s != bigAct, s.action != nil else { return nil }
            return s
        }

        /// stale — система пометила содержимое устаревшим: реакция кончилась, показываем спокойное.
        func shownPose(stale: Bool) -> Pose { stale ? (calmPose ?? pose) : pose }
        func shownLine(stale: Bool) -> String { stale ? (calmLine ?? line) : line }

        /// То же без времени обновления: сравниваем, есть ли что менять.
        func sameContent(as o: ContentState) -> Bool {
            var a = self, b = o
            a.updatedAt = 0
            b.updatedAt = 0
            return a == b
        }

        var timer: NeedTimer? {
            guard let s = timerStart, let e = timerEnd, let k = timerKind else { return nil }
            return NeedTimer(kind: k, start: s, end: e, title: "")
        }
    }

    var name: String
}
