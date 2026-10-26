// Волна 32: переключатели «Звук и отклик» и «Уведомления», голос пса (тявк или редкое игривое рычание)
// и тихая музыка — мягкий чиптюн (игры, лавка и дом, прогулка, еле слышно на главном). Здесь только
// решения и ноты — без SwiftUI и AVFoundation, проверяется тестами на Linux (PrefsTests).
// Экран настроек, SoundKit и NotificationScheduler читают отсюда. Здесь же слова подписей под круглыми кнопками.

#if APP_TARGET || SWIFT_PACKAGE
import Foundation

/// Переключатель в настройках. Значение — ключ UserDefaults; по умолчанию всё включено.
enum PetPref: String, CaseIterable, Sendable {
    case sound = "sound.on"
    case voice = "voice.on"
    case music = "music.on"
    case haptics = "haptics.on"
    case notifications = "notif.on"

    var key: String { rawValue }

    var title: String {
        switch self {
        case .sound: return "Звуки"
        case .voice: return "Лай и рычание"
        case .music: return "Музыка"
        case .haptics: return "Вибрация"
        case .notifications: return "Уведомления"
        }
    }

    /// accessibilityIdentifier строки (UI-тесты): settings.sound был и раньше — не менять.
    var id: String {
        switch self {
        case .sound: return "settings.sound"
        case .voice: return "settings.voice"
        case .music: return "settings.music"
        case .haptics: return "settings.haptics"
        case .notifications: return "settings.notifications"
        }
    }

    /// Пояснение под переключателем; nil — и так понятно.
    var footer: String? {
        switch self {
        case .sound, .haptics, .notifications: return nil
        case .voice: return "Тявк, а иногда игривое «р-р-р» в игре."
        case .music: return "Тихий 8-бит, дома еле слышно. Ночью и во сне пса — тишина."
        }
    }

    /// Звуки собаки отдельно от остальных звуков — но без звуков их не слышно.
    var needsSound: Bool { self == .voice }

    func isOn(in defaults: UserDefaults = .standard) -> Bool {
        FeelGate.enabled(key, in: defaults)
    }

    func set(_ on: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key)
    }
}

// MARK: - уведомления

/// Что разрешил iPhone (UNAuthorizationStatus без UserNotifications).
enum NotifPermission: Sendable, Equatable {
    case allowed, denied, notAsked
}

enum NotifPref {
    /// Пояснение под переключателем «Уведомления».
    static func footer(on: Bool, permission: NotifPermission) -> String {
        guard on else { return "Без напоминаний. Питомец подождёт." }
        switch permission {
        case .allowed: return "Напомню, когда питомцу что-то нужно."
        case .notAsked: return "Спрошу у iPhone разрешение."
        case .denied: return "iPhone не пускает уведомления — включи их в настройках iPhone."
        }
    }

    /// Нужна ли кнопка «Открыть настройки iPhone».
    static func needsSystemSettings(on: Bool, permission: NotifPermission) -> Bool {
        on && permission == .denied
    }

    /// Что ставить в расписание: выключено — ничего (старые снимаются).
    static func notes(_ planned: [PlannedNote], on: Bool) -> [PlannedNote] {
        on ? planned : []
    }
}

// MARK: - голос пса

extension SoundCue {
    /// Звуки собаки (выключаются «Лай и рычание»).
    var isVoice: Bool {
        switch self {
        case .yip, .growl, .hello: return true
        default: return false
        }
    }
}

/// Тявк или игривое рычание. Рычание — редкий сюрприз: в игре и щекотке, не чаще раза в пару минут,
/// никогда два раза подряд и не в первые разы (сначала пёс просто радуется).
struct PetVoice: Sendable, Equatable {
    enum Event: Sendable { case play, tickle }

    /// Пауза между рычаниями, секунды.
    static let cooldown: Double = 120
    /// Сколько тявков должно быть между рычаниями (и до первого).
    static let yipsBetween = 2

    static func chance(_ e: Event) -> Double {
        switch e {
        case .play: return 0.25
        case .tickle: return 0.2
        }
    }

    private(set) var lastGrowl: Double? = nil
    private(set) var yipsSince = 0

