// «Блок Дуо» (BlockDuo.swift): фигуры и раздача от сида, постановка, линии, комбо, пустое поле, ход Шибы
// (лучшее место, пропуск), конец партии, автопилот; монеты с убыванием, своим и общим потолком мини-игр
// (вместе с «Лови мячик»), рекорд, настроение ядерным play, поля сейва верхним уровнем и переход к новому щенку.
// Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

/// Местный полдень рядом с 1_760_000_000: днём пёс не спит.
private let bT0: Double = {
    let t: Double = 1_760_000_000
    let off = Double(Clock.tzOffsetMin(at: t)) * 60
    return ((t + off) / 86400).rounded(.down) * 86400 + 12 * 3600 - off
}()

private func bFile(at t: Double = bT0, level: Double = 60) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = "blockduo-pet-1"
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    return f
}

/// Конфиг с явными цифрами — тесты не зависят от правок economy.json.
private func bCfg(cap: Int = 60, shared: Int = 60) -> BlockDuoConfig {
    var c = BlockDuoConfig()
    c.base = 5
    c.max = 40
    c.parScore = 1500
    c.dailyCap = cap
    c.sharedCap = shared
    c.diminishing = [.init(from: 1, x: 1), .init(from: 7, x: 0.5), .init(from: 13, x: 0.2)]
    return c
}

/// Поле из 8 строк: «.» пусто, «#» клетка хозяина, «S» клетка Шибы.
private func grid(_ rows: [String]) -> [UInt8] {
    precondition(rows.count == 8)
    return rows.flatMap { row -> [UInt8] in
        precondition(row.count == 8)
        return row.map { $0 == "#" ? 1 : ($0 == "S" ? BlockDuo.shibaColor : 0) }
    }
}

private let empty = Array(repeating: "........", count: 8)
/// Шахматка: ни двух пустых клеток рядом, ни одной полной линии.
private let checker = (0..<8).map { r in String((0..<8).map { c in (r + c) % 2 == 0 ? "#" : "." }) }

private func single(_ color: UInt8 = 2) -> BlockPiece { BlockPiece(shape: 0, color: color) }
private func cell(_ r: Int, _ c: Int) -> BlockCell { BlockCell(r: r, c: c) }

final class BlockDuoTests: XCTestCase {

    // MARK: фигуры и раздача

    func testShapesAsInWebVersion() {
        XCTAssertEqual(BlockDuo.shapes.count, 37)
        XCTAssertEqual(BlockDuo.totalWeight, 42, accuracy: 1e-9, "веса как в public/app.js")
        for s in BlockDuo.shapes {
            XCTAssertFalse(s.cells.isEmpty)
            XCTAssertLessThanOrEqual(s.w, 5)
            XCTAssertLessThanOrEqual(s.h, 5)
            XCTAssertEqual(s.cells.map(\.c).max(), s.w - 1, "рамка по клеткам")
            XCTAssertEqual(s.cells.map(\.r).max(), s.h - 1)
        }
        XCTAssertEqual(BlockDuo.shapes[10].cells.count, 9, "квадрат 3×3")
        XCTAssertEqual(BlockDuo.shapes[13].cells, [cell(0, 0), cell(0, 1), cell(1, 0)])
        for s in BlockDuo.shibaShapes {
            XCTAssertLessThanOrEqual(BlockDuo.shapes[s.shape].cells.count, 4, "у Шибы фигуры маленькие")
        }
    }

    func testDealIsDeterministicWithThreeColors() {
        for round in 0..<30 {
            let a = BlockDuo.deal(seed: 42, round: round)
            XCTAssertEqual(a, BlockDuo.deal(seed: 42, round: round), "один сид и номер — одна тройка")
            XCTAssertEqual(a.count, 3)
            XCTAssertEqual(Set(a.map(\.color)).count, 3, "три разных цвета")
            for p in a {
                XCTAssertTrue((1...8).contains(p.color))
                XCTAssertTrue(BlockDuo.shapes.indices.contains(p.shape))
            }
        }
        let rounds = (0..<20).map { BlockDuo.deal(seed: 42, round: $0) }
        XCTAssertGreaterThan(Set(rounds).count, 15, "тройки меняются от раунда к раунду")
        XCTAssertNotEqual((0..<5).map { BlockDuo.deal(seed: 43, round: $0) }, Array(rounds.prefix(5)))
        // Все фигуры выпадают, большие реже маленьких.
        var seen = [Int](repeating: 0, count: BlockDuo.shapes.count)
        for r in 0..<2000 { for p in BlockDuo.deal(seed: 9, round: r) { seen[p.shape] += 1 } }
        XCTAssertTrue(seen.allSatisfy { $0 > 0 })
        XCTAssertGreaterThan(seen[9], seen[7] * 2, "квадрат 2×2 (вес 4) чаще палки на 5 (вес 1)")
    }

