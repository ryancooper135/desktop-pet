// Ключ местного дня — один на всё приложение. Все дневные счётчики (потолки монет, привычки, мини-игры,
// кухня, капсула, витрина) и местные дни открыток, памяти, характера и уведомлений считаются здесь.
//
// Правила времени (волна 14, DECISIONS):
// - шкалы, откаты и прогулки идут по абсолютному времени (unix-секунды, ядро) — пояс и летнее время их не трогают;
// - календарный день нужен только для дневных лимитов и «сегодня» в текстах;
// - сохранённый день назад не откатывается: часы назад или перелёт на запад не дают второй потолок,
//   а вперёд — сутки сменяются, как у хозяина (туда-обратно выходит ноль).

import Foundation

enum DayKey {
    /// Номер местных суток для момента t по поясу на этот момент (летнее время учтено). Полночь — уже новые сутки.
    static func of(_ t: Double) -> Int { of(t, tzOffsetMin: Clock.tzOffsetMin(at: t)) }

    /// Номер местных суток при заданном сдвиге пояса (минуты к востоку от UTC).
    static func of(_ t: Double, tzOffsetMin: Int) -> Int {
        floorDiv(minute(t) + tzOffsetMin, 1440)
    }

    /// Местная полночь, с которой начинаются сутки day, при заданном сдвиге.
    static func start(_ day: Int, tzOffsetMin: Int) -> Double {
        Double(day * 1440 - tzOffsetMin) * 60
    }

    /// Местная полночь суток day по поясу на тот момент (в день перевода часов сдвиг другой, чем сейчас).
    static func start(_ day: Int) -> Double {
        var t = start(day, tzOffsetMin: Clock.tzOffsetMin(at: Double(day) * 86400))
        // Сдвиг на саму полночь может отличаться от сдвига в полдень UTC — уточняем дважды.
        for _ in 0..<2 { t = start(day, tzOffsetMin: Clock.tzOffsetMin(at: t)) }
        return t
    }

    /// Следующая местная полночь после t. Сутки перевода часов — 23 или 25 часов.
    static func nextMidnight(after t: Double) -> Double {
        let m = start(of(t) + 1)
        return m > t ? m : t + 60   // запасной ход: в пределах пояса m всегда впереди
    }

    /// Счётчик «сегодня» без записи: сутки сменились — 0. Сохранённый день из будущего (часы назад) — счётчик тот же.
    static func today(_ count: Int, day stored: Int, at t: Double) -> Int {
        of(t) > stored ? 0 : count
    }

    /// Новый номер суток, если они сменились вперёд; nil — те же или из прошлого (назад не откатываемся).
    static func newer(than stored: Int, at t: Double) -> Int? {
        let d = of(t)
        return d > stored ? d : nil
    }

    /// Целая минута UTC (вниз, и для времени до 1970).
    static func minute(_ t: Double) -> Int { Int((t / 60).rounded(.down)) }

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }
}
