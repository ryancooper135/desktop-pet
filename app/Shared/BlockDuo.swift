// Мини-игра «Блок Дуо» (волна 12): Block Blast на двоих с Шибой. Поле 8×8, внизу три фигуры; ставишь все три —
// Шиба ставит одну свою, маленькую, и приходит новая тройка. Заполненные строки и столбцы исчезают.
// Счёт общий: игра не против Шибы, а вместе с ним (вечером «сыграли вдвоём», а не «он у тебя выиграл»).
//
// Здесь только логика без экрана (BlockDuoScreen.swift рисует):
// • правила и фигуры — как у веб-версии (C:\Users\ryanc\block-duo, public/app.js): те же 37 фигур и веса,
//   1 очко за клетку, 40·n·(n+1)·комбо за n линий, +500 за пустое поле; комбо гаснет после трёх ходов без линий;
// • тройка зависит только от сида и номера тройки, фигура Шибы — от сида и номера его хода: один сид — одна партия
//   при тех же ходах (UI-снимки, тесты). Генератор — CatchRandom (SplitMix64), как у «Лови мячик»;
// • Шиба ходит сам (простой ИИ): место, где больше всего линий исчезнет; поровну — где фигура плотнее прилегает
//   к занятым клеткам и стенкам; дальше — первое сверху слева. Не влезла никуда — пропускает ход, это не конец игры;
// • конец — когда ни одна фигура из тройки никуда не встаёт;
// • награда — как у «Лови мячик» (CatchGame.want): base…max до par_score, убывание по номеру партии за сутки,
//   бафф дома, свой дневной потолок и общий потолок мини-игр (minigames.daily_cap); настроение — ядерным play;
// • рекорд и дневные счётчики — верхним уровнем SaveFile (blockduoBest, blockduoDay, blockduoCoins, blockduoGames).

import Foundation
@preconcurrency import PetCore

// MARK: - Настройки

struct BlockDuoConfig: Hashable, Sendable {
    var name = "Блок Дуо"
    /// Монеты за партию хоть с одним очком…
    var base = 5
    /// …и за par_score очков и больше.
    var max = 40
    var parScore = 3000
    /// Потолок монет за «Блок Дуо» в местные сутки…
    var dailyCap = 60
    /// …и общий на все мини-игры (вместе с «Лови мячик»): новая игра не добавляет дохода, только выбор.
    var sharedCap = MiniGames.defaultSharedCap
    var diminishing: [CatchConfig.Step] = [.init(from: 1, x: 1), .init(from: 7, x: 0.5), .init(from: 13, x: 0.2)]

    static let shared = BlockDuoConfig(json: Catalog.economy() ?? .null)

    init() {}

    init(json e: JSONValue) {
        func int(_ v: JSONValue, _ d: Int) -> Int { v.double.map { Int($0) } ?? d }
        let g = e["minigames"]
        let c = g["list"]["blockduo"]
        name = c["name"].string ?? name
        base = int(c["base"], base)
        max = Swift.max(base, int(c["max"], max))
        parScore = Swift.max(1, int(c["par_score"], parScore))
        dailyCap = Swift.max(0, int(c["daily_cap"], dailyCap))
        sharedCap = Swift.max(0, int(g["daily_cap"], sharedCap))
        // Убывание — общая таблица мини-игр, её уже читает CatchConfig.
        diminishing = CatchConfig(json: e).diminishing
    }

    /// Те же цифры в виде CatchConfig — чтобы формула монет была одна (CatchGame.want).
    var asCatch: CatchConfig {
        var c = CatchConfig()
        c.base = base
        c.max = max
        c.parScore = parScore
        c.dailyCap = dailyCap
        c.sharedCap = sharedCap
        c.diminishing = diminishing
        return c
    }
}

// MARK: - Фигуры и поле

struct BlockCell: Hashable, Sendable {
    var r: Int
    var c: Int

    var index: Int { r * BlockDuo.size + c }
}

struct BlockShape: Hashable, Sendable {
    /// Клетки от левого верхнего угла рамки фигуры.
    let cells: [BlockCell]
    let w: Int
    let h: Int
    let weight: Double

    /// «XX\nX.» — как в веб-версии.
    init(_ pattern: String, _ weight: Double) {
        let rows = pattern.split(separator: "\n", omittingEmptySubsequences: false)
        var cells: [BlockCell] = []
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() where ch == "X" { cells.append(BlockCell(r: r, c: c)) }
        }
        self.cells = cells
        h = rows.count
        w = rows.map(\.count).max() ?? 0
        self.weight = weight
    }
}

