// Общее для мини-игр («Лови мячик», «Блок Дуо», «Раннер» — волна 55b): единый реестр MiniGame (волна 55), дневной потолок монет на всех
// (волна 13) и правило «кто занят» (волна 32).
// Волна 32: играть можно всегда. Раньше спящий, моющийся, гуляющий или уставший пёс закрывал игры серой кнопкой;
// теперь раунд запускается, но идёт «просто так»: без монет, без «Поиграть» в ядре (шкалы, монеты ухода, привычки),
// и Шиба потом ничего не говорит в комнате. Рекорд пишется, счётчик партий для убывания монет не растёт.
// Кончился дневной потолок — тоже «просто так» на карточке, но пёс свободен: настроение он получает, как раньше.

import Foundation
@preconcurrency import PetCore

/// Реестр мини-игр (волна 55). Единственный список игр: монеты за сутки, опыт уровня (DogLevel.games), открытие
/// по уровню (DogLevel.gameOpen), челлендж дня (ChallengeGame — тот же тип), рекорды и «Все игры» (Shards).
/// Новая игра = новый case + её поля в SaveFile + ключи ниже. rawValue — ключ рекордов, опыта и диплинка.
/// «Щенок против зомби» убран в волне 55: поля zombie* в сейве остались для совместимости, но в реестре его нет —
/// старые партии не дают опыта и не считаются в потолок монет.
enum MiniGame: String, Codable, CaseIterable, Hashable, Sendable {
    case ball = "catch"
    case blockduo
    /// Волна 55b: бег по двору, району и парку (Runner.swift).
    case runner

    /// Короткое имя для плашки.
    var title: String {
        switch self {
        case .ball: return "Мячик"
        case .blockduo: return "Блок Дуо"
        case .runner: return "Раннер"
        }
    }

    /// Полное имя игры (меню «Мини-игры»): из конфига игры в economy.json.
    var name: String {
        switch self {
        case .ball: return CatchConfig.shared.name
        case .blockduo: return BlockDuoConfig.shared.name
        case .runner: return RunnerConfig.shared.name
        }
    }

    /// Значок пункта меню (SF Symbol).
    var icon: String {
        switch self {
        case .ball: return "tennisball.fill"
        case .blockduo: return "square.grid.3x3.fill"
        case .runner: return "figure.run"
        }
    }

    /// Поля сейва: рекорд, сутки (DayKey) счётчиков, монеты и партии за эти сутки.
    var bestKey: WritableKeyPath<SaveFile, Int> {
        switch self {
        case .ball: return \.catchBest
        case .blockduo: return \.blockduoBest
        case .runner: return \.runnerBest
        }
    }
    var dayKey: WritableKeyPath<SaveFile, Int> {
        switch self {
        case .ball: return \.catchDay
        case .blockduo: return \.blockduoDay
        case .runner: return \.runnerDay
        }
    }
    var coinsKey: WritableKeyPath<SaveFile, Int> {
        switch self {
        case .ball: return \.catchCoins
        case .blockduo: return \.blockduoCoins
        case .runner: return \.runnerCoins
        }
    }
    var gamesKey: WritableKeyPath<SaveFile, Int> {
        switch self {
        case .ball: return \.catchGames
        case .blockduo: return \.blockduoGames
        case .runner: return \.runnerGames
        }
    }

    /// Личный рекорд этой игры в сейве.
    func record(_ f: SaveFile) -> Int { f[keyPath: bestKey] }

    /// Сколько монет ещё дадут сегодня за эту игру (свой потолок и общий на все игры).
    func coinsLeft(_ f: SaveFile, now: Double) -> Int {
        switch self {
        case .ball: return CatchGame.coinsLeft(f, now: now)
        case .blockduo: return BlockDuo.coinsLeft(f, now: now)
        case .runner: return Runner.coinsLeft(f, now: now)
        }
    }
}

enum MiniGames {
    /// Если в economy.json нет minigames.daily_cap: столько же, сколько потолок одной игры.
    static let defaultSharedCap = 60

    /// Монет за все мини-игры сегодня (у каждой свои сутки в сейве: вчерашнее не в счёт).
    static func coinsToday(_ f: SaveFile, now: Double) -> Int {
        MiniGame.allCases.reduce(0) { $0 + DayKey.today(f[keyPath: $1.coinsKey], day: f[keyPath: $1.dayKey], at: now) }
    }

