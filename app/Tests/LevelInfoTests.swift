// Волна 34 I: что показывает экран про уровень и рост (LevelInfo), голос по росту (GrowthVoice) и запись «Подрос»
// в памяти. Тексты короткие, сводка нескольких уровней — одна, лента открытий — по таблице DogLevel.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000.
private let iT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func iFile(points: Double = 0) -> SaveFile {
    var f = SaveFile.fresh(now: iT0)
    f.petId = "level-info-1"
    f.growth.points = points
    DogLevel.settle(&f, now: iT0)
    return f
}

final class LevelInfoTests: XCTestCase {

    // MARK: шапка и лист

    func testChipAndXpLine() {
        let p = LevelProgress(level: 7, xp: 1000, into: 320, need: 430)
        XCTAssertEqual(LevelInfo.chipText(p), "ур. 7")
        XCTAssertEqual(LevelInfo.xpLine(p), "320 / 430")
        XCTAssertEqual(LevelInfo.chipLabel(p), "Уровень 7, 320 опыта из 430")
        let max = LevelProgress(level: 40, xp: 22570, into: 0, need: 0)
        XCTAssertEqual(LevelInfo.xpLine(max), "предел")
        XCTAssertEqual(LevelInfo.chipLabel(max), "Уровень 40, предел")
        XCTAssertEqual(LevelInfo.chipLabel(LevelProgress(level: 2, xp: 30, into: 1, need: 40)), "Уровень 2, 1 опыт из 40")
    }

    func testTodayLine() {
        var f = iFile()
        for i in 0..<5 { f.log("act.feed", t: iT0 + Double(i), ok: true) }
        DogLevel.settle(&f, now: iT0 + 10)
        let x = LevelInfo.todayXp(f, now: iT0 + 10)
        XCTAssertEqual(x, f.level.dayXp)
        XCTAssertGreaterThan(x, 0)
        XCTAssertEqual(LevelInfo.todayLine(f, now: iT0 + 10), "Сегодня \(x) из 150")
        // Завтра учёт ещё не перешёл — сегодня 0.
        XCTAssertEqual(LevelInfo.todayXp(f, now: iT0 + 86400), 0)
        f.level.dayXp = 150
        XCTAssertEqual(LevelInfo.todayLine(f, now: iT0 + 10), "Сегодня 150 из 150 — на сегодня всё")
    }

    func testSources() {
        let s = LevelInfo.sources()
        XCTAssertFalse(s.isEmpty)
        XCTAssertEqual(Set(s.map(\.id)).count, s.count, "без повторов")
        let walk = s.first { $0.title == "Прогулка" }
        XCTAssertEqual(walk?.xp, DogLevelConfig.shared.rules["ev.back_home"]?.xp)
        XCTAssertEqual(s.last?.title, "Хороший день")
        XCTAssertEqual(LevelInfo.sourceValue(XpSource(title: "a", xp: 10, perDay: 0)), "+10")
        XCTAssertEqual(LevelInfo.sourceValue(XpSource(title: "a", xp: 8, perDay: 1)), "+8, раз в день")
        XCTAssertEqual(LevelInfo.sourceValue(XpSource(title: "a", xp: 1, perDay: 10)), "+1, 10 раз в день")
        XCTAssertEqual(LevelInfo.sourceValue(XpSource(title: "a", xp: 4, perDay: 2)), "+4, 2 раза в день")
        for r in s { XCTAssertLessThanOrEqual(r.title.count, 22, r.title) }
    }

    func testUpcomingFeed() {
        let cfg = DogLevelConfig()
        let u = LevelInfo.upcoming(after: 1, cfg)
        XCTAssertEqual(u.map(\.level), [2, 3, 4, 5])
        XCTAssertEqual(u.first?.unlocks, DogLevel.unlocks(2, cfg))
        // После 30 открытия не на каждом уровне: 31–34 — прибавки, 35, 36…
        XCTAssertEqual(LevelInfo.upcoming(after: 30, count: 2, cfg).map(\.level), [31, 32])
        XCTAssertEqual(LevelInfo.upcoming(after: 39, cfg).map(\.level), [40])
        XCTAssertTrue(LevelInfo.upcoming(after: 40, cfg).isEmpty)
        XCTAssertEqual(LevelInfo.rewardText(5, cfg), "+100 🪙 · +5 ✂️")
        XCTAssertEqual(LevelInfo.rewardText(7, cfg), "+140 🪙")
    }

    // MARK: рост