    func testShibaPieceIsDeterministicAndSmall() {
        let shiba = Set(BlockDuo.shibaShapes.map(\.shape))
        var kinds = Set<Int>()
        for turn in 0..<300 {
            let p = BlockDuo.shibaPiece(seed: 5, turn: turn)
            XCTAssertEqual(p, BlockDuo.shibaPiece(seed: 5, turn: turn))
            XCTAssertEqual(p.color, BlockDuo.shibaColor)
            XCTAssertTrue(shiba.contains(p.shape))
            kinds.insert(p.shape)
        }
        XCTAssertEqual(kinds, shiba, "все щенячьи фигуры выпадают")
    }

    // MARK: постановка и линии

    func testPlaceScoresCellsAndRefusesBadSpots() throws {
        var g = BlockDuoGame(seed: 1, board: grid(empty), tray: [BlockPiece(shape: 9, color: 3), single(), single(4)])
        XCTAssertNil(g.preview(slot: 0, at: cell(7, 7)), "2×2 за край не встаёт")
        XCTAssertNil(g.place(slot: 0, at: cell(-1, 0)))
        let t = try XCTUnwrap(g.place(slot: 0, at: cell(2, 3)))
        XCTAssertEqual(t.mine.gained, 4, "клетка — очко")
        XCTAssertEqual(t.mine.cells, [19, 20, 27, 28])
        XCTAssertNil(t.shiba)
        XCTAssertFalse(t.dealt)
        XCTAssertEqual(g.score, 4)
        XCTAssertEqual(g.mine, 4)
        XCTAssertNil(g.tray[0], "поставленная фигура уходит из тройки")
        XCTAssertNil(g.place(slot: 0, at: cell(5, 5)), "пустой слот")
        XCTAssertNil(g.place(slot: 1, at: cell(2, 3)), "на занятое нельзя")
        XCTAssertEqual(g.board[19], 3, "цвет фигуры")
        XCTAssertEqual(g.moves, 1)
    }

    func testRowAndColumnClearTogether() throws {
        var rows = empty
        rows[0] = "#######."
        for r in 1..<8 { rows[r] = ".......#" }
        rows[5] = "...#...#"
        var g = BlockDuoGame(seed: 1, board: grid(rows), tray: [single(), single(), single()])
        let pv = try XCTUnwrap(g.preview(slot: 0, at: cell(0, 7)))
        XCTAssertEqual(pv.rows, [0])
        XCTAssertEqual(pv.cols, [7])
        XCTAssertEqual(pv.clearing.count, 15)
        let t = try XCTUnwrap(g.place(slot: 0, at: cell(0, 7)))
        XCTAssertEqual(t.mine.rows, [0])
        XCTAssertEqual(t.mine.cols, [7])
        XCTAssertEqual(t.mine.cleared.count, 15)
        XCTAssertEqual(t.mine.gained, 1 + 40 * 2 * 3, "две линии сразу — 240")
        XCTAssertFalse(t.mine.perfect)
        XCTAssertEqual(t.mine.placed[7], 2, "до очистки клетка видна")
        XCTAssertEqual(g.board.filter { $0 != 0 }.count, 1, "осталась одна клетка")
        XCTAssertEqual(g.lines, 2)
        XCTAssertEqual(g.combo, 1)
    }

    func testComboGrowsAndPerfectBoardBonus() throws {
        var rows = empty
        rows[0] = "#######."
        rows[1] = "#######."
        rows[2] = "#######."
        var g = BlockDuoGame(seed: 3, board: grid(rows), tray: [single(), single(), single()])
        XCTAssertEqual(g.place(slot: 0, at: cell(0, 7))?.mine.gained, 1 + 80)
        XCTAssertEqual(g.place(slot: 1, at: cell(1, 7))?.mine.gained, 1 + 160, "комбо ×2")
        let t = try XCTUnwrap(g.place(slot: 2, at: cell(2, 7)))
        XCTAssertEqual(t.mine.combo, 3)
        XCTAssertTrue(t.mine.perfect, "поле опустело")
        XCTAssertEqual(t.mine.gained, 1 + 240 + BlockDuo.perfectBonus)
        XCTAssertGreaterThanOrEqual(g.maxCombo, 3)
    }

