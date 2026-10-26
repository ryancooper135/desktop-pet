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
        /// Гуляет: когда ядро снимет прогулку (Finds.backAt). После него остров сам показывает «Дома»,
        /// даже если приложение не успело прислать новое состояние. Не в init: старый JSON и тесты не трогаем.
        var backAt: Double? = nil
        /// Волна 20: текст мысли как в пузыре приложения (PetSnapshot.wantText) — «Хрустик бы…», пока он не голодный.
        /// Optional и не в init, как backAt: старый JSON без поля — остров берёт текст по want.
        var wantText: String? = nil
        /// Волна 20: заголовок таймера как в приложении (PetSnapshot.timer.title). По одной шкале не отличить «Проголодается»
        /// (ниже 30) от «Совсем оголодает» (беда, сытость 0). nil у старого JSON — берём по шкале.
        var timerTitle: String? = nil
        /// Волна 34 J: событие островка (IslandEvents §8) — вид сейчас и после staleDate. nil у старого JSON —
        /// остров рисует прежний вид по pose/line.
        var card: IslandCard? = nil
        var next: IslandCard? = nil

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
            self.wantText = s.wantText
            self.timerTitle = s.timer?.title
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
            let peek = PetRunner.peek(f, at: t)
            if peek.alive, let w = peek.outing {
                st.backAt = Finds.backAt(w, stateT: peek.t)
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

        /// Прогулка кончилась, а нового состояния нет: время вышло (staleDate = backAt, с запасом на часы виджета).
        /// Раннее «устарело» (событие прогноза до возвращения) домой не приводит.
        func home(stale: Bool, now: Double = Clock.now()) -> Bool {
            guard let b = backAt else { return false }
            return now >= b - 1 || (stale && now >= b - Self.homeSlack)
        }

        /// Запас: ядро снимает прогулку шагом позже until, а staleDate бывает и по until.
        static let homeSlack: Double = 90
        static let homeLine = "Дома"

        /// stale — система пометила содержимое устаревшим: реакция кончилась, показываем спокойное.
        /// Вернулся с прогулки без свежего состояния — спокойная поза и «Дома».
        func shownPose(stale: Bool, now: Double = Clock.now()) -> Pose {
            if home(stale: stale, now: now) { return .idle }
            return stale ? (calmPose ?? pose) : pose
        }

        func shownLine(stale: Bool, now: Double = Clock.now()) -> String {
            if home(stale: stale, now: now) { return Self.homeLine }
            return stale ? (calmLine ?? line) : line
        }

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