    /// Звук на событие в момент t (секунды, монотонно); roll — случай 0..<1.
    mutating func cue(_ e: Event, at t: Double, roll: Double) -> SoundCue {
        let rested = lastGrowl.map { t - $0 >= Self.cooldown || t < $0 } ?? true
        if rested, yipsSince >= Self.yipsBetween, roll < Self.chance(e) {
            lastGrowl = t
            yipsSince = 0
            return .growl
        }
        yipsSince += 1
        return .yip
    }
}

// MARK: - музыка

/// Мягкий чиптюн: короткие лупы, у каждого места свой. Мелодия — квадрат за мягким фильтром (8-бит без
/// писка), бас — треугольник; у лоу-фай лупов лёгкий свинг. После каждой фразы — пустые такты: музыка
/// не тараторит без конца. На главном — тише всех и реже всех. Ночью и пока пёс спит — тишина (homeKind).
enum MusicTheme: Sendable {
    enum Kind: String, Sendable, CaseIterable {
        /// Мини-игры: бодрее всех.
        case play
        /// Лавка и дом: спокойный лоу-фай.
        case shop
        /// Пёс на прогулке: лёгкий шаг.
        case walk
        /// Главный экран: еле слышно, с долгими паузами.
        case home
    }

    static let stepsPerBar = 8
    static let leadGain = 0.03
    static let bassGain = 0.035
    /// Главный экран тише остальных.
    static let homeQuiet = 0.6

    /// Длина восьмой, секунды.
    static func beat(_ k: Kind) -> Double {
        switch k {
        case .play: return 0.2
        case .walk: return 0.24
        case .shop: return 0.3
        case .home: return 0.36
        }
    }

    /// Свинг: насколько (доля восьмой) запаздывает каждая вторая восьмая.
    static func swing(_ k: Kind) -> Double {
        switch k {
        case .play: return 0
        case .walk: return 0.08
        case .shop, .home: return 0.12
        }
    }

    /// Срез фильтра мелодии: ниже — мягче и «ламповее».
    static func cutoff(_ k: Kind) -> Double {
        switch k {
        case .play: return 1500
        case .walk: return 1300
        case .shop: return 1100
        case .home: return 900
        }
    }

    static func volume(_ k: Kind) -> Double {
        k == .home ? homeQuiet : 1
    }

    static func barLength(_ k: Kind) -> Double {
        beat(k) * Double(stepsPerBar)
    }

    static func bars(_ k: Kind) -> Int {
        sheet(k).count
    }

    static func loopLength(_ k: Kind) -> Double {
        barLength(k) * Double(bars(k))
    }

    /// Пустой такт — пауза между фразами.
    static func isRest(_ i: Int, _ k: Kind) -> Bool {
        line(i, k).isEmpty
    }

    /// Ноты по тактам: ступени Scale, nil — пауза, пустой такт — тишина.
    static func sheet(_ k: Kind) -> [[Int?]] {
        switch k {
        case .play:
            return [
                [5, 7, 8, nil, 7, nil, 5, nil],
                [3, nil, 5, 7, 8, nil, nil, nil],
                [8, 7, 5, nil, 7, nil, 8, nil],
                [10, nil, 8, nil, 7, nil, nil, nil],
                [],
                [5, 7, 8, nil, 10, nil, 8, nil],
                [7, nil, 5, nil, 3, nil, 5, nil],
                [7, 8, 7, 5, 4, nil, nil, nil],
                [5, nil, nil, nil, nil, nil, nil, nil],
                [],
                [],
            ]
        case .shop:
            return [
                [7, nil, 8, nil, 7, nil, 5, nil],
                [4, nil, 5, nil, nil, nil, nil, nil],
                [3, nil, 4, nil, 5, nil, 7, nil],
                [5, nil, nil, nil, nil, nil, nil, nil],
                [],
                [8, nil, 7, nil, 8, nil, 10, nil],
                [9, nil, 8, nil, nil, nil, nil, nil],
                [7, nil, 5, nil, 4, nil, 3, nil],
                [5, nil, nil, nil, nil, nil, nil, nil],
                [],
                [],
            ]
        case .walk:
            return [
                [5, nil, 7, nil, 5, nil, 8, nil],
                [7, nil, 5, nil, 4, nil, nil, nil],
                [5, nil, 7, nil, 8, nil, 10, nil],
                [8, nil, nil, nil, 7, nil, nil, nil],
                [],
                [4, nil, 5, nil, 7, nil, 5, nil],
                [3, nil, 5, nil, 4, nil, nil, nil],
                [5, 7, 8, nil, 7, nil, 5, nil],
                [5, nil, nil, nil, nil, nil, nil, nil],
                [],
                [],
            ]
        case .home:
            return [
                [7, nil, nil, nil, 5, nil, nil, nil],
                [4, nil, nil, nil, 5, nil, nil, nil],
                [],
                [],
                [8, nil, nil, nil, 7, nil, nil, nil],
                [5, nil, nil, nil, nil, nil, nil, nil],
                [],
                [],
                [],
                [],
            ]
        }
    }

