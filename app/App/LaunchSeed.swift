// Сиды запуска для UI-тестов и отладки (PET_RESET, PET_AWAY_H, PET_SEED и др.).
// Перенесено из AppModel.swift без изменений (волна 28).

import Foundation
@preconcurrency import PetCore

// MARK: - Сиды для тестов и отладки

/// PET_RESET=1 — стереть стор; PET_AWAY_H=<часы> — будто приложение не открывали столько часов;
/// PET_SEED=critical|dead|nap|bath|walk|walk_back — готовое состояние (walk — гуляет ещё 20 мин,
/// walk_back — вернётся через 6 с при открытом приложении, для раскадровки anim-walk;
/// tastes — один открытый вкус и один «???» в альбоме; postcard — неразобранная открытка за вчера;
/// postcard_photo — открытка «играли» за вчера, кадр снимет камера сцены; postcard_expiring — открытке неделя;
/// room_max — все линии дома на верхнем уровне, room_mid — уровни 1–2 вперемешку, для снимков комнаты;
/// house_rich — все линии дома на базе и 50 000 монет: в HouseUITests покупка проходит с первого нажатия;
/// tricks — «Сидеть» выучен, «Лежать» 3 из 5, дальше замки;
/// brush — сытый бодрый щенок со свалявшейся шерстью, для снимков расчёсывания;
/// wear — в коллекции шапочка, бантик, бандана, шарф, плащ и миска, надеты шапочка, шарф и плащ (ui-61/62);
/// memories — месяц вместе: прогулки, трюки, рекорд, вещь, кровать, любимая еда и неделя игр — игривый характер,
/// а в полдень (PET_NOW) пузырь — воспоминание (ui-73/74);
/// items — 14 предметов всех ролей, кубок на полке, теннисный мячик, корона и бабочка, 5000 монет (ui-67/68);
/// fur_shaggy — сытый щенок с лохматой шерстью и клочками на спине (ui-71); fur_brushed — он же, расчёсанный
/// дважды (раз два часа назад, раз только что): гладкая шерсть без клочков (ui-72);
/// blockduo — бодрый щенок с рекордом «Блок Дуо» 1800 (ui-79/80);
/// zombie — бодрый щенок с рекордом «Щенок против зомби» 300 (ui-83/84);
/// charpack — свои персонажи (волна 12) из шибы бандла: «Серый Шиба» (клипы переименованы, рост 0,8, серая
/// шерсть) активен, «Без стойки» — без клипа idle, с ошибкой в списке (ui-81/82)).
/// Срабатывает один раз за запуск.
enum LaunchSeed {
    @MainActor private static var done = false
    /// Сид postcard_photo: какой открытке приложение снимет настоящий кадр после старта.
    @MainActor private(set) static var photoCardId: String? = nil

