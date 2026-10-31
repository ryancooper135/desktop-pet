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
        case .music: return "Тихий чилл, дома еле слышно. Ночью и во сне пса — ещё тише."
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

/// Волна 49: тихая чилл-музыка из файлов (CC0, content/ASSETS_LICENSES.md) вместо синтезированного чиптюна —
/// его высокие ноты Вадим слышал как «капающие монеты». Два лупа: спокойный для дома и лавки, лоу-фай для
/// мини-игр. Играет SoundKit через AVAudioPlayer по кругу, громкость — отсюда. Ночью и пока пёс спит — та же
/// музыка тише, а не тишина; пёс без сил или его нет — тишина.
enum MusicTheme: Sendable {
    enum Kind: String, Sendable, CaseIterable {
        /// Мини-игры: свой лоу-фай луп.
        case play
        /// Лавка, дом, капсулы.
        case shop
        /// Пёс на прогулке (главный экран).
        case walk
        /// Главный экран.
        case home
        /// Главный экран, пёс спит или дремлет: та же домашняя, но еле слышно.
        case sleep
    }

    /// Файлы лупов в Resources/Music (в бандле папки нет — только имя).
    static let homeTrack = "music_home"
    static let playTrack = "music_play"
    static let tracks = [homeTrack, playTrack]
    static let fileExtension = "m4a"

    static func track(_ k: Kind) -> String {
        k == .play ? playTrack : homeTrack
    }

    /// Громкость плеера 0…1 (файлы сведены к −16…−20 LUFS): музыка — фон под звуками, не наравне с ними.
    static func volume(_ k: Kind) -> Double {
        switch k {
        case .play: return 0.32
        case .shop: return 0.3
        case .walk: return 0.26
        case .home: return 0.28
        case .sleep: return 0.12
        }
    }

    /// Ночью (тихие часы хозяина) — во столько раз тише, и в играх тоже.
    static let nightScale = 0.4

    /// Итоговая громкость: место × ночь.
    static func level(_ k: Kind, quiet: Bool) -> Double {
        volume(k) * (quiet ? nightScale : 1)
    }

    /// Плавности, секунды: вход с нуля, уход в ноль, смена громкости (ночь, сон) на том же лупе.
    static let fadeIn = 2.0
    static let fadeOut = 0.8
    static let fadeChange = 1.5

    // MARK: где играть

    /// Тихие часы — от отбоя хозяина до подъёма (пёс в это время спит).
    static func quietHours(localMin: Double, bedMin: Int, wakeMin: Int) -> Bool {
        OwnerSleep.inWindow(Int(localMin) % 1440, bedMin, wakeMin)
    }

    /// Что играть на главном экране: пёс гуляет — прогулка; спит — тихо; без сил или его нет — тишина.
    static func homeKind(pose: Pose, alive: Bool) -> Kind? {
        guard alive else { return nil }
        switch pose {
        case .dead, .critical: return nil
        case .sleep, .nap: return .sleep
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
    static let tricks = "Команды"
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
