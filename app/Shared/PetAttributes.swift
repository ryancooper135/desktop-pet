// Live Activity: атрибуты и состояние. Состояние — плоская выжимка из PetSnapshot, без ядра:
// ActivityKit кодирует его в JSON и передаёт в процесс виджетов.

import ActivityKit
import Foundation

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

        init(pose: Pose, want: String?, wantIcon: String?, line: String, hearts: Double, heartsMax: Double,
             level: Int, main: MainAct, timerStart: Double?, timerEnd: Double?, timerKind: String?, updatedAt: Double) {
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
        }

        init(_ s: PetSnapshot) {
            self.init(pose: s.pose, want: s.want, wantIcon: s.wantIcon, line: s.islandLine,
                      hearts: s.hearts, heartsMax: s.heartsMax, level: s.level, main: s.main,
                      timerStart: s.timer?.start, timerEnd: s.timer?.end, timerKind: s.timer?.kind, updatedAt: s.t)
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