    func testGrowthLine() {
        let cfg = GrowthConfig()
        var f = iFile()
        XCTAssertEqual(LevelInfo.growthRate(f, cfg), cfg.legacyPerDay)
        XCTAssertEqual(LevelInfo.growthDays(f, cfg), Int((10 / cfg.legacyPerDay).rounded(.up)))
        XCTAssertEqual(LevelInfo.growthLine(f, cfg), "Щенок · примерно 12 дней до подростка")
        f.growth.points = 9.5
        XCTAssertEqual(LevelInfo.growthLine(f, cfg), "Щенок · примерно 1 день до подростка")
        f.growth.points = 34
        f.growth.last = GrowthDay(d: 1, g: 0.5, h: 0, n: 0, v: false, home: 1)
        XCTAssertEqual(LevelInfo.growthLine(f, cfg), "Подросток · примерно 2 дня до взрослого")
        f.growth.points = 35
        XCTAssertEqual(LevelInfo.growthLine(f, cfg), "Взрослый")
        XCTAssertNil(LevelInfo.growthDays(f, cfg))
        // Совсем плохой день не делает прогноз бесконечным: не меньше base.
        f.growth.points = 0
        f.growth.last = GrowthDay(d: 1, g: 0, h: 0, n: 0, v: false, home: 0)
        XCTAssertEqual(LevelInfo.growthRate(f, cfg), cfg.base)
        for ph in GrowthPhase.allCases { XCTAssertFalse(LevelInfo.perksLine(ph).isEmpty) }
        XCTAssertEqual(LevelInfo.grewText(.teen), "Подрос! Теперь подросток")
        XCTAssertEqual(LevelInfo.grewText(.adult), "Вырос! Совсем взрослый")
    }

    // MARK: VoiceOver (волна 36 O)

    /// Лист «Уровень» читается словами: без «·», «/», 🪙 ✂️; рост — с подписью «Рост» и тем, что даёт стадия.
    func testSpeechReadsWords() {
        let cfg = GrowthConfig()
        var f = iFile()
        XCTAssertEqual(LevelInfo.growthSpeech(f, cfg),
                       "Рост. Щенок, примерно 12 дней до подростка. Учит только «Сидеть» и «Лежать», быстрее устаёт")
        f.growth.points = 35
        XCTAssertEqual(LevelInfo.growthSpeech(f, cfg), "Рост. Взрослый. Иногда приносит две находки, меньше ест")
        // Видимая строка не изменилась (на неё смотрят UI-тесты: «Щенок» в level.growth).
        XCTAssertEqual(LevelInfo.growthLine(iFile(), cfg), "Щенок · примерно 12 дней до подростка")
        XCTAssertTrue(LevelInfo.growthSpeech(iFile(), cfg).contains("Щенок"))

        XCTAssertEqual(LevelInfo.xpSpeech(LevelProgress(level: 7, xp: 1000, into: 320, need: 430)), "Опыт: 320 из 430")
        XCTAssertEqual(LevelInfo.xpSpeech(LevelProgress(level: 40, xp: 9999, into: 0, need: 0)),
                       "Это предел — выше уровней нет")

        XCTAssertEqual(LevelInfo.rewardSpeech(coins: 160, shards: 0), "Награда: 160 монет")
        XCTAssertEqual(LevelInfo.rewardSpeech(coins: 201, shards: 5), "Награда: 201 монета и 5 клочков")
        XCTAssertEqual(LevelInfo.rewardSpeech(coins: 22, shards: 1), "Награда: 22 монеты и 1 клочок")

        XCTAssertEqual(LevelInfo.sourceSpeech(XpSource(title: "Покормить", xp: 8, perDay: 1)), "Покормить: 8 опыта, раз в день")
        XCTAssertEqual(LevelInfo.sourceSpeech(XpSource(title: "Погладить", xp: 1, perDay: 10)), "Погладить: 1 опыт, 10 раз в день")
        XCTAssertEqual(LevelInfo.sourceSpeech(XpSource(title: "Прогулка", xp: 12, perDay: 0)), "Прогулка: 12 опыта")

        let u = [LevelUnlock(kind: .feature, id: "a", text: "Челлендж дня"), LevelUnlock(kind: .item, id: "b", text: "Мячик")]
        let r = DogLevel.reward(11)
        XCTAssertEqual(LevelInfo.rowSpeech(level: 11, unlocks: u),
                       "Уровень 11: Челлендж дня, Мячик. " + LevelInfo.rewardSpeech(coins: r.coins, shards: r.shards))
        XCTAssertEqual(LevelInfo.rowSpeech(level: 11, unlocks: []),
                       "Уровень 11. " + LevelInfo.rewardSpeech(coins: r.coins, shards: r.shards))

        // Всё, что лист реально покажет, — без значков и разделителей.
        var said = [LevelInfo.growthSpeech(iFile(), cfg)] + LevelInfo.sources().map(LevelInfo.sourceSpeech)
        for step in LevelInfo.upcoming(after: 1) { said.append(LevelInfo.rowSpeech(level: step.level, unlocks: step.unlocks)) }
        for line in said {
            for bad in ["·", "🪙", "✂️", "+"] { XCTAssertFalse(line.contains(bad), "\(line) содержит \(bad)") }
        }
    }

    // MARK: сцена нового уровня

