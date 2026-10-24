// Волна 32: переключатели «Звук и отклик» и «Уведомления», голос пса (тявк или редкое игривое рычание)
// и тихая музыка мини-игр. Здесь только решения и ноты — без SwiftUI и AVFoundation, проверяется тестами
// на Linux (PrefsTests). Экран настроек, SoundKit и NotificationScheduler читают отсюда.

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
        case .music: return "Тихая мелодия в мини-играх и в лавке. Дома — тишина."
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

/// Тихая музыкальная шкатулка: мелодия треугольником и мягкий бас, всё в пентатонике звуков.
/// Играет только на нескольких экранах (MusicTheme.Kind), на главном — тишина.
enum MusicTheme: Sendable {
    enum Kind: String, Sendable, CaseIterable {
        /// Мини-игры: бодрее.
        case play
        /// Лавка, «Блок Дуо»: спокойнее.
        case calm
    }

    static let stepsPerBar = 8
    static let melodyGain = 0.045
    static let bassGain = 0.035

    /// Длина восьмой, секунды.
    static func beat(_ k: Kind) -> Double {
        k == .play ? 0.2 : 0.3
    }

    static func barLength(_ k: Kind) -> Double {
        beat(k) * Double(stepsPerBar)
    }

    static func bars(_ k: Kind) -> Int {
        melody(k).count
    }

    static func loopLength(_ k: Kind) -> Double {
        barLength(k) * Double(bars(k))
    }

    /// Мелодия по тактам: ступени Scale, nil — пауза.
    static func melody(_ k: Kind) -> [[Int?]] {
        switch k {
        case .play:
            return [
                [5, 7, 8, 7, 10, nil, 8, nil],
                [9, 8, 7, nil, 8, nil, nil, nil],
                [5, 7, 8, 10, 12, nil, 10, nil],
                [11, 10, 8, nil, 10, nil, nil, nil],
                [8, nil, 9, 8, 7, nil, 5, nil],
                [6, nil, 7, 6, 5, nil, nil, nil],
                [7, 8, 10, 8, 9, 8, 7, nil],
                [5, nil, 7, nil, 5, nil, nil, nil],
            ]
        case .calm:
            return [
                [7, nil, 8, nil, 10, nil, 8, nil],
                [9, nil, 8, nil, 7, nil, nil, nil],
                [5, nil, 7, nil, 8, nil, 7, nil],
                [6, nil, 5, nil, nil, nil, nil, nil],
                [7, nil, 8, nil, 10, nil, 12, nil],
                [11, nil, 10, nil, 8, nil, nil, nil],
                [9, nil, 8, nil, 7, nil, 6, nil],
                [5, nil, nil, nil, nil, nil, nil, nil],
            ]
        }
    }

    /// Бас по тактам по кругу: до, ля, ре, соль.
    static let bass = [-5, -6, -4, -7]

    /// Ноты такта i (по кругу), время — от начала такта. Все помечены music.
    static func bar(_ i: Int, _ k: Kind) -> [Tone] {
        let all = melody(k)
        let line = all[((i % all.count) + all.count) % all.count]
        let b = beat(k)
        // Нота мелодии короче восьмой: одновременно звучат максимум нота мелодии и бас.
        let bell = Envelope(attack: 0.004, hold: 0.02, release: b - 0.03)
        var out: [Tone] = []
        let root = Scale.note(bass[((i % bass.count) + bass.count) % bass.count])
        for half in 0..<2 {
            out.append(Tone(at: Double(half * 4) * b, .triangle, root,
                            env: Envelope(attack: 0.01, hold: b, release: b * 2.2), gain: bassGain, cutoff: 600))
        }
        for (j, step) in line.enumerated() {
            guard let step else { continue }
            out.append(Tone(at: Double(j) * b, .triangle, Scale.note(step), env: bell, gain: melodyGain))
        }
        return out.map { var t = $0; t.music = true; return t }
    }
}
#endif
