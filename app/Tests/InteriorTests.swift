// Волна 41 G: интерьер комнаты (Interior.swift) — обои, пол и ковёр на выбор. Каталог, цены из economy.json,
// покупка и выбор, сейв со старыми файлами, переход новому щенку, яркость стен под статус-баром и геометрия
// узоров (чистые функции InteriorArt: сцену в WSL не собрать). Гоняется и на Linux.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let iT0: Double = 1_760_000_000

private func iFile(coins: Int = 0, shards: Int = 0) -> SaveFile {
    var f = SaveFile.fresh(now: iT0)
    f.econ.wallet.coins = coins
    f.econ.wallet.shards = shards
    return f
}

private func iConfigURL() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("config/economy.json")
}

private let iFixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

final class InteriorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: Paths.mirror)
    }

    // MARK: каталог

    func testCatalogShape() {
        XCTAssertEqual(Set(Interior.all.map(\.id)).count, Interior.all.count, "id не повторяются")
        for part in InteriorPart.allCases {
            let s = Interior.styles(part)
            XCTAssertTrue((3...5).contains(s.count), "\(part): 3–5 вариантов, а их \(s.count)")
            XCTAssertTrue(s[0].isFree, "\(part): первый бесплатный")
            XCTAssertEqual(Interior.standard(part), s[0])
            XCTAssertEqual(s.filter(\.isFree).count, 1, "\(part): бесплатный один")
            for st in s {
                XCTAssertFalse(st.name.isEmpty)
                XCTAssertLessThanOrEqual(st.name.count, 20, "\(st.id): короткое имя для плитки")
                switch (part, st.look) {
                case (.walls, .walls), (.floor, .floor), (.rug, .rug): break
                default: XCTFail("\(st.id): вид не своей части")
                }
            }
        }
        let exclusives = Interior.all.filter(\.isExclusive)
        XCTAssertTrue((1...2).contains(exclusives.count), "1–2 эксклюзива за клочки")
    }

    func testStandardIsTheOldRoom() {
        // Прежние цвета PetRoom/RoomColors: стена 0xfbefe4, клетка 0xbcd3ee/0xf4f1ea, ковёр 0xe9b8a8.
        XCTAssertEqual(Interior.standard(.walls).look, .walls(.plain(0xfbefe4)))
        XCTAssertEqual(Interior.standard(.floor).look, .floor(.checker(0xbcd3ee, 0xf4f1ea)))
        XCTAssertEqual(Interior.standard(.rug).look, .rug(.round(0xe9b8a8)))
        XCTAssertEqual(Interior.shown(iFile()), .standard)
    }

    // MARK: цены

    func testConfigFileMatchesDefaults() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: iConfigURL()))
        XCTAssertEqual(InteriorConfig(json: json), InteriorConfig(), "config/economy.json и умолчания в Swift разошлись")
        XCTAssertEqual(InteriorConfig(json: .null), InteriorConfig())
        // В файле — ровно платные варианты, каждый в своей валюте.
        let coinIds = Set(json["interior"]["coins"].object.keys), shardIds = Set(json["interior"]["shards"].object.keys)
        XCTAssertEqual(coinIds, Set(Interior.all.filter { $0.currency == .coins }.map(\.id)))
        XCTAssertEqual(shardIds, Set(Interior.all.filter(\.isExclusive).map(\.id)))
    }

    func testConfigReadsOverridesAndIgnoresWrongCurrency() throws {
        let raw = #"{"interior": {"coins": {"wall_mint": 77, "rug_oval": 0, "wall_stars": 5, "wall_cream": 9},"#
            + #" "shards": {"rug_stripes": 11, "floor_planks": 3}}}"#
        let c = InteriorConfig(json: try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)))
        XCTAssertEqual(c.price(Interior.style("wall_mint")!), 77)
        XCTAssertEqual(c.price(Interior.style("rug_oval")!), 1, "ноль и меньше — 1")
        XCTAssertEqual(c.price(Interior.style("rug_stripes")!), 11)
        XCTAssertEqual(c.price(Interior.style("wall_stars")!), 120, "эксклюзив за монеты не продаётся")
        XCTAssertEqual(c.price(Interior.style("floor_planks")!), 450, "монетный вариант за клочки не продаётся")
        XCTAssertEqual(c.price(Interior.style("wall_cream")!), 0, "бесплатное остаётся бесплатным")
    }

    func testPricesSitBetweenShopAndHome() {
        let c = InteriorConfig()
        for st in Interior.all where st.currency == .coins {
            XCTAssertTrue((100...1000).contains(c.price(st)), "\(st.id): уровня игрушек лавки")
        }
        for st in Interior.all where st.isExclusive {
            XCTAssertTrue((70...120).contains(c.price(st)), "\(st.id): между сезонной вещью и эксклюзивом места")
        }
    }

    // MARK: покупка и выбор

    func testBuyForCoinsSpendsOnlyCoinsAndSetsIt() {
        var f = iFile(coins: 1000, shards: 50)
        let before = f
        guard case .success(let st) = Interior.buy("floor_planks", in: &f, now: iT0) else { return XCTFail("купить") }
        XCTAssertEqual(st.id, "floor_planks")
        XCTAssertEqual(f.econ.wallet.coins, 550)
        XCTAssertEqual(f.econ.wallet.shards, 50)
        XCTAssertEqual(f.interior.owned, ["floor_planks"])
        XCTAssertEqual(Interior.shown(f).floor, "floor_planks", "купленное сразу встаёт")
        XCTAssertEqual(f.journal.last?.kind, "interior.buy")
        XCTAssertEqual(f.journal.last?.key, "floor_planks")
        XCTAssertEqual(f.journal.last?.value, 450)
        // Косметика: ни потолков, ни заработка, ни уровня, ни питомца.
        XCTAssertEqual(f.econ.daily, before.econ.daily)
        XCTAssertEqual(f.econ.items, before.econ.items)
        XCTAssertEqual(f.level, before.level)
        XCTAssertEqual(f.yard, before.yard)
        XCTAssertEqual(f.pet, before.pet)
    }

    func testBuyForShards() {
        var f = iFile(coins: 5000, shards: 100)
        guard case .success = Interior.buy("rug_stripes", in: &f, now: iT0) else { return XCTFail("купить") }
        XCTAssertEqual(f.econ.wallet.shards, 10)
        XCTAssertEqual(f.econ.wallet.coins, 5000, "эксклюзив монет не берёт")
        XCTAssertEqual(Interior.shown(f).rug, "rug_stripes")
    }

    func testRefusals() {
        var f = iFile(coins: 100, shards: 10)
        XCTAssertEqual(Interior.buy("nope", in: &f, now: iT0).failure, .unknown)
        XCTAssertEqual(Interior.buy("wall_cream", in: &f, now: iT0).failure, .owned, "бесплатное и так есть")
        XCTAssertEqual(Interior.buy("wall_mint", in: &f, now: iT0).failure, .notEnoughCoins(need: 350))
        XCTAssertEqual(Interior.buy("wall_stars", in: &f, now: iT0).failure, .notEnoughShards(need: 110))
        XCTAssertEqual(f.econ.wallet.coins, 100, "отказ ничего не тратит")
        XCTAssertEqual(f.econ.wallet.shards, 10)
        XCTAssertTrue(f.interior.isEmpty)
        XCTAssertEqual(Interior.choose("wall_mint", in: &f).failure, .notOwned)
        XCTAssertEqual(Interior.choose("nope", in: &f).failure, .unknown)
        f.econ.wallet.coins = 1000
        _ = Interior.buy("wall_mint", in: &f, now: iT0)
        XCTAssertEqual(Interior.buy("wall_mint", in: &f, now: iT0).failure, .owned)
        XCTAssertEqual(f.econ.wallet.coins, 550, "второй раз не списывает")
        for r: InteriorRefusal in [.owned, .notOwned, .unknown, .notEnoughCoins(need: 3), .notEnoughShards(need: 4)] {
            XCTAssertFalse(InteriorText.refusal(r).hasPrefix("interior_"), "\(r): строка есть")
        }
        XCTAssertEqual(InteriorText.refusal(.notEnoughCoins(need: 3)), "Не хватает 3 🪙")
    }

    func testChooseBackToStandardKeepsSaveEmpty() {
        var f = iFile(coins: 1000)
        _ = Interior.buy("rug_rings", in: &f, now: iT0)
        XCTAssertEqual(f.interior.rug, "rug_rings")
        guard case .success = Interior.choose("rug_round", in: &f) else { return XCTFail("бесплатный ставится всегда") }
        XCTAssertNil(f.interior.rug, "по умолчанию — nil, а не id")
        XCTAssertEqual(Interior.shown(f).rug, "rug_round")
        XCTAssertEqual(f.interior.owned, ["rug_rings"], "купленное не пропадает")
        guard case .success = Interior.choose("rug_rings", in: &f) else { return XCTFail("своё ставится") }
        XCTAssertEqual(Interior.shown(f).rug, "rug_rings")
    }

    func testBrokenChoiceFallsBackToStandard() {
        var f = iFile()
        f.interior.walls = "wall_mint"      // не куплено
        f.interior.floor = "rug_oval"       // не та часть
        f.interior.rug = "gone_rug"         // нет в каталоге
        f.interior.owned = ["rug_oval"]
        XCTAssertEqual(Interior.shown(f), .standard)
    }

    func testOffersForSheet() {
        var f = iFile(coins: 400, shards: 0)
        _ = Interior.buy("wall_stripes", in: &f, now: iT0)   // 400 → 100
        let walls = Interior.offers(f, .walls)
        XCTAssertEqual(walls.map(\.id), Interior.styles(.walls).map(\.id))
        XCTAssertEqual(walls[0].state, .owned)
        XCTAssertEqual(walls[1].state, .chosen)
        XCTAssertEqual(walls[2].state, .buy(need: 350))
        XCTAssertEqual(walls.last?.state, .buy(need: 120), "эксклюзив считает клочки")
        XCTAssertEqual(InteriorText.button(walls[1]), "Стоит")
        XCTAssertEqual(InteriorText.button(walls[0]), "Поставить")
        XCTAssertEqual(InteriorText.button(walls[2]), "Не хватает 350 🪙")
        XCTAssertEqual(InteriorText.button(walls.last!), "Не хватает 120 ✂️")
        f.econ.wallet.coins = 1000
        XCTAssertEqual(InteriorText.button(Interior.offers(f, .walls)[2]), "450 🪙")
    }

    func testPerformGoesThroughStore() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-interior")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.mutate { (f: inout SaveFile) -> Void in f.econ.wallet.coins = 700 }
        let r = try Interior.perform(buy: "wall_diamonds", store: store, now: Clock.now())
        XCTAssertEqual(r.success?.id, "wall_diamonds")
        XCTAssertEqual(try XCTUnwrap(store.read()).econ.wallet.coins, 100)
        _ = try Interior.perform(choose: "wall_cream", store: store)
        XCTAssertEqual(Interior.shown(try XCTUnwrap(store.read())).walls, "wall_cream")
    }

    // MARK: сейв

    func testEmptyInteriorIsNotWritten() throws {
        let data = try JSONEncoder().encode(iFile())
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"interior\""), "пустое в файл не пишется")
        XCTAssertTrue(try JSONDecoder().decode(SaveFile.self, from: data).interior.isEmpty)
    }

    func testInteriorRoundTrips() throws {
        var f = iFile(coins: 2000, shards: 200)
        _ = Interior.buy("wall_stars", in: &f, now: iT0)
        _ = Interior.buy("floor_zigzag", in: &f, now: iT0)
        _ = Interior.buy("rug_square", in: &f, now: iT0)
        _ = Interior.choose("floor_checker", in: &f)
        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.interior, f.interior)
        XCTAssertEqual(Interior.shown(back), InteriorShown(walls: "wall_stars", floor: "floor_checker", rug: "rug_square"))
    }

    func testOldSaveWithoutInteriorOpens() throws {
        let raw = try Data(contentsOf: iFixtures.appendingPathComponent("save-v0.14.json"))
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("\"interior\""))
        let f = try JSONDecoder().decode(SaveFile.self, from: raw)
        XCTAssertTrue(f.interior.isEmpty)
        XCTAssertEqual(Interior.shown(f), .standard, "старый сейв — прежняя комната")
    }

    func testBrokenInteriorFieldDoesNotBreakSave() throws {
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(iFile(coins: 9))) as? [String: Any])
        obj["interior"] = ["owned": 5, "walls": "wall_mint", "floor": 3]
        let f = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(f.econ.wallet.coins, 9, "сейв цел")
        XCTAssertEqual(f.interior.owned, [])
        XCTAssertEqual(f.interior.walls, "wall_mint")
        XCTAssertNil(f.interior.floor)
        XCTAssertEqual(Interior.shown(f).walls, "wall_cream", "не куплено — не показываем")
        obj["interior"] = "мусор"
        XCTAssertTrue(try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: obj))
            .interior.isEmpty)
    }

    func testNewPuppyKeepsTheRoom() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-interior")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: iT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.econ.wallet.coins = 1000
            _ = Interior.buy("floor_mint", in: &f, now: iT0)
        }
        let old = try XCTUnwrap(store.read()).petId
        try store.startOver(now: iT0 + 86400)
        let f = try XCTUnwrap(store.read())
        XCTAssertNotEqual(f.petId, old, "новый щенок")
        XCTAssertEqual(f.interior.owned, ["floor_mint"], "комната хозяина остаётся")
        XCTAssertEqual(Interior.shown(f).floor, "floor_mint")
    }

    // MARK: тексты

    func testTextKeysExist() throws {
        let ui = Lines.shared.sections["ui"] ?? [:]
        guard !ui.isEmpty else { throw XCTSkip("lines.json нет в бандле") }
        for k in InteriorText.keys {
            XCTAssertFalse((ui[k] ?? []).isEmpty, "нет строки ui.\(k)")
            XCTAssertTrue(k.hasPrefix("interior_"), k)
        }
        for p in InteriorPart.allCases { XCTAssertFalse(InteriorText.partName(p).hasPrefix("interior_")) }
        XCTAssertEqual(InteriorText.ui("interior_bought", ["item": "Доски"]), "Теперь в комнате: Доски")
    }

    // MARK: свет и статус-бар

    func testWallsKeepStatusBarScrimDecisions() {
        // Статус-бар смотрит на прежний цвет стены (RoomClock.needsStatusScrim): верх новых обоев не должен
        // заметно отличаться по яркости ни в какой час, иначе подложка под часами окажется не к месту.
        let old = RoomRGB(hex: 0xfbefe4).luminance
        for st in Interior.styles(.walls) {
            guard case .walls(let w) = st.look else { continue }
            XCTAssertEqual(RoomRGB(hex: w.base).luminance, old, accuracy: 0.03, "\(st.id): фон стены")
            for phase in stride(from: 0.0, through: 2.0, by: 0.05) {
                let light = RoomLight.at(phase: phase)
                for dark in [false, true] {
                    let lum = light.wallLuminance(w.base)
                    let mine = dark ? lum > RoomClock.statusThreshold : lum < RoomClock.statusThreshold
                    // Порог в окрестности 0,02 по яркости — допустимая граница: там подложка почти не видна.
                    if abs(light.wallLuminance - RoomClock.statusThreshold) > 0.02 {
                        XCTAssertEqual(mine, RoomClock.needsStatusScrim(phase: phase, dark: dark),
                                       "\(st.id) фаза \(phase) dark=\(dark)")
                    }
                }
            }
        }
        XCTAssertEqual(RoomLight.at(phase: 1).wallLuminance(0xfbefe4), RoomLight.at(phase: 1).wallLuminance)
    }

    // MARK: узоры

    func testWallPatternsStayOnTheWallAndUnderTheWindow() {
        for st in Interior.styles(.walls) {
            guard case .walls(let w) = st.look else { continue }
            let shapes = InteriorArt.wallShapes(w)
            if case .plain = w { XCTAssertTrue(shapes.isEmpty, "однотонные — без узора") } else {
                XCTAssertFalse(shapes.isEmpty, st.id)
            }
            XCTAssertLessThan(shapes.count, 800, "\(st.id): узор лёгкий")
            for s in shapes {
                XCTAssertTrue(w.colors.dropFirst().contains(s.color), "\(st.id): цвет узора из своих")
                XCTAssertGreaterThanOrEqual(s.rim.count, 3)
                for p in s.rim + [s.center] {
                    XCTAssertTrue((0...InteriorArt.wallWidth).contains(p.x) && (0...InteriorArt.wallHeight).contains(p.y),
                                  "\(st.id): \(p) за стеной")
                }
            }
            if case .panel = w {
                // Панель с рейкой ниже окна (0,21) и полотенца ванны (0,22): за ними не прячется.
                let top = shapes.flatMap(\.rim).map(\.y).max() ?? 0
                XCTAssertLessThan(top, RoomPlan.window.minY)
                XCTAssertLessThan(top, RoomPlan.bathTowel.minY)
            }
        }
    }

    func testWallShapesWindCounterClockwise() {
        // Веер из центра против часовой стрелки — лицом к камере (+z), как сама стена.
        for st in Interior.styles(.walls) {
            guard case .walls(let w) = st.look else { continue }
            for s in InteriorArt.wallShapes(w) {
                for i in s.rim.indices {
                    let a = s.rim[i] - s.center, b = s.rim[(i + 1) % s.rim.count] - s.center
                    XCTAssertGreaterThan(a.x * b.y - a.y * b.x, 0, "\(st.id): треугольник смотрит в стену")
                }
            }
        }
    }

    func testDefaultFloorMatchesOldChecker() {
        // Прежняя PetRoom.checkerImage(size: 320, cells: 10): CGContext от левого нижнего угла,
        // клетка (ряд снизу + столбец) чётная — голубая.
        let size = 320
        let px = InteriorArt.floorPixels(.checker(0xbcd3ee, 0xf4f1ea), size: size)
        XCTAssertEqual(px.count, size * size * 4)
        func at(_ x: Int, _ yTop: Int) -> UInt32 {
            let i = (yTop * size + x) * 4
            return UInt32(px[i]) << 16 | UInt32(px[i + 1]) << 8 | UInt32(px[i + 2])
        }
        for row in 0..<10 {
            for col in 0..<10 {
                let x = col * 32 + 16, yBottom = row * 32 + 16
                let want: UInt32 = (row + col) % 2 == 0 ? 0xbcd3ee : 0xf4f1ea
                XCTAssertEqual(at(x, size - 1 - yBottom), want, "клетка \(row),\(col)")
            }
        }
        XCTAssertEqual(px[3], 255, "непрозрачно")
    }

    func testFloorPatternsUseOwnColors() {
        for st in Interior.styles(.floor) {
            guard case .floor(let fl) = st.look else { continue }
            let px = InteriorArt.floorPixels(fl, size: 64)
            var seen = Set<UInt32>()
            for i in stride(from: 0, to: px.count, by: 4) {
                seen.insert(UInt32(px[i]) << 16 | UInt32(px[i + 1]) << 8 | UInt32(px[i + 2]))
            }
            XCTAssertTrue(seen.isSubset(of: Set(fl.colors)), "\(st.id): лишние цвета")
            XCTAssertGreaterThanOrEqual(seen.count, 2, "\(st.id): узор виден")
        }
    }

    func testRugsStayFlatAndInPlace() {
        for st in Interior.styles(.rug) {
            guard case .rug(let r) = st.look else { continue }
            let pieces = InteriorArt.rugPieces(r)
            XCTAssertFalse(pieces.isEmpty, st.id)
            for p in pieces {
                // В прежнем квадрате ковра: миска, мячик-дом и игровой угол стоят вне его, как и раньше.
                XCTAssertLessThanOrEqual(abs(p.x) + p.halfX, InteriorArt.rugRadius + 1e-4, "\(st.id): по x")
                XCTAssertLessThanOrEqual(abs(p.z) + p.halfZ, InteriorArt.rugRadius + 1e-4, "\(st.id): по z")
                // Ниже матраса лежанки и пятна-тени: собака не тонет и не парит.
                XCTAssertLessThanOrEqual(p.top, InteriorArt.rugMaxTop, st.id)
                XCTAssertLessThan(p.top, RoomPlan.bedTop, st.id)
                XCTAssertGreaterThan(p.top, 0, st.id)
            }
            // Слои снизу вверх не стоят на одной высоте с тем, что под ними (не мерцают).
            for (a, b) in zip(pieces, pieces.dropFirst()) where a.top >= b.top {
                XCTAssertTrue(abs(a.x - b.x) > a.halfX + b.halfX - 1e-4 || a.top < b.top, "\(st.id): слой в слое")
            }
            XCTAssertTrue(Set(pieces.map(\.color)).isSubset(of: Set(r.colors + [0xf6efe2])), "\(st.id): цвета свои")
        }
        // По умолчанию — прежний диск: r 0,45, толщина 0,004.
        XCTAssertEqual(InteriorArt.rugPieces(.round(0xe9b8a8)),
                       [RugPiece(shape: .disc(r: 0.45), top: 0.004, color: 0xe9b8a8)])
        // Ковёр не дотягивается до мячика и миски сильнее прежнего круга.
        XCTAssertGreaterThan(RoomPlan.Keep.bowlHome.z.magnitude, InteriorArt.rugRadius)
    }
}

private extension Result {
    var failure: Failure? { if case .failure(let e) = self { return e }; return nil }
    var success: Success? { if case .success(let s) = self { return s }; return nil }
}