    func testComboFadesAfterThreeMovesWithoutLines() throws {
        var rows = empty
        rows[0] = "#######."
        rows[7] = "#......."
        var g = BlockDuoGame(seed: 3, board: grid(rows), tray: [single(), single(), single()])
        _ = g.place(slot: 0, at: cell(0, 7))
        XCTAssertEqual(g.combo, 1)
        _ = g.place(slot: 1, at: cell(4, 0))
        XCTAssertEqual(g.combo, 1, "один ход без линий — комбо держится")
        let t = try XCTUnwrap(g.place(slot: 2, at: cell(4, 2)))
        // Третий ход без линий — ход Шибы на почти пустом поле: линий у него не будет.
        XCTAssertEqual(t.shiba?.lines ?? 0, 0)
        XCTAssertEqual(g.combo, 0, "три хода без линий (третий — Шибы) гасят комбо")
    }

    // MARK: Шиба

    func testShibaPicksSpotThatClearsLine() {
        var rows = empty
        rows[3] = "#####..#"
        rows[6] = "#....#.."
        let b = grid(rows)
        XCTAssertEqual(BlockDuo.shibaSpot(BlockPiece(shape: 1, color: BlockDuo.shibaColor), on: b), cell(3, 5))
        // Вертикальная палка на 2 строку не закроет — тогда плотнее к занятому и к стенке.
        let v = BlockDuo.shibaSpot(BlockPiece(shape: 2, color: BlockDuo.shibaColor), on: b)
        XCTAssertNotNil(v)
        XCTAssertNil(BlockDuo.shibaSpot(BlockPiece(shape: 9, color: BlockDuo.shibaColor), on: grid(checker)),
                     "2×2 на шахматку не встаёт")
        // Одна клетка в шахматке — первое сверху слева.
        XCTAssertEqual(BlockDuo.shibaSpot(single(BlockDuo.shibaColor), on: grid(checker)), cell(0, 1))
    }

    func testShibaMovesAfterThirdPieceThenNewTray() throws {
        var g = BlockDuoGame(seed: 11, board: grid(empty), tray: [single(), nil, nil])
        let t = try XCTUnwrap(g.place(slot: 0, at: cell(0, 0)))
        let s = try XCTUnwrap(t.shiba, "на пустом поле Шибе место есть")
        XCTAssertEqual(s.who, .shiba)
        XCTAssertEqual(s.piece, BlockDuo.shibaPiece(seed: 11, turn: 0))
        XCTAssertTrue(s.cells.allSatisfy { g.board[$0] == BlockDuo.shibaColor }, "его клетки — его цветом")
        XCTAssertEqual(g.lastShiba, s)
        XCTAssertEqual(g.shiba, s.gained)
        XCTAssertEqual(g.score, g.mine + g.shiba, "счёт общий")
        XCTAssertTrue(t.dealt)
        XCTAssertEqual(g.round, 1)
        XCTAssertEqual(g.tray, BlockDuo.deal(seed: 11, round: 1).map(Optional.some))
        XCTAssertEqual(g.shibaTurns, 1)
    }

    func testShibaSkipsWhenNoRoomButGameGoesOn() throws {
        // Сид, где у Шибы фигура больше клетки, а в новой тройке есть одиночка: шахматка его не пускает, тебя — да.
        let seed = try XCTUnwrap((1...2000).map(UInt64.init).first { s in
            BlockDuo.shibaPiece(seed: s, turn: 0).shape != 0 && BlockDuo.deal(seed: s, round: 1).contains { $0.shape == 0 }
        })
        var g = BlockDuoGame(seed: seed, board: grid(checker), tray: [single(), nil, nil])
        let t = try XCTUnwrap(g.place(slot: 0, at: cell(0, 1)))
        XCTAssertNil(t.shiba)
        XCTAssertTrue(t.shibaSkipped)
        XCTAssertNil(g.lastShiba)
        XCTAssertFalse(t.over, "пропуск Шибы — не конец игры")
        XCTAssertFalse(g.isOver)
        XCTAssertEqual(g.shibaTurns, 1, "ход Шибы всё равно засчитан: следующая фигура — новая")
    }