    @MainActor
    static func applyOnce() {
        guard !done else { return }
        done = true
        if Env.value("PET_RESET") == "1" { PetStore.reset() }
        let away = Env.value("PET_AWAY_H").flatMap { Double($0) }
        let seed = Env.value("PET_SEED")
        guard away != nil || seed != nil else { return }
        let now = Clock.now()
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in
            if let h = away, h > 0 {
                let t = now - h * 3600
                f.pet.t = t
                f.seen = f.pet
                f.lastSeenT = t
            }
            switch seed {
            case "critical":
                PetRunner.catchUp(&f, now: now)
                f.pet.needs[.food] = 0
                f.pet.needs[.clean] = 15
                f.pet.needs[.energy] = 20
                f.pet.needs[.fun] = 10
                f.pet.needs[.love] = 10
                f.pet.hearts = 1
                f.seen = f.pet
                f.lastSeenT = now
            case "dead":
                // Для скриншота экрана «Нет с нами»: умер только что, отчёт «пока не было» не всплывает.
                PetRunner.catchUp(&f, now: now)
                f.pet.needs[.food] = 0
                f.pet.hearts = 0
                f.pet.lastChanceH = nil
                f.pet.alive = false
                f.pet.diedAt = now
                f.pet.cause = .starve
                f.seen = f.pet
                f.lastSeenT = now
            case "nap":
                PetRunner.catchUp(&f, now: now)
                f.pet.napUntil = now + 40 * 60
            case "bath":
                PetRunner.catchUp(&f, now: now)
                f.pet.bathUntil = now + 10 * 60
            case "walk", "walk_back":
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                if seed == "walk" {
                    f.pet.outing = Outing(from: now - 40 * 60, until: now + 20 * 60, find: "cone")
                } else {
                    // Ядро снимает прогулку на шаге в 60 с, засчитанном целиком: состояние «состарено» на 54 с,
                    // и шаг с t ≥ until закончится через 6 с после запуска.
                    f.pet.t = now - 54
                    f.pet.outing = Outing(from: now - 40 * 60, until: f.pet.t, find: "cone")
                }
                f.seen = f.pet
                f.lastSeenT = now
            case "tastes":
                // Любимая еда открыта, нелюбимая игрушка — на полпути (2 из 3).
                PetRunner.catchUp(&f, now: now)
                if let love = Tastes.hidden(petId: f.petId, .food, log: f.tastes).love {
                    f.tastes.opened[Tastes.key(.food, love)] = TasteLog.Fact(r: Taste.love.rawValue, t: now - 3600)
                }
                if let d = Tastes.hidden(petId: f.petId, .toy, log: f.tastes).dislike {
                    f.tastes.seen[Tastes.key(.toy, d)] = TasteLog.Seen(n: 2, t: now - 3600, r: Taste.dislike.rawValue)
                }
            case "postcard_photo":
                // Открытка «играли» за вчера; кадр снимет сама камера сцены после старта (startPhotoChores).
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                let tz = f.owner.tzOffsetMin
                let day = DayKey.of(now, tzOffsetMin: tz) - 1
                let card = Postcards.make(Moment(kind: .play, t: DayKey.start(day, tzOffsetMin: tz) + 17 * 3600 + 20 * 60,
                                                 score: 35), day: day, petId: f.petId, tzOffsetMin: tz)
                if f.cards.card(card.id) == nil { f.cards.pending.append(card) }
                photoCardId = card.id
                f.seen = f.pet
                f.lastSeenT = now
            case "postcard_expiring":
                // Открытка недельной давности: сегодня её последний день (Postcards.isLastDay).
                PetRunner.catchUp(&f, now: now)
                let tz = f.owner.tzOffsetMin
                let day = DayKey.of(now, tzOffsetMin: tz) - Postcards.lifeDays
                let m = Moment(kind: .bath, t: DayKey.start(day, tzOffsetMin: tz) + 11 * 3600 + 5 * 60, score: 30)
                let card = Postcards.make(m, day: day, petId: f.petId, tzOffsetMin: tz)
                if f.cards.card(card.id) == nil { f.cards.pending.append(card) }
            case "postcard":
                // Открытка «первый день» за вчера, ещё не разобрана: карточка на главной.
                PetRunner.catchUp(&f, now: now)
                let tz = f.owner.tzOffsetMin
                let day = DayKey.of(now, tzOffsetMin: tz) - 1
                // Подпись с дефисом («Начало чего-то хорошего»): на снимке видно, что слово не рвётся.
                // petId здесь только зерно выбора строки — перебираем, пока не выпадет нужная.
                let m = Moment(kind: .firstDay, t: now - 86400, score: 100)
                var card = Postcards.make(m, day: day, petId: f.petId, tzOffsetMin: tz)
                for i in 0..<64 where card.lineId != "a.card_first_day.03" {
                    card = Postcards.make(m, day: day, petId: "\(f.petId)-\(i)", tzOffsetMin: tz)
                }
                if f.cards.card(card.id) == nil { f.cards.pending.append(card) }
            case "room_max", "room_mid":
                // Дом в комнате (RoomDecor): уровни ставим прямо, без покупок — монеты и журнал не нужны.
                PetRunner.catchUp(&f, now: now)
                let mid: [HomeLine: Int] = [.bath: 2, .bed: 1, .kitchen: 2, .kennel: 1, .play: 2, .yard: 1]
                for line in HomeLine.allCases {
                    f.pet.home[line] = seed == "room_max" ? RoomPlan.maxLevel : mid[line] ?? 1
                }
            case "house_rich":
                // Экран «Дом» (HouseUITests): комната пустая, монет хватит на любой уровень любой линии.
                PetRunner.catchUp(&f, now: now)
                for line in HomeLine.allCases { f.pet.home[line] = 0 }
                Economy.grant(&f, coins: 50_000)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                f.seen = f.pet
                f.lastSeenT = now
            case "tricks":
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                var sit = TrickLog.Entry()
                sit.n = Tricks.needed
                sit.t = now - 3600
                sit.tries = 9
                sit.learned = now - 3600
                f.tricks[.sit] = sit
                var lie = TrickLog.Entry()
                lie.n = 3
                lie.t = now - 3600
                lie.tries = 6
                f.tricks[.lie] = lie
                f.seen = f.pet
                f.lastSeenT = now
            case "brush":
                // С PET_RESET щенок новорождённый: при look 0 шерсть «свалялась» (Coat.newborn).
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                f.pet.needs[.look] = 0
                f.seen = f.pet
                f.lastSeenT = now
            case "blockduo":
                // «Блок Дуо» (ui-79/80): бодрый щенок, рекорд 1800 — на карточке итога видно «рекорд», в игре — бейдж.
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                f.blockduoBest = max(f.blockduoBest, 1800)
                f.seen = f.pet
                f.lastSeenT = now
            case "zombie":
                // «Щенок против зомби» (ui-83/84): бодрый щенок, рекорд 300 — на карточке «Играть» виден рекорд.
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                f.zombieBest = max(f.zombieBest, 300)
                f.seen = f.pet
                f.lastSeenT = now
            case "fur_shaggy", "fur_brushed":
                // С PET_RESET щенок новорождённый: look 50 — ухоженность 0,30, «лохматая» (CoatFur: 4 клочка).
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                f.pet.needs[.look] = 50
                if seed == "fur_brushed" {
                    // Расчёсывание поднимает на одну стадию: прошлое (лохматая → обычная) и сейчас (→ гладкая).
                    f.createdT = min(f.createdT, now - 3 * 3600)
                    f.log(Brush.actKind, t: now - 2 * 3600, source: .app, ok: true)
                    _ = Brush.finish(&f, now: now)
                }
            case "habits":
                // Экран «Привычки»: утро и три стакана воды отмечены сегодня, зарядка была вчера, остальное — ни разу.
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                Habits.checkIn(.workout, in: &f, now: now - 86400)
                Habits.checkIn(.wake, in: &f, now: now - 600)
                Habits.checkIn(.water, times: 3, in: &f, now: now - 300)
                f.seen = f.pet
                f.lastSeenT = now
            case "wear":
                // Надетое на собаке (PetWear) и кнопки «Надеть/Снять» в коллекции. Миска — не надевается.
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 80 }
                for id in ["leaf_hat", "bow_blue", "bandana_red", "scarf_knit", "cape_champion", "bowl_plain"] {
                    f.econ.items[id] = 1
                }
                for id in ["leaf_hat", "scarf_knit", "cape_champion"] { _ = Wear.put(&f, id) }
                f.seen = f.pet
                f.lastSeenT = now
            case "sleep_learned", "good_morning":
                // Сон хозяина выучен (OwnerSleep): 10 ночей вокруг 00:40–08:10 с разбросом, последняя — вчера.
                // good_morning: прошлый заход в 00:20 — первый заход утром поздоровается «Доброе утро».
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 80 }
                let day = OwnerSleep.local(now, tzOffsetMin: f.owner.tzOffsetMin).day
                let eve = [-20, 15, 0, -10, 25, 5, -5, 10, -15, 0]
                let morn = [10, -25, 0, 15, -5, 5, -10, 20, 0, -15]
                f.sleep.nights = (0..<10).map { i in
                    SleepLog.Night(n: day - 10 + i, eve: 760 + eve[i], morn: 1210 + morn[i])
                }
                f.sleep.lastT = seed == "good_morning" ? now - 8 * 3600 : now
                f.seen = f.pet
                f.lastSeenT = now
            case "memories":
                seedMemories(&f, now: now)
            case "charpack":
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 80 }
                f.character = seedCharacters()
                f.characterName = f.character.flatMap { CharacterStore.standard.entry($0)?.name }
                f.seen = f.pet
                f.lastSeenT = now
            case "items":
                // Волна 11: коллекция всех трёх ролей с иконками, кубок на полке, теннисный мячик вместо жёлтого,
                // корона и бабочка на собаке; 5000 монет — в лавке «Купить» с первого нажатия.
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 80 }
                for id in ["leaf_hat", "bow_blue", "bell_collar", "beret_red", "bowtie_dots", "wreath_autumn",
                           "crown_champion", "raincoat", "bowl_plain", "pumpkin_small", "lamp_mushroom", "trophy_cup",
                           "ball_tennis", "ball_star"] {
                    f.econ.items[id] = 1
                }
                for id in ["crown_champion", "bowtie_dots"] { _ = Wear.put(&f, id) }
                _ = ItemCatalog.toggleShelf(&f, "trophy_cup")
                _ = ItemCatalog.toggleToy(&f, "ball_tennis")
                f.econ.wallet.coins = 5000
                f.seen = f.pet
                f.lastSeenT = now
            case "kitchen":
                // Волна 12: «Кухня шефа» (L3, скидка и готовка), запас кухни полный, сытость 40 — блюдо видно
                // прибавкой; тыковка в коллекции (суп готов), банки желудей нет (печенье просит вещь).
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 75 }
                f.pet.needs[.food] = 40
                f.pet.home[.kitchen] = 3
                f.pet.pantry = 60
                f.econ.items["pumpkin_small"] = 1
                f.econ.wallet.coins = 500
                // Любимая еда уже открыта: бонус первого блюда — монеты, и на снимке видна фраза пса, а не карточка вкуса.
                if let love = Tastes.hidden(petId: f.petId, .food, log: f.tastes).love {
                    f.tastes.opened[Tastes.key(.food, love)] = TasteLog.Fact(r: Taste.love.rawValue, t: now - 86400)
                }
                f.seen = f.pet
                f.lastSeenT = now
            case "wants_pet", "walk_blocked", "walk_hungry":
                // Волна 18 (ui-88/89): «Погладь меня» — ласки 10, остальное 80; «Лапы чешутся», но чистоты 29 < 30 —
                // «Гулять» с замком, плашка «Сначала помыть → Гулять». Волна 32: гулять можно с сытости 30 (= «голодный»
                // порог), «подкормить перед прогулкой» больше не бывает — замок держит чистота, а не еда.
                // Волна 20 (ui-93, walk_hungry): еды 20 — уже голодный: плашка «Покормить», таймер «Совсем оголодает».
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                if seed == "wants_pet" {
                    f.pet.needs[.love] = 10
                } else {
                    f.pet.needs[.walk] = 0
                    if seed == "walk_hungry" { f.pet.needs[.food] = 20 } else { f.pet.needs[.clean] = 29 }
                }
                f.seen = f.pet
                f.lastSeenT = now
            default:
                break
            }
        }
    }

    /// Сид charpack: два пака из шибы бандла (ничего не качаем), старые паки стираем. Возвращает id рабочего.
    @MainActor
    private static func seedCharacters() -> String? {
        guard let model = Bundle.main.url(forResource: "shiba", withExtension: "usdz"),
              let clips = Bundle.main.url(forResource: "shiba.clips", withExtension: "json"),
              let data = try? Data(contentsOf: clips),
              let timeline = try? JSONDecoder().decode(CharacterPack.Timeline.self, from: data) else { return nil }
        let store = CharacterStore.standard
        try? FileManager.default.removeItem(at: store.root)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        func put(_ c: CharacterConfig) -> String? {
            try? store.place(id: CharacterStore.id(for: c.name)) { dir in
                try FileManager.default.copyItem(at: model, to: dir.appendingPathComponent(CharacterPack.defaultModel))
                try enc.encode(c).write(to: dir.appendingPathComponent(CharacterPack.configName))
            }.id
        }
        _ = put(CharacterPack.sample(timeline, name: "Без стойки", without: ["idle", "happy_wag", "yawn"]))
        return put(CharacterPack.sample(timeline))
    }

    /// Сид memories. Открытки за прошлые дни не всплывают: catchUp — до того, как createdT уходит в прошлое
    /// (doneDay уже вчерашний). petId перебираем, пока в момент now пузырь не станет воспоминанием (PetMind).
    @MainActor
    private static func seedMemories(_ f: inout SaveFile, now: Double) {
        let day: Double = 86400
        PetRunner.catchUp(&f, now: now)
        for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 90 }
        f.flags.rulesShown = true
        f.createdT = now - 31 * day
        // Прогулки и находки.
        for (find, ago) in [("cone", 20.0), ("stick", 10), ("sock", 4)] {
            f.pet.finds[find, default: 0] += 1
            f.log("ev.back_home.\(find)", t: now - ago * day, key: find)
        }
        // Трюки.
        for (trick, ago) in [(Trick.sit, 25.0), (.lie, 12)] {
            var e = TrickLog.Entry()
            e.n = Tricks.needed
            e.t = now - ago * day
            e.tries = 8
            e.learned = now - ago * day
            f.tricks[trick] = e
        }
        // Первая вещь из автомата и кровать.
        f.econ.capsule.pulls += 1
        f.econ.items["leaf_hat"] = 1
        f.log("capsule", t: now - 15 * day, key: "leaf_hat", value: 1)
        f.pet.home[.bed] = max(f.pet.home[.bed] ?? 0, 1)
        f.log("home.buy", t: now - 8 * day, key: HomeLine.bed.rawValue, value: 1)
        // Неделя ухода: много игр и прогулок — игривый, остальное ровно.
        let tz = f.owner.tzOffsetMin
        let today = DayKey.of(now, tzOffsetMin: tz)
        for ago in 1...6 {
            var t = DayKey.start(today - ago, tzOffsetMin: tz) + 8 * 3600
            for (kind, n) in [("play", 3), ("walk", 2), ("pet", 5), ("bath", 1), ("brush", 1)] {
                for _ in 0..<n {
                    f.log("act.\(kind)", t: t, source: .app, ok: true)
                    t += 3600
                }
            }
        }
        let base = f
        for i in 0..<128 {
            var g = base
            g.petId = "\(base.petId)-\(i)"
            if let love = Tastes.hidden(petId: g.petId, .food, log: g.tastes).love {
                g.tastes.opened[Tastes.key(.food, love)] = TasteLog.Fact(r: Taste.love.rawValue, t: now - 18 * day)
            }
            // Книга с нуля: рекорд «Лови мячик» побит три дня назад, после начала книги.
            g.memories = MemoryBook()
            g.care = CareTally()
            Memories.update(&g)
            let petT = g.pet.t
            g.pet.t = now - 3 * day
            g.catchBest = max(g.catchBest, 27)
            Memories.update(&g)
            g.pet.t = petT
            Traits.update(&g)
            f = g
            if case .memory? = PetMind.pick(g, at: now, tzOffsetMin: tz),
               let line = PetMind.line(g, at: now, tzOffsetMin: tz),
               Presenter.make(g, at: now).line == line { break }
        }
        f.seen = f.pet
        f.lastSeenT = now
    }
}