    private static func line(_ i: Int, _ k: Kind) -> [Int?] {
        let all = sheet(k)
        return all[((i % all.count) + all.count) % all.count]
    }

    /// Бас по тактам по кругу: до, ля, ре, соль.
    static let bass = [-5, -6, -4, -7]

    /// Начало восьмой j в такте, с учётом свинга.
    static func stepStart(_ j: Int, _ k: Kind) -> Double {
        (Double(j) + (j % 2 == 1 ? swing(k) : 0)) * beat(k)
    }

    /// Ноты такта i (по кругу), время — от начала такта. Все помечены music.
    static func bar(_ i: Int, _ k: Kind) -> [Tone] {
        let n = bars(k), pos = ((i % n) + n) % n
        let notes = sheet(k)[pos]
        guard !notes.isEmpty else { return [] }
        let b = beat(k), v = volume(k), length = barLength(k)
        var out: [Tone] = []
        let root = Scale.note(bass[pos % bass.count])
        for half in 0..<2 {
            out.append(Tone(at: Double(half * 4) * b, .triangle, root,
                            env: Envelope(attack: 0.01, hold: b, release: b * 2.2), gain: bassGain * v, cutoff: 600))
        }
        // Нота тянется через паузы за ней (не дольше двух восьмых) и гаснет до следующей:
        // одновременно звучат максимум нота мелодии и бас.
        let attack = 0.008, hold = 0.02
        for (j, step) in notes.enumerated() {
            guard let step else { continue }
            let start = stepStart(j, k)
            let next = notes.indices.dropFirst(j + 1).first { notes[$0] != nil }.map { stepStart($0, k) } ?? length
            let span = min(next - start, 2 * b) - 0.012
            out.append(Tone(at: start, .square, Scale.note(step),
                            env: Envelope(attack: attack, hold: hold, release: span - attack - hold),
                            gain: leadGain * v, cutoff: cutoff(k)))
        }
        return out.map { var t = $0; t.music = true; return t }
    }

    // MARK: где играть

    /// Тихие часы — от отбоя хозяина до подъёма (пёс в это время спит).
    static func quietHours(localMin: Double, bedMin: Int, wakeMin: Int) -> Bool {
        OwnerSleep.inWindow(Int(localMin) % 1440, bedMin, wakeMin)
    }

    /// Что играть на главном экране: пёс гуляет — прогулка; спит, без сил или его нет — тишина.
    static func homeKind(pose: Pose, alive: Bool) -> Kind? {
        guard alive else { return nil }
        switch pose {
        case .sleep, .nap, .dead, .critical: return nil
        case .away: return .walk
        default: return .home
        }
    }
}

// MARK: - подписи под круглыми кнопками

/// Слова под круглыми кнопками ряда над панелью (App/RoundCaption.swift). Короткие: под кругом 48 pt
/// и в самом тесном ряду (зазор 2 pt) не налезают друг на друга.
enum RoundCaption {
    static let album = "Альбом"
    static let machine = "Автомат"
    static let house = "Дом"
    static let tricks = "Трюки"
    static let games = "Игры"
    /// Волна 34 G: круг «Двор» справа над рядом (App/YardEntry.swift).
    static let yard = "Двор"

    static let all = [album, machine, house, tricks, games, yard]
    /// Не длиннее — иначе шрифт ужимается и слово плохо читается.
    static let maxLength = 7
    /// Сколько места ряд оставляет под подписями, pt.
    static let room = 12.0
}
#endif
