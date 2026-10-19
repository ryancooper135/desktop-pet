// Разбор касаний по сцене без SwiftUI: тап, тики пройденного пути, засчитанная ласка, щекотка, свайп вверх.
// HomeScreen кормит его точками из DragGesture(minimumDistance: 0), сам трекер ничего не знает про модель.
// Волна 18: свайп вверх решает направление, а не длина пути. Пока палец ушёл от точки касания в основном вверх
// (|dy| ≥ upRatio·|dx|, вверх больше upLock), тики и ласка молчат; отпустил выше swipeUp — свайп, сколько бы ни прошёл.
// Ласка — короче (strokePath 150 вместо 220): один уверенный проход по спине, а не два-три (DECISIONS, волна 18).

import CoreGraphics

enum StrokeEvent: Equatable, Sendable {
    /// Короткое касание почти без движения.
    case tap
    /// Каждые tickStep пройденного пути (номер тика с начала жеста).
    case tick(Int)
    /// Засчитанная ласка: суммарный путь ≥ strokePath, один раз за жест, не на свайпе вверх.
    case stroke
    /// tickleTaps тапов за tickleWindow секунд. Заменяет tap на последнем тапе.
    case tickle
    /// Свайп вверх (шкалы): от касания до отпускания в основном вверх. Сильнее ласки.
    case swipeUp
}

struct StrokeTracker: Sendable {
    static let tapMaxPath: CGFloat = 12
    static let tapMaxTime: Double = 0.3
    static let tickStep: CGFloat = 50
    static let strokePath: CGFloat = 150
    static let tickleTaps = 4
    static let tickleWindow: Double = 1.5
    /// Свайп вверх: от касания до отпускания dy < −swipeUp и |dy| ≥ upRatio·|dx| (уклон до ~34° от вертикали).
    static let swipeUp: CGFloat = 80
    static let upRatio: CGFloat = 1.5
    /// С этого подъёма жест считается «идёт вверх»: тики и ласка ждут, пока он не уйдёт вбок.
    static let upLock: CGFloat = 30

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
        // Идёт вверх — это свайп к шкалам, а не ласка: ни сердечек, ни .stroke. Ушёл вбок — путь уже набран, тики догонят.
        if goingUp { return out }
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

    /// Сейчас палец от точки касания в основном выше: dy < −upLock и |dy| ≥ upRatio·|dx|.
    var goingUp: Bool { Self.isUp(dx: last.x - start.x, dy: last.y - start.y, beyond: Self.upLock) }

    static func isUp(dx: CGFloat, dy: CGFloat, beyond: CGFloat) -> Bool {
        dy < -beyond && -dy >= upRatio * abs(dx)
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
        } else if Self.isUp(dx: dx, dy: dy, beyond: Self.swipeUp) {
            out.append(.swipeUp)
        }
        return out
    }
}
