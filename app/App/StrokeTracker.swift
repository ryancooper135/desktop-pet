// Разбор касаний по сцене без SwiftUI: тап, тики пройденного пути, засчитанная ласка, щекотка, свайп вверх.
// HomeScreen кормит его точками из DragGesture(minimumDistance: 0), сам трекер ничего не знает про модель.

import CoreGraphics

enum StrokeEvent: Equatable, Sendable {
    /// Короткое касание почти без движения.
    case tap
    /// Каждые tickStep пройденного пути (номер тика с начала жеста).
    case tick(Int)
    /// Засчитанная ласка: суммарный путь ≥ strokePath, один раз за жест.
    case stroke
    /// tickleTaps тапов за tickleWindow секунд. Заменяет tap на последнем тапе.
    case tickle
    /// Свайп вверх (шкалы), только если это не ласка.
    case swipeUp
}

struct StrokeTracker: Sendable {
    static let tapMaxPath: CGFloat = 12
    static let tapMaxTime: Double = 0.3
    static let tickStep: CGFloat = 50
    static let strokePath: CGFloat = 220
    static let tickleTaps = 4
    static let tickleWindow: Double = 1.5
    /// Свайп вверх: dy < −swipeUp и |dx| < swipeSide.
    static let swipeUp: CGFloat = 80
    static let swipeSide: CGFloat = 60

    private(set) var active = false
    private(set) var start: CGPoint = .zero
    private(set) var startTime: Double = 0
    private(set) var last: CGPoint = .zero
    private(set) var path: CGFloat = 0
    private(set) var ticks = 0
    private(set) var stroked = false
    /// Времена недавних тапов (окно щекотки), переживают конец жеста.
    private(set) var tapTimes: [Double] = []

    init() {}

    mutating func begin(at p: CGPoint, time: Double) {
        active = true
        start = p
        last = p
        startTime = time
        path = 0
        ticks = 0
        stroked = false
    }

    mutating func move(to p: CGPoint, time: Double) -> [StrokeEvent] {
        guard active else {
            begin(at: p, time: time)
            return []
        }
        let dx = p.x - last.x, dy = p.y - last.y
        path += (dx * dx + dy * dy).squareRoot()
        last = p
        var out: [StrokeEvent] = []
        while CGFloat(ticks + 1) * Self.tickStep <= path {
            ticks += 1
            out.append(.tick(ticks))
        }
        if !stroked && path >= Self.strokePath {
            stroked = true
            out.append(.stroke)
        }
        return out
    }

    mutating func end(at p: CGPoint, time: Double) -> [StrokeEvent] {
        guard active else { return [] }
        var out = move(to: p, time: time)
        active = false
        let dx = p.x - start.x, dy = p.y - start.y
        if path < Self.tapMaxPath && time - startTime < Self.tapMaxTime {
            tapTimes = tapTimes.filter { time - $0 <= Self.tickleWindow } + [time]
            if tapTimes.count >= Self.tickleTaps {
                tapTimes.removeAll()
                out.append(.tickle)
            } else {
                out.append(.tap)
            }
        } else if path < Self.strokePath && dy < -Self.swipeUp && abs(dx) < Self.swipeSide {
            out.append(.swipeUp)
        }
        return out
    }
}