    func testGameOverWhenNothingFits() {
        var g = BlockDuoGame(seed: 1, board: grid(checker), tray: [BlockPiece(shape: 9, color: 1), BlockPiece(shape: 1, color: 2), nil])
        XCTAssertTrue(g.isOver)
        XCTAssertFalse(g.anyFits)
        XCTAssertNil(g.place(slot: 1, at: cell(0, 1)))
        let fresh = BlockDuoGame(seed: 1)
        XCTAssertFalse(fresh.isOver)
        XCTAssertEqual(fresh.tray, BlockDuo.deal(seed: 1, round: 0).map(Optional.some))
        XCTAssertTrue(fresh.isEmpty)
    }

    // MARK: автопилот

    func testAutoplayIsDeterministicAndEnds() {
        let a = BlockDuo.autoplay(seed: 77)
        XCTAssertEqual(a, BlockDuo.autoplay(seed: 77), "один сид — одна партия")
        XCTAssertTrue(a.isOver)
        XCTAssertNil(BlockDuo.pilotMove(a))
        XCTAssertEqual(a.score, a.mine + a.shiba)
        XCTAssertGreaterThan(a.moves, 10)
        XCTAssertGreaterThan(a.lines, 0)
        XCTAssertGreaterThan(a.shibaTurns, 2)
        let mid = BlockDuo.autoplay(seed: 77, moves: 7)
        XCTAssertEqual(mid.moves, 7)
        XCTAssertEqual(mid.shibaTurns, 2, "после 6 фигур Шиба сходил дважды")
        XCTAssertFalse(mid.isOver)
        XCTAssertNotEqual(BlockDuo.autoplay(seed: 78), a)
    }

    func testShibaHelpsInTypicalGames() {
        // На двадцати партиях Шиба хоть иногда закрывает линии сам — «дуо» не для галочки.
        var shibaLines = 0, scores: [Int] = []
        for s in 1...20 {
            let g = BlockDuo.autoplay(seed: UInt64(s))
            shibaLines += g.shibaLines
            scores.append(g.score)
        }
        XCTAssertGreaterThan(shibaLines, 5)
        // Автопилот жадный и играет сильнее человека: par_score в economy.json ниже его обычной партии,
        // чтобы и живой игрок за хорошую партию дотягивался до max.
        XCTAssertLessThan(BlockDuoConfig.shared.parScore, scores.sorted()[10])
    }

    // MARK: награда

    func testFinishPaysRecordAndPlay() {
        var f = bFile()
        let fun = f.pet.needs[.fun] ?? 0
        let g = BlockDuo.autoplay(seed: 3)
        let c = bCfg(cap: 500, shared: 500)
        let r = BlockDuo.finish(g, in: &f, now: bT0, c)
        XCTAssertEqual(r.score, g.score)
        XCTAssertEqual(r.coins, CatchGame.want(score: g.score, game: 1, c.asCatch))
        XCTAssertTrue(r.isRecord)
        XCTAssertEqual(f.blockduoBest, g.score)
        XCTAssertEqual(f.blockduoGames, 1)
        XCTAssertEqual(f.blockduoCoins, r.coins)
        XCTAssertTrue(r.played)
        XCTAssertGreaterThan(f.pet.needs[.fun] ?? 0, fun, "настроение — ядерным play")
        // Вторая партия хуже — рекорд стоит.
        let worse = BlockDuo.autoplay(seed: 3, moves: 3)
        let r2 = BlockDuo.finish(worse, in: &f, now: bT0 + 60, c)
        XCTAssertFalse(r2.isRecord)
        XCTAssertEqual(r2.best, g.score)
        XCTAssertEqual(f.blockduoGames, 2)
    }

    func testWantScalesToParAndDiminishes() {
        let c = bCfg().asCatch
        XCTAssertEqual(CatchGame.want(score: 0, game: 1, c), 0)
        XCTAssertEqual(CatchGame.want(score: 1500, game: 1, c), 40, "конфиг теста — par 1500")
        XCTAssertEqual(CatchGame.want(score: 9000, game: 1, c), 40, "выше par — не больше max")
        XCTAssertEqual(CatchGame.want(score: 750, game: 1, c), 23)
        XCTAssertEqual(CatchGame.want(score: 1500, game: 7, c), 20)
        XCTAssertEqual(CatchGame.want(score: 1500, game: 13, c), 8)
    }

