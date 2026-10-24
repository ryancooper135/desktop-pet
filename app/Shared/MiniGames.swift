// Общее для трёх мини-игр («Лови мячик», «Блок Дуо», «Щенок против зомби»): дневной потолок монет на всех
// (волна 13) и правило «кто занят» (волна 32).
// Волна 32: играть можно всегда. Раньше спящий, моющийся, гуляющий или уставший пёс закрывал игры серой кнопкой;
// теперь раунд запускается, но идёт «просто так»: без монет, без «Поиграть» в ядре (шкалы, монеты ухода, привычки),
// и Шиба потом ничего не говорит в комнате. Рекорд пишется, счётчик партий для убывания монет не растёт.
// Кончился дневной потолок — тоже «просто так» на карточке, но пёс свободен: настроение он получает, как раньше.

import Foundation
@preconcurrency import PetCore

enum MiniGames {
    /// Если в economy.json нет minigames.daily_cap: столько же, сколько потолок одной игры.
    static let defaultSharedCap = 60

    /// Монет за все мини-игры сегодня (у каждой свои сутки в сейве: вчерашнее не в счёт).
    static func coinsToday(_ f: SaveFile, now: Double) -> Int {
        DayKey.today(f.catchCoins, day: f.catchDay, at: now)
            + DayKey.today(f.blockduoCoins, day: f.blockduoDay, at: now)
            + DayKey.today(f.zombieCoins, day: f.zombieDay, at: now)
    }

    // MARK: кто занят (волна 32)

    /// Причина «монеты на сегодня всё» в note: пёс свободен, но монет за игры больше не дадут.
    static let capReason = "cap"

    /// Занят ли пёс для мини-игр — одно правило на все три. Порядок как у трюков (Tricks.gate): нет пса → гуляет →
    /// моется → спит (дрёма или ночь) → плохо, потом отказ ядра на play («tired» — нет сил). nil — свободен,
    /// раунд настоящий. Иначе — причина, и раунд идёт «просто так».
    static func busy(_ f: SaveFile, at t: Double) -> String? {
        if let r = Tricks.gate(f, at: t) { return r }
        var s = PetRunner.peek(f, at: t)
        let res = PetEngine.act(&s, Catalog.rules, PetRunner.owner(f, at: t), .play)
        return res.ok ? nil : (res.reason ?? "unavailable")
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