/// Фигура в тройке или у Шибы: какая (индекс в BlockDuo.shapes) и каким цветом.
struct BlockPiece: Hashable, Sendable {
    let shape: Int
    /// 1…8 — цвета хозяина, BlockDuo.shibaColor — клетки Шибы.
    let color: UInt8

    var form: BlockShape { BlockDuo.shapes[shape] }
}

/// Один ход: кто, куда, что исчезло и сколько дал.
struct BlockMove: Hashable, Sendable {
    enum Who: Hashable, Sendable { case me, shiba }

    let who: Who
    let piece: BlockPiece
    let at: BlockCell
    /// Куда легли клетки фигуры (индексы поля).
    let cells: [Int]
    let rows: [Int]
    let cols: [Int]
    /// Исчезнувшие клетки (строки и столбцы вместе, без повторов, по возрастанию).
    let cleared: [Int]
    /// Поле сразу после постановки, до очистки: экран показывает его, пока линии мигают.
    let placed: [UInt8]
    let gained: Int
    /// Комбо после хода.
    let combo: Int
    /// Поле опустело — +500.
    let perfect: Bool

    var lines: Int { rows.count + cols.count }
}

/// Ход хозяина и, если тройка кончилась, ответный ход Шибы.
struct BlockTurn: Hashable, Sendable {
    let mine: BlockMove
    let shiba: BlockMove?
    /// Тройка кончилась, а фигуре Шибы места нет — он пропустил ход.
    let shibaSkipped: Bool
    /// Пришла новая тройка.
    let dealt: Bool
    let over: Bool
}

/// Подсветка при перетаскивании: куда ляжет фигура и какие линии исчезнут.
struct BlockPreview: Hashable, Sendable {
    let cells: [Int]
    let rows: [Int]
    let cols: [Int]

    /// Клетки, которые исчезнут, вместе с теми, что сейчас лягут.
    var clearing: Set<Int> { Set(BlockDuo.lineCells(rows: rows, cols: cols)) }
}

// MARK: - Партия

struct BlockDuoGame: Hashable, Sendable {
    let seed: UInt64
    /// 0 — пусто, 1…8 — клетки хозяина, BlockDuo.shibaColor — Шибы.
    private(set) var board: [UInt8]
    /// Три места внизу; nil — фигуру уже поставили.
    private(set) var tray: [BlockPiece?]
    /// Номер тройки (с 0).
    private(set) var round = 0
    private(set) var score = 0
    /// Чьи очки в общем счёте.
    private(set) var mine = 0
    private(set) var shiba = 0
    private(set) var combo = 0
    /// Ходов подряд без линий: на третьем комбо гаснет.
    private(set) var since = 0
    private(set) var maxCombo = 0
    private(set) var lines = 0
    /// Фигур хозяина на поле.
    private(set) var moves = 0
    /// Ходов Шибы (и пропущенных тоже): по нему выбирается его следующая фигура.
    private(set) var shibaTurns = 0
    private(set) var shibaLines = 0
    private(set) var isOver = false
    /// Последний ход Шибы: экран подсвечивает его клетки до следующего хода.
    private(set) var lastShiba: BlockMove? = nil

    init(seed: UInt64) {
        self.seed = seed
        board = Array(repeating: 0, count: BlockDuo.cells)
        tray = BlockDuo.deal(seed: seed, round: 0).map(Optional.some)
        isOver = !anyFits
    }

    /// Готовое поле и тройка — для тестов: проверить линии, комбо и ход Шибы на нужной раскладке.
    init(seed: UInt64, board: [UInt8], tray: [BlockPiece?]) {
        precondition(board.count == BlockDuo.cells && tray.count == 3)
        self.seed = seed
        self.board = board
        self.tray = tray
        isOver = !anyFits
    }

    var isEmpty: Bool { board.allSatisfy { $0 == 0 } }

    /// Встаёт ли фигура с левым верхним углом рамки в at.
    func fits(_ p: BlockPiece, at: BlockCell) -> Bool {
        BlockDuo.fits(p.form, at: at, on: board)
    }

    /// Встаёт ли фигура хоть куда-нибудь.
    func fitsAnywhere(_ p: BlockPiece) -> Bool {
        BlockDuo.spots(p.form, on: board).first != nil
    }