    func testOwnDailyCapAndNextDay() {
        var f = bFile()
        let g = BlockDuo.autoplay(seed: 3)
        var total = 0
        for i in 0..<6 { total += BlockDuo.finish(g, in: &f, now: bT0 + Double(i) * 60, bCfg(cap: 50, shared: 500)).coins }
        XCTAssertEqual(total, 50, "не больше своего потолка")
        XCTAssertEqual(BlockDuo.coinsLeft(f, now: bT0 + 600, bCfg(cap: 50, shared: 500)), 0)
        let r = BlockDuo.finish(g, in: &f, now: bT0 + 900, bCfg(cap: 50, shared: 500))
        XCTAssertEqual(r.coins, 0)
        XCTAssertTrue(r.capped)
        XCTAssertEqual(BlockDuo.rewardText(r), r.careCoins > 0 ? "+\(EconText.coins(r.careCoins))" : "На сегодня монет за игры хватит")
        XCTAssertEqual(BlockDuo.coinsLeft(f, now: bT0 + 86400, bCfg(cap: 50, shared: 500)), 50, "завтра снова")
    }

    func testSharedCapWithCatch() {
        var f = bFile()
        f.catchDay = Economy.day(bT0)
        f.catchCoins = 50
        XCTAssertEqual(BlockDuo.coinsLeft(f, now: bT0, bCfg()), 10, "мячик уже взял 50 из общих 60")
        let r = BlockDuo.finish(BlockDuo.autoplay(seed: 3), in: &f, now: bT0, bCfg())
        XCTAssertEqual(r.coins, 10)
        XCTAssertTrue(r.capped)
        XCTAssertEqual(MiniGames.coinsToday(f, now: bT0), 60)
        // И наоборот: «Лови мячик» видит монеты «Блок Дуо».
        var cc = CatchConfig()
        cc.dailyCap = 60
        cc.sharedCap = 60
        XCTAssertEqual(CatchGame.coinsLeft(f, now: bT0, cc), 0)
        let cr = CatchGame.finish(score: 30, in: &f, now: bT0 + 60, cc)
        XCTAssertEqual(cr.coins, 0)
        XCTAssertTrue(cr.capped)
        // Вчерашнее не в счёт.
        var y = bFile()
        y.blockduoDay = Economy.day(bT0) - 1
        y.blockduoCoins = 60
        XCTAssertEqual(MiniGames.coinsToday(y, now: bT0), 0)
        XCTAssertEqual(CatchGame.coinsLeft(y, now: bT0, cc), 60)
        XCTAssertEqual(BlockDuo.coinsLeft(y, now: bT0, bCfg()), 60)
    }

    func testZeroScoreCountsGameWithoutPlay() {
        var f = bFile()
        let fun = f.pet.needs[.fun]
        let r = BlockDuo.finish(BlockDuoGame(seed: 1), in: &f, now: bT0, bCfg())
        XCTAssertEqual(r.coins, 0)
        XCTAssertFalse(r.capped)
        XCTAssertFalse(r.played)
        XCTAssertFalse(r.isRecord)
        XCTAssertNil(BlockDuo.rewardText(r))
        XCTAssertEqual(f.pet.needs[.fun], fun)
        XCTAssertEqual(f.blockduoGames, 1)
    }

    func testFinishAfterDeathPaysNothing() {
        // Волна 13: партия кончилась уже после смерти — без монет, рекорд остаётся.
        var f = bFile()
        f.pet.alive = false
        let coins = f.econ.wallet.coins
        let r = BlockDuo.finish(BlockDuo.autoplay(seed: 3, moves: 4), in: &f, now: bT0, bCfg())
        XCTAssertGreaterThan(r.score, 0)
        XCTAssertEqual(r.totalCoins, 0)
        XCTAssertFalse(r.capped)
        XCTAssertNil(BlockDuo.rewardText(r))
        XCTAssertEqual(f.econ.wallet.coins, coins)
        XCTAssertEqual(f.blockduoCoins, 0)
        XCTAssertFalse(r.played)
        XCTAssertEqual(f.blockduoBest, r.score)
    }

    func testFinishWhileAsleepKeepsRecordWithoutPlay() {
        var f = bFile()
        f.pet.napUntil = bT0 + 1800
        XCTAssertEqual(BlockDuo.gate(f, at: bT0), "asleep")
        let r = BlockDuo.finish(BlockDuo.autoplay(seed: 3, moves: 4), in: &f, now: bT0, bCfg())
        XCTAssertFalse(r.played)
        XCTAssertEqual(r.reason, "asleep")
        XCTAssertGreaterThan(f.blockduoBest, 0)
    }