    func testSummaryOneAndMany() throws {
        let cfg = DogLevelConfig()
        XCTAssertNil(LevelInfo.summary(after: 3, upTo: 3, cfg))
        XCTAssertNil(LevelInfo.summary(after: 4, upTo: 3, cfg))

        let one = try XCTUnwrap(LevelInfo.summary(after: 2, upTo: 3, cfg))
        XCTAssertEqual(LevelInfo.star(one), "★3")
        XCTAssertEqual(LevelInfo.toast(one), "Уровень 3! +60 🪙")
        XCTAssertEqual(LevelInfo.unlockText(one.unlocks), "Открылось: Блок Дуо, В лавке редкие вещи")

        let many = try XCTUnwrap(LevelInfo.summary(after: 3, upTo: 6, cfg))
        XCTAssertEqual(many.coins, 80 + 100 + 120)
        XCTAssertEqual(many.shards, 5)
        XCTAssertEqual(LevelInfo.star(many), "★6")
        XCTAssertEqual(LevelInfo.toast(many), "Уровни 4–6! +300 🪙 · +5 ✂️")
        XCTAssertEqual(many.unlocks.count, 5)
        XCTAssertEqual(LevelInfo.unlockText(many.unlocks), "Открылось: Дворик, Косточковая грядка, Прачечная 24/7 и ещё 2")
        XCTAssertNil(LevelInfo.unlockText([]))
    }

    func testSummaryMatchesSettleRewards() {
        // Сколько дал settle — столько и пишет сводка.
        var f = iFile()
        let coins0 = f.econ.wallet.coins, shards0 = f.econ.wallet.shards
        let seen = f.level.paidLevel
        f.level.xp = DogLevel.xpTo(6)
        let out = DogLevel.settle(&f, now: iT0 + 5)
        XCTAssertEqual(out.ups.map(\.level), [2, 3, 4, 5, 6])
        let s = LevelInfo.summary(after: seen, upTo: f.level.paidLevel)
        XCTAssertEqual(s?.coins, f.econ.wallet.coins - coins0)
        XCTAssertEqual(s?.shards, f.econ.wallet.shards - shards0)
    }

    func testXpPop() {
        XCTAssertEqual(LevelInfo.xpPop(5), "+5 опыта")
        XCTAssertEqual(LevelInfo.xpPop(1), "+1 опыт")
        XCTAssertEqual(LevelInfo.xpPop(21), "+21 опыт")
    }

    // MARK: голос

    func testVoicePitch() {
        let base = SoundRecipe.tones(.yip)
        XCTAssertEqual(GrowthVoice.apply(base, pitch: 1, crack: 0, roll: 0), base, "взрослый как был")
        let pup = GrowthVoice.apply(base, pitch: 1.35, crack: 0, roll: 0)
        XCTAssertEqual(pup.count, base.count)
        for (a, b) in zip(pup, base) {
            XCTAssertEqual(a.freq, b.freq * 1.35, accuracy: 1e-9)
            XCTAssertEqual(a.glideTo, b.glideTo * 1.35, accuracy: 1e-9)
            XCTAssertEqual(a.at, b.at)
            XCTAssertEqual(a.env, b.env)
        }
        // Безумное число из конфига прижимается.
        let wild = GrowthVoice.apply(base, pitch: 9, crack: 0, roll: 0)
        XCTAssertEqual(wild.first?.freq ?? 0, (base.first?.freq ?? 0) * 2, accuracy: 1e-9)
        XCTAssertEqual(GrowthVoice.apply(base, pitch: .nan, crack: 0, roll: 0), base)
    }

    func testVoiceCrack() {
        let base = SoundRecipe.tones(.yip)
        XCTAssertEqual(GrowthVoice.apply(base, pitch: 1, crack: 0.3, roll: 0.5), base, "бросок мимо — не сорвался")
        let broke = GrowthVoice.apply(base, pitch: 1, crack: 0.3, roll: 0.1)
        for (a, b) in zip(broke, base) where b.wave != .noise {
            XCTAssertGreaterThan(a.freq, b.freq, "начинает выше")
            XCTAssertLessThan(a.glideTo, b.glideTo, "и проваливается ниже")
            XCTAssertGreaterThan(a.glide, 0)
        }
    }

    // MARK: память

    func testGrowMemory() {
        var f = SaveFile.fresh(now: iT0)
        f.owner.tzOffsetMin = 0
        Memories.update(&f)
        f.log("growth.phase", t: iT0 + 100, key: "teen")
        f.log("growth.phase", t: iT0 + 200, key: "teen")
        Memories.update(&f)
        f.log("growth.phase", t: iT0 + 300, key: "adult")
        Memories.update(&f)
        XCTAssertEqual(f.memories["grow.teen"]?.t, iT0 + 100, "одна запись на стадию")
        XCTAssertNotNil(f.memories["grow.adult"])
        XCTAssertEqual(f.memories.items.filter { $0.kind == "grow" }.count, 2)
        let album = Memories.album(f)
        XCTAssertEqual(album.first?.text, "Вырос — совсем взрослый")
        XCTAssertEqual(album.first?.emoji, "📏")
        XCTAssertTrue(album.contains { $0.text == "Подрос — уже подросток" })
        XCTAssertNil(Memories.line(Memory(id: "grow.teen", t: 0, key: "teen")), "вслух не вспоминает")
    }
}