    /// Хоть одна фигура из тройки встаёт.
    var anyFits: Bool { tray.contains { $0.map(fitsAnywhere) ?? false } }

    /// Подсветка для фигуры slot в at; nil — сюда не встаёт.
    func preview(slot: Int, at: BlockCell) -> BlockPreview? {
        guard tray.indices.contains(slot), let p = tray[slot], fits(p, at: at) else { return nil }
        var b = board
        let cells = p.form.cells.map { BlockCell(r: at.r + $0.r, c: at.c + $0.c).index }
        for i in cells { b[i] = p.color }
        let (rows, cols) = BlockDuo.fullLines(b)
        return BlockPreview(cells: cells, rows: rows, cols: cols)
    }

    /// Поставить фигуру slot в at. nil — партия кончилась, места нет или слот пустой.
    /// Последняя из тройки — Шиба ставит свою, приходит новая тройка, проверяется конец.
    mutating func place(slot: Int, at: BlockCell) -> BlockTurn? {
        guard !isOver, tray.indices.contains(slot), let p = tray[slot], fits(p, at: at) else { return nil }
        tray[slot] = nil
        let my = put(p, at: at, who: .me)
        moves += 1
        mine += my.gained
        var reply: BlockMove? = nil
        var skipped = false
        var dealt = false
        if tray.allSatisfy({ $0 == nil }) {
            let sp = BlockDuo.shibaPiece(seed: seed, turn: shibaTurns)
            shibaTurns += 1
            if let at = BlockDuo.shibaSpot(sp, on: board) {
                let m = put(sp, at: at, who: .shiba)
                shiba += m.gained
                shibaLines += m.lines
                reply = m
                lastShiba = m
            } else {
                skipped = true
                lastShiba = nil
            }
            round += 1
            tray = BlockDuo.deal(seed: seed, round: round).map(Optional.some)
            dealt = true
        }
        isOver = !anyFits
        return BlockTurn(mine: my, shiba: reply, shibaSkipped: skipped, dealt: dealt, over: isOver)
    }

    /// Положить фигуру, убрать полные линии, посчитать очки и комбо (как в веб-версии).
    private mutating func put(_ p: BlockPiece, at: BlockCell, who: BlockMove.Who) -> BlockMove {
        let cells = p.form.cells.map { BlockCell(r: at.r + $0.r, c: at.c + $0.c).index }
        for i in cells { board[i] = p.color }
        let placed = board
        let (rows, cols) = BlockDuo.fullLines(board)
        let cleared = BlockDuo.lineCells(rows: rows, cols: cols)
        for i in cleared { board[i] = 0 }
        let n = rows.count + cols.count
        var gained = cells.count
        var perfect = false
        if n > 0 {
            combo += 1
            since = 0
            gained += 40 * n * (n + 1) * combo
            perfect = isEmpty
            if perfect { gained += BlockDuo.perfectBonus }
            lines += n
        } else {
            since += 1
            if since >= 3 { combo = 0 }
        }
        maxCombo = Swift.max(maxCombo, combo)
        score += gained
        return BlockMove(who: who, piece: p, at: at, cells: cells, rows: rows, cols: cols, cleared: cleared,
                         placed: placed, gained: gained, combo: combo, perfect: perfect)
    }
}

// MARK: - Итог

struct BlockDuoResult: Hashable, Sendable {
    var score = 0
    var mine = 0
    var shiba = 0
    var lines = 0
    var maxCombo = 0
    /// Монеты за партию (после убывания, баффа дома и потолков).
    var coins = 0
    /// Монеты ухода за «Поиграть» (ядерное действие play).
    var careCoins = 0
    /// Хотели больше, но упёрлись в потолок.
    var capped = false
    var best = 0
    var isRecord = false
    var played = false
    var reason: String?

    var totalCoins: Int { coins + careCoins }
}

enum BlockDuo {
    static let size = 8
    static let cells = size * size
    /// Цвет клеток Шибы (у хозяина 1…8).
    static let shibaColor: UInt8 = 9
    static let perfectBonus = 500
    /// Вид реакции пса в комнате после партии (AppModel.react): подпрыгнул и виляет, как после привычки.
    static let reactKind = "blockduo"