    func testTexts() {
        var r = BlockDuoResult()
        XCTAssertEqual(BlockDuo.resultTitle(r), "Даже не начали…")
        XCTAssertFalse(BlockDuo.shibaLine(r).isEmpty)
        r.score = 900; r.mine = 800; r.shiba = 100; r.best = 1200
        XCTAssertEqual(BlockDuo.resultTitle(r), "Места больше нет!")
        XCTAssertEqual(BlockDuo.shibaLine(r), BlockDuo.shibaLine(r), "одна партия — одна фраза")
        r.isRecord = true
        XCTAssertEqual(BlockDuo.resultTitle(r), "Новый рекорд!")
        XCTAssertTrue(BlockDuo.shibaLine(r).contains("900"))
        r.coins = 12; r.careCoins = 3
        XCTAssertEqual(BlockDuo.rewardText(r), "+\(EconText.coins(15))")
    }

    // MARK: сейв и конфиг

    func testSaveFieldsTopLevelAndOldSave() throws {
        var f = bFile()
        BlockDuo.finish(BlockDuo.autoplay(seed: 3), in: &f, now: bT0, bCfg())
        let data = try JSONEncoder().encode(f)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((obj["blockduoBest"] as? NSNumber)?.intValue, f.blockduoBest, "рекорд — верхним уровнем")
        XCTAssertNotNil(obj["blockduoDay"])
        XCTAssertNotNil(obj["blockduoCoins"])
        let back = try JSONDecoder().decode(SaveFile.self, from: data)
        XCTAssertEqual(back.blockduoBest, f.blockduoBest)
        XCTAssertEqual(back.blockduoDay, f.blockduoDay)
        XCTAssertEqual(back.blockduoCoins, f.blockduoCoins)
        XCTAssertEqual(back.blockduoGames, 1)

        // Старый сейв без полей — нули, остальное на месте.
        var plain = f
        plain.blockduoBest = 0; plain.blockduoDay = 0; plain.blockduoCoins = 0; plain.blockduoGames = 0
        let oldData = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("\"blockduoBest\""))
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("\"blockduoGames\""))
        let oldFile = try JSONDecoder().decode(SaveFile.self, from: oldData)
        XCTAssertEqual(oldFile.blockduoBest, 0)
        XCTAssertEqual(oldFile.petId, f.petId)
        XCTAssertEqual(oldFile.econ.wallet, f.econ.wallet)

        // Битое поле — ноль, а не весь сейв.
        let text = String(decoding: oldData, as: UTF8.self)
        let broken = "{\"blockduoBest\":\"много\",\"blockduoGames\":2," + text.dropFirst()
        let b = try JSONDecoder().decode(SaveFile.self, from: Data(broken.utf8))
        XCTAssertEqual(b.blockduoBest, 0)
        XCTAssertEqual(b.blockduoGames, 2)
        XCTAssertEqual(b.petId, f.petId)

        let fresh = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SaveFile.fresh(now: bT0))) as? [String: Any]
        XCTAssertNil(fresh?["blockduoBest"])
        XCTAssertNil(fresh?["blockduoGames"])
    }

    func testStartOverKeepsRecordAndDailyCap() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-blockduo")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: bT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.blockduoBest = 3210
            f.blockduoDay = Economy.day(bT0)
            f.blockduoCoins = 60
            f.blockduoGames = 4
        }
        try store.startOver(now: bT0 + 100)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.blockduoBest, 3210, "рекорд хозяина остаётся")
        XCTAssertEqual(f.blockduoCoins, 60, "новым щенком потолок не обнулить")
        XCTAssertEqual(f.blockduoDay, Economy.day(bT0))
        XCTAssertEqual(f.blockduoGames, 4)
    }

    func testConfigFromEconomyJSON() {
        let d = BlockDuoConfig(json: .null)
        XCTAssertEqual(d.name, "Блок Дуо")
        XCTAssertEqual(d.sharedCap, MiniGames.defaultSharedCap)

        let s = BlockDuoConfig.shared
        XCTAssertEqual(s.name, "Блок Дуо")
        XCTAssertGreaterThan(s.base, 0)
        XCTAssertGreaterThanOrEqual(s.max, s.base)
        XCTAssertLessThanOrEqual(s.max, s.dailyCap, "одна партия не выбирает больше дневного потолка")
        XCTAssertGreaterThan(s.sharedCap, 0)
        XCTAssertEqual(s.sharedCap, CatchConfig.shared.sharedCap, "общий потолок один на обе игры")
        XCTAssertEqual(s.diminishing, CatchConfig.shared.diminishing, "убывание общее")
        XCTAssertEqual(s.asCatch.parScore, s.parScore)
        XCTAssertEqual(BlockDuo.reactKind, "blockduo")
    }
}