    /// Подсказка кнопки «Мини-игры»: «Лови мячик или Блок Дуо вместе с Шибой».
    static func menuHint(_ games: [MiniGame] = MiniGame.allCases) -> String {
        let names = games.map(\.name)
        let list = names.count < 2 ? names.joined()
            : names.dropLast().joined(separator: ", ") + " или " + names[names.count - 1]
        return list + " вместе с Шибой"
    }

    // MARK: кто занят (волна 32)

    /// Причина «монеты на сегодня всё» в note: пёс свободен, но монет за игры больше не дадут.
    static let capReason = "cap"

    /// Занят ли пёс для мини-игр — одно правило на все игры. Порядок как у трюков (Tricks.gate): нет пса → гуляет →
    /// моется → спит (дрёма или ночь) → плохо, потом отказ ядра на play («tired» — нет сил). nil — свободен,
    /// раунд настоящий. Иначе — причина, и раунд идёт «просто так».
    /// Волна 64: правила ядра — ItemPerks.rules(f), как у PetRunner.apply, который потом и проводит «Поиграть»
    /// (раньше тут стоял голый Catalog.rules, и польза вещей/стадия роста в ответ «занят ли» не входили).
    /// rules — для теста: подставить свои правила и убедиться, что решение идёт по ним.
    static func busy(_ f: SaveFile, at t: Double, rules: Rules? = nil) -> String? {
        let r = rules ?? ItemPerks.rules(f)
        if let reason = Tricks.gate(f, at: t, rules: r) { return reason }
        var s = PetRunner.peek(f, at: t)
        let res = PetEngine.act(&s, r, PetRunner.owner(f, at: t), .play)
        return res.ok ? nil : (res.reason ?? "unavailable")
    }

    /// Что карточка «Играть» и кнопка старта знают об игре в момент now (волна 64). Экраны мини-игр раньше брали
    /// model.snap.t — снимок, который мог отстать на минуты (ночь уже началась, дрёма кончилась, сутки сменились,
    /// а плашка и раунд «просто так» решались по старому времени). Теперь — текущее время, как у остальных
    /// решений ядра (PetRunner.apply, Challenges.play на финише).
    struct Start: Equatable, Sendable {
        /// Причина «просто так» (busy); nil — раунд настоящий.
        let busy: String?
        /// Плашка на карточке (note): busy или capReason.
        let note: String?
        /// Сколько монет ещё дадут сегодня за эту игру.
        let left: Int
    }

    static func start(_ f: SaveFile?, _ game: MiniGame, now: Double) -> Start {
        guard let f else { return Start(busy: nil, note: nil, left: 0) }
        let left = game.coinsLeft(f, now: now)
        let b = busy(f, at: now)
        return Start(busy: b, note: b ?? (left <= 0 ? capReason : nil), left: left)
    }

    /// Что сказать на карточке «Играть»: причина «просто так» (busy) или capReason, когда монет сегодня больше нет
    /// (left — coinsLeft этой игры). nil — обычная игра, плашки нет.
    static func note(_ f: SaveFile, at t: Double, left: Int) -> String? {
        busy(f, at: t) ?? (left <= 0 ? capReason : nil)
    }

    /// Плашка на карточке «Играть»: «Шиба спит — играем просто так, без монет».
    static func noteText(_ reason: String) -> String {
        switch reason {
        case "asleep": return "Шиба спит — играем просто так, без монет"
        case "bathing": return "Шиба моется — играем просто так, без монет"
        case "away": return "Шиба гуляет — играем просто так, без монет"
        case "tired": return "Шиба устал — играем просто так, без монет"
        case "unwell": return "Шибе плохо — играем просто так, без монет"
        case "dead": return "Шибы больше нет — играем просто так"
        case capReason: return "Монеты на сегодня всё — играем просто так"
        default: return "Играем просто так, без монет"
        }
    }

    /// То же под имя питомца в комнате (SaveFile.petName).
    static func noteText(_ reason: String, name: String) -> String {
        PetNames.adapt(noteText(reason), name: name)
    }

    /// Значок плашки (SF Symbol).
    static func noteIcon(_ reason: String) -> String {
        switch reason {
        case "asleep": return "moon.zzz.fill"
        case "away": return "figure.walk"
        case "bathing": return "drop.fill"
        case "tired": return "battery.25"
        case capReason: return "gamecontroller.fill"
        default: return "exclamationmark.circle.fill"
        }
    }

    /// Строка награды на итоге раунда «просто так».
    static let freeReward = "Играли просто так — без монет"
}