    /// Фигуры и веса веб-версии (public/app.js, SHAPE_DEFS), в том же порядке.
    static let shapes: [BlockShape] = [
        BlockShape("X", 2),
        BlockShape("XX", 2), BlockShape("X\nX", 2),
        BlockShape("XXX", 2), BlockShape("X\nX\nX", 2),
        BlockShape("XXXX", 1.5), BlockShape("X\nX\nX\nX", 1.5),
        BlockShape("XXXXX", 1), BlockShape("X\nX\nX\nX\nX", 1),
        BlockShape("XX\nXX", 4),
        BlockShape("XXX\nXXX\nXXX", 1.4),
        BlockShape("XXX\nXXX", 1.2), BlockShape("XX\nXX\nXX", 1.2),
        BlockShape("XX\nX.", 1), BlockShape("XX\n.X", 1), BlockShape("X.\nXX", 1), BlockShape(".X\nXX", 1),
        BlockShape("X.\nX.\nXX", 0.7), BlockShape(".X\n.X\nXX", 0.7), BlockShape("XX\nX.\nX.", 0.7), BlockShape("XX\n.X\n.X", 0.7),
        BlockShape("XXX\nX..", 0.7), BlockShape("XXX\n..X", 0.7), BlockShape("X..\nXXX", 0.7), BlockShape("..X\nXXX", 0.7),
        BlockShape("XXX\n.X.", 0.8), BlockShape(".X.\nXXX", 0.8), BlockShape("X.\nXX\nX.", 0.8), BlockShape(".X\nXX\n.X", 0.8),
        BlockShape("XX.\n.XX", 0.8), BlockShape(".XX\nXX.", 0.8), BlockShape("X.\nXX\n.X", 0.8), BlockShape(".X\nXX\nX.", 0.8),
        BlockShape("XXX\nX..\nX..", 0.8), BlockShape("XXX\n..X\n..X", 0.8), BlockShape("X..\nX..\nXXX", 0.8), BlockShape("..X\n..X\nXXX", 0.8),
    ]
    static let totalWeight = shapes.reduce(0) { $0 + $1.weight }

    /// Фигуры Шибы — щенячьи, маленькие (индекс в shapes, вес): он затыкает дырки, а не занимает поле.
    static let shibaShapes: [(shape: Int, weight: Double)] = [
        (0, 2), (1, 2), (2, 2), (3, 1.5), (4, 1.5), (9, 1.5), (13, 1), (14, 1), (15, 1), (16, 1),
    ]

    // MARK: раздача

    private static let golden: UInt64 = 0x9E37_79B9_7F4A_7C15
    /// Своя «соль» у ходов Шибы: его фигуры не повторяют тройки хозяина.
    private static let shibaSalt: UInt64 = 0x5348_4942_4144_4F47

    /// Тройка номер round: три фигуры по весам, три разных цвета 1…8. Число бросков не зависит от выпавшего.
    static func deal(seed: UInt64, round: Int) -> [BlockPiece] {
        var rng = CatchRandom(seed: seed ^ (UInt64(round) &+ 1) &* golden)
        var colors: [UInt8] = Array(1...8)
        var out: [BlockPiece] = []
        for _ in 0..<3 {
            var x = rng.unit() * totalWeight
            var s = 0
            while s < shapes.count - 1 && x >= shapes[s].weight {
                x -= shapes[s].weight
                s += 1
            }
            let k = Swift.min(colors.count - 1, Int(rng.unit() * Double(colors.count)))
            out.append(BlockPiece(shape: s, color: colors.remove(at: k)))
        }
        return out
    }

    /// Фигура Шибы на его ход номер turn.
    static func shibaPiece(seed: UInt64, turn: Int) -> BlockPiece {
        var rng = CatchRandom(seed: (seed ^ shibaSalt) ^ (UInt64(turn) &+ 1) &* golden)
        let total = shibaShapes.reduce(0) { $0 + $1.weight }
        var x = rng.unit() * total
        for s in shibaShapes {
            if x < s.weight { return BlockPiece(shape: s.shape, color: shibaColor) }
            x -= s.weight
        }
        return BlockPiece(shape: shibaShapes[shibaShapes.count - 1].shape, color: shibaColor)
    }

    // MARK: поле

    static func fits(_ s: BlockShape, at: BlockCell, on board: [UInt8]) -> Bool {
        guard at.r >= 0, at.c >= 0, at.r + s.h <= size, at.c + s.w <= size else { return false }
        return s.cells.allSatisfy { board[(at.r + $0.r) * size + at.c + $0.c] == 0 }
    }

    /// Все места, куда фигура встаёт, сверху слева направо.
    static func spots(_ s: BlockShape, on board: [UInt8]) -> [BlockCell] {
        var out: [BlockCell] = []
        guard s.h <= size, s.w <= size else { return out }
        for r in 0...(size - s.h) {
            for c in 0...(size - s.w) where fits(s, at: BlockCell(r: r, c: c), on: board) {
                out.append(BlockCell(r: r, c: c))
            }
        }
        return out
    }

    /// Полные строки и столбцы.
    static func fullLines(_ b: [UInt8]) -> (rows: [Int], cols: [Int]) {
        let rows = (0..<size).filter { r in (0..<size).allSatisfy { b[r * size + $0] != 0 } }
        let cols = (0..<size).filter { c in (0..<size).allSatisfy { b[$0 * size + c] != 0 } }
        return (rows, cols)
    }

    /// Клетки строк и столбцов вместе, без повторов, по возрастанию.
    static func lineCells(rows: [Int], cols: [Int]) -> [Int] {
        var set = Set<Int>()
        for r in rows { for c in 0..<size { set.insert(r * size + c) } }
        for c in cols { for r in 0..<size { set.insert(r * size + c) } }
        return set.sorted()
    }

    /// Оценка места: сколько линий исчезнет и сколько соседей у клеток фигуры (занятые клетки и стенки).
    static func rate(_ s: BlockShape, at: BlockCell, on board: [UInt8]) -> (lines: Int, touch: Int) {
        var b = board
        let mine = Set(s.cells.map { BlockCell(r: at.r + $0.r, c: at.c + $0.c).index })
        for i in mine { b[i] = 1 }
        let (rows, cols) = fullLines(b)
        var touch = 0
        for i in mine {
            let r = i / size, c = i % size
            for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let nr = r + dr, nc = c + dc
                if nr < 0 || nr >= size || nc < 0 || nc >= size {
                    touch += 1
                } else if !mine.contains(nr * size + nc) && board[nr * size + nc] != 0 {
                    touch += 1
                }
            }
        }
        return (rows.count + cols.count, touch)
    }

    /// Ход Шибы: больше линий; поровну — плотнее прилегает; дальше — первое сверху слева. nil — места нет.
    static func shibaSpot(_ p: BlockPiece, on board: [UInt8]) -> BlockCell? {
        best(p.form, on: board)?.at
    }

    private static func best(_ s: BlockShape, on board: [UInt8]) -> (at: BlockCell, lines: Int, touch: Int)? {
        var top: (at: BlockCell, lines: Int, touch: Int)? = nil
        for at in spots(s, on: board) {
            let (l, t) = rate(s, at: at, on: board)
            if let b = top, (l, t) <= (b.lines, b.touch) { continue }
            top = (at, l, t)
        }
        return top
    }

    // MARK: автопилот (тесты, UI-снимки)

    /// Ход хозяина так же жадно, как Шиба, по всем фигурам тройки; поровну — левая фигура. nil — ходить некуда.
    static func pilotMove(_ g: BlockDuoGame) -> (slot: Int, at: BlockCell)? {
        var top: (slot: Int, at: BlockCell, lines: Int, touch: Int)? = nil
        for (slot, p) in g.tray.enumerated() {
            guard let p, let b = best(p.form, on: g.board) else { continue }
            if let t = top, (b.lines, b.touch) <= (t.lines, t.touch) { continue }
            top = (slot, b.at, b.lines, b.touch)
        }
        return top.map { ($0.slot, $0.at) }
    }

    /// Сыграть автопилотом не больше moves ходов хозяина (или до конца). Детерминировано.
    static func autoplay(seed: UInt64, moves: Int = .max) -> BlockDuoGame {
        var g = BlockDuoGame(seed: seed)
        var n = 0
        while n < moves, !g.isOver, let m = pilotMove(g) {
            _ = g.place(slot: m.slot, at: m.at)
            n += 1
        }
        return g
    }

    // MARK: награда

    /// Сменились местные сутки — счётчики с нуля. Назад не откатываемся, как Economy.rollDay.
    static func rollDay(_ f: inout SaveFile, now: Double) {
        let d = Economy.day(now)
        guard d > f.blockduoDay else { return }
        f.blockduoDay = d
        f.blockduoCoins = 0
        f.blockduoGames = 0
    }

    /// Монет за «Блок Дуо» сегодня (до смены суток — 0).
    static func coinsToday(_ f: SaveFile, now: Double) -> Int {
        Economy.day(now) > f.blockduoDay ? 0 : f.blockduoCoins
    }

    /// Сколько монет ещё можно получить сегодня: свой потолок и общий потолок мини-игр.
    static func coinsLeft(_ f: SaveFile, now: Double, _ cfg: BlockDuoConfig = .shared) -> Int {
        let own = cfg.dailyCap - coinsToday(f, now: now)
        let all = cfg.sharedCap - MiniGames.coinsToday(f, now: now)
        return Swift.max(0, Swift.min(own, all))
    }

    /// Можно ли играть — как в «Лови мячик»: причина трюков или отказ ядра на play. nil — можно.
    static func gate(_ f: SaveFile, at t: Double) -> String? { CatchGame.gate(f, at: t) }

    /// Партия кончилась (или её бросили): рекорд, монеты с потолками, настроение через ядерный play. Пишет только в f.
    @discardableResult
    static func finish(_ g: BlockDuoGame, in f: inout SaveFile, now: Double, _ cfg: BlockDuoConfig = .shared) -> BlockDuoResult {
        var r = BlockDuoResult(score: Swift.max(0, g.score), mine: g.mine, shiba: g.shiba, lines: g.lines, maxCombo: g.maxCombo)
        PetRunner.catchUp(&f, now: now)
        rollDay(&f, now: now)
        f.blockduoGames += 1
        let wish = CatchGame.want(score: r.score, game: f.blockduoGames, buff: CatchGame.coinsX(f.pet), cfg.asCatch)
        let got = Swift.min(wish, coinsLeft(f, now: now, cfg))
        f.blockduoCoins += got
        f.econ.wallet.coins += got
        r.coins = got
        r.capped = got < wish
        r.isRecord = r.score > f.blockduoBest
        f.blockduoBest = Swift.max(f.blockduoBest, r.score)
        r.best = f.blockduoBest
        // Ни одной фигуры — это не игра: настроение не трогаем.
        if r.score > 0 {
            let out = PetRunner.apply(.play, source: .app, to: &f, now: now)
            r.played = out.ok
            r.careCoins = out.ok ? out.coins : 0
            r.reason = out.ok ? nil : out.reason
        }
        return r
    }

    // MARK: тексты

    static func resultTitle(_ r: BlockDuoResult) -> String {
        if r.isRecord && r.score > 0 { return "Новый рекорд!" }
        if r.score == 0 { return "Даже не начали…" }
        return "Места больше нет!"
    }

    /// «+12 монет», «На сегодня монет хватит» или nil (очков нет).
    static func rewardText(_ r: BlockDuoResult) -> String? {
        if r.totalCoins > 0 { return "+\(EconText.coins(r.totalCoins))" }
        if r.capped { return "На сегодня монет за игры хватит" }
        return nil
    }

    /// Что Шиба скажет в комнате после партии. Выбор по счёту: одна партия — одна фраза.
    static func shibaLine(_ r: BlockDuoResult) -> String {
        if r.score == 0 { return "Давай ещё разок? Я поставлю свою фигурку!" }
        if r.isRecord { return "Гав! Наш рекорд — \(r.score)! Мы команда!" }
        if r.shiba > 0 && r.shiba >= r.mine / 3 { return "Видел, как я линию убрал? Гав!" }
        let lines = [
            "Классно сыграли вдвоём!",
            "Ещё партию? Я уже придумал, куда ставить!",
            "Ты ставишь, я помогаю — так веселее!",
        ]
        return lines[r.score % lines.count]
    }
}

// MARK: - Общий потолок мини-игр

enum MiniGames {
    /// Если в economy.json нет minigames.daily_cap: столько же, сколько потолок одной игры.
    static let defaultSharedCap = 60

    /// Монет за все мини-игры сегодня (у каждой свои сутки в сейве: вчерашнее не в счёт).
    static func coinsToday(_ f: SaveFile, now: Double) -> Int {
        let d = Economy.day(now)
        let c = d > f.catchDay ? 0 : f.catchCoins
        let b = d > f.blockduoDay ? 0 : f.blockduoCoins
        let z = d > f.zombieDay ? 0 : f.zombieCoins
        return c + b + z
    }
}
