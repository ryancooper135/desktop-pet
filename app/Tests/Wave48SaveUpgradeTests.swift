// Волна 48 V: новая сборка ставится поверх старой (iloader) — сейв v0.15…v0.29 и после волн 32–47 обязан открыться
// тем же щенком: монеты, вещи, двор, уровень, достижения, задания, просьбы. Смерть или сброс из-за обновления — худший баг.
// Fixtures/upgrade/save-<эпоха>.json — один синтетический «богатый» сейв (`fixture-pet`, без личных данных: v0.14 из
// волны 15 + все поля волн 15–47), записанный SaveFile коммита эпохи (git archive + swift test в WSL). Чего эпоха
// не знала, в её файле нет — так и выглядит сейв на телефоне перед обновлением.
// Отдельная папка: DogLevelTests перебирает Fixtures/*.json как сейвы «до уровня», а здесь уровень уже есть.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let upDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures").appendingPathComponent("upgrade")

/// Эпохи по порядку и ключи верхнего уровня, которые в их файле обязаны быть (сверх v0.14).
private let upEpochs: [(v: String, commit: String, keys: [String])] = {
    let w15 = ["birthTz"]
    let w23 = w15 + ["tips"]
    let w32 = w23 + ["runaway", "shardLog", "level", "growth", "yard", "trip"]
    let w35 = w32 + ["challenge"]
    let w43 = w35 + ["interior", "tasks", "asks"]
    return [
        ("v0.15", "41b4b81", w15),
        ("v0.22", "dc45d10", w23),
        ("v0.28", "d8e1614", w23),
        ("v0.29", "cf3b781", w32),
        ("w36", "0d15650", w35),
        ("w40", "9759d2f", w35),
        ("w43", "ba36d45", w43),
        ("w45", "7687185", w43),
    ]
}()

/// Новые ключи, которых в сейве v0.14 (волна 15) ещё не было.
private let upNewKeys = ["birthTz", "tips", "runaway", "shardLog", "level", "growth", "yard", "trip",
                         "challenge", "interior", "tasks", "asks"]

private func upData(_ v: String) throws -> Data {
    try Data(contentsOf: upDir.appendingPathComponent("save-\(v).json"))
}

private func upObject(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// Всё, что есть в `old`, есть и в `new` с тем же значением (новые поля в `new` разрешены).
private func upMissing(_ old: Any, in new: Any?, at path: String = "") -> [String] {
    guard let new else { return [path] }
    if let o = old as? [String: Any] {
        guard let n = new as? [String: Any] else { return [path] }
        return o.keys.sorted().flatMap { upMissing(o[$0]!, in: n[$0], at: path + "." + $0) }
    }
    if let o = old as? [Any] {
        guard let n = new as? [Any], n.count == o.count else { return [path + "[]"] }
        return o.indices.flatMap { upMissing(o[$0], in: n[$0], at: path + "[\($0)]") }
    }
    if let o = old as? String { return (new as? String) == o ? [] : [path] }
    if let o = old as? NSNumber, let n = new as? NSNumber {
        return abs(o.doubleValue - n.doubleValue) < 1e-9 ? [] : [path]
    }
    return "\(old)" == "\(new)" ? [] : [path]
}

private func sub(_ o: [String: Any], _ k: String) -> [String: Any] { (o[k] as? [String: Any]) ?? [:] }

/// Ключевые значения: база v0.14 у всех, новое — если эпоха его уже писала.
private func upCheck(_ f: SaveFile, raw o: [String: Any], _ v: String, file: StaticString = #filePath, line: UInt = #line) {
    // База (волна 15): тот же щенок и всё нажитое.
    XCTAssertEqual(f.petId, "fixture-pet", v, file: file, line: line)
    XCTAssertEqual(f.name, "Шиба", v, file: file, line: line)
    XCTAssertEqual(f.createdT, 1_759_136_000, v, file: file, line: line)
    XCTAssertTrue(f.pet.alive, "\(v): щенок жив", file: file, line: line)
    XCTAssertEqual(f.pet.hearts, 4, v, file: file, line: line)
    XCTAssertEqual(f.pet.finds["stick"], 3, v, file: file, line: line)
    XCTAssertEqual(f.econ.wallet.coins, 1234, "\(v): монеты", file: file, line: line)
    XCTAssertEqual(f.econ.wallet.tickets, 3, v, file: file, line: line)
    XCTAssertEqual(f.econ.wallet.shards, 17, "\(v): клочки ✂️", file: file, line: line)
    XCTAssertEqual(f.econ.items, ["scarf_knit": 1, "bandana_red": 2, "kennel_castle": 1, "ball_tennis": 1],
                   "\(v): вещи", file: file, line: line)
    XCTAssertEqual(f.econ.lastEarn?.coins, 3, v, file: file, line: line)
    XCTAssertEqual(f.cards.album.map(\.id), ["20369-feed"], "\(v): открытки", file: file, line: line)
    XCTAssertEqual(f.tricks.items["sit"]?.learned, 1_759_950_000, "\(v): трюк", file: file, line: line)
    XCTAssertEqual(f.catchBest, 42, v, file: file, line: line)
    // Запись дописывает новые воспоминания (возраст), старые остаются.
    XCTAssertGreaterThanOrEqual(f.memories.items.count, 2, "\(v): воспоминания", file: file, line: line)
    XCTAssertEqual(f.worn["neck"], "scarf_knit", "\(v): надето", file: file, line: line)
    XCTAssertEqual(f.shelf, "kennel_castle", v, file: file, line: line)
    XCTAssertEqual(f.blockduoBest, 1500, v, file: file, line: line)
    XCTAssertEqual(f.zombieBest, 77, v, file: file, line: line)
    XCTAssertEqual(f.characterName, "Тестик", v, file: file, line: line)
    if o["birthTz"] != nil { XCTAssertEqual(f.birthTz, 120, "\(v): пояс рождения", file: file, line: line) }

    if o["tips"] != nil {
        XCTAssertEqual(f.tips.strokes, 12, "\(v): подсказки", file: file, line: line)
        XCTAssertEqual(f.tips.seen, ["pet", "swipe"], v, file: file, line: line)
    }
    if o["runaway"] != nil {
        XCTAssertEqual(f.runaway.comebacks, [1_759_500_000], "\(v): побеги", file: file, line: line)
    }
    if o["shardLog"] != nil {
        XCTAssertEqual(f.shardLog.earned, 23, "\(v): клочки за всё время", file: file, line: line)
        XCTAssertEqual(f.shardLog.finds, 4, v, file: file, line: line)
        XCTAssertEqual(f.shardLog.best["zombie"], 77, v, file: file, line: line)
        XCTAssertEqual(f.shardLog.once, ["ach.first_trick", "ach.first_dish"], "\(v): полученное", file: file, line: line)
    }
    if sub(o, "shardLog")["achT"] != nil {
        XCTAssertEqual(f.shardLog.achT["first_trick"], 1_759_950_000, "\(v): дата достижения", file: file, line: line)
        XCTAssertEqual(f.shardLog.achT.count, 2, v, file: file, line: line)
    }
    if o["level"] != nil {
        XCTAssertEqual(f.level.xp, 6500, "\(v): опыт", file: file, line: line)
        XCTAssertEqual(f.level.paidLevel, 24, "\(v): уровень", file: file, line: line)
        XCTAssertEqual(DogLevel.level(f), 24, v, file: file, line: line)
        XCTAssertEqual(f.level.migrated, 1, v, file: file, line: line)
        XCTAssertEqual(f.level.firsts, ["feed", "walk"], v, file: file, line: line)
    }
    if o["growth"] != nil {
        XCTAssertEqual(f.growth.points, 340, "\(v): рост", file: file, line: line)
        XCTAssertEqual(f.growth.open?.d, 20370, v, file: file, line: line)
    }
    if o["yard"] != nil {
        XCTAssertEqual(f.yard.plates, ["window", "daisy", "dryer", "trash"], "\(v): двор", file: file, line: line)
        XCTAssertEqual(f.yard.stations, ["dryer": 2], v, file: file, line: line)
        XCTAssertEqual(f.yard.bank, 55.5, accuracy: 1e-9, "\(v): копилка двора", file: file, line: line)
        XCTAssertEqual(f.yard.collected, 420, v, file: file, line: line)
        XCTAssertEqual(f.yard.larder, 1, v, file: file, line: line)
    }
    if sub(o, "yard")["gold"] != nil { XCTAssertEqual(f.yard.gold, ["window"], "\(v): золото", file: file, line: line) }
    if sub(o, "yard")["moves"] != nil { XCTAssertEqual(f.yard.moves, 1, "\(v): переезд", file: file, line: line) }
    if o["trip"] != nil {
        XCTAssertEqual(f.trip.count, 5, "\(v): походы", file: file, line: line)
        XCTAssertEqual(f.trip.visits, ["bus_stop": 3, "laundry": 2], v, file: file, line: line)
        XCTAssertEqual(f.trip.album, ["bus_stop.ticket": 2, "bus_stop.badge": 1], "\(v): альбом находок",
                       file: file, line: line)
        XCTAssertEqual(f.trip.last?.find, "bus_stop.badge", v, file: file, line: line)
    }
    if sub(sub(o, "trip"), "last")["extra"] != nil {
        XCTAssertEqual(f.trip.last?.extra, "bus_stop.ticket", v, file: file, line: line)
    }
    if o["challenge"] != nil {
        XCTAssertEqual(f.challenge.count, 4, "\(v): вызовы", file: file, line: line)
        XCTAssertEqual(f.challenge.last?.score, 42, v, file: file, line: line)
    }
    if o["interior"] != nil {
        XCTAssertEqual(f.interior.owned, ["wall_mint", "rug_oval"], "\(v): интерьер", file: file, line: line)
        XCTAssertEqual(f.interior.walls, "wall_mint", v, file: file, line: line)
        XCTAssertEqual(f.interior.rug, "rug_oval", v, file: file, line: line)
    }
    if o["tasks"] != nil {
        XCTAssertEqual(f.tasks.total, 11, "\(v): задания дня", file: file, line: line)
        XCTAssertEqual(f.tasks.items.map(\.id), ["feed", "walk"], v, file: file, line: line)
        XCTAssertEqual(f.tasks.allDays, 3, v, file: file, line: line)
    }
    if o["asks"] != nil {
        XCTAssertEqual(f.asks.total, 6, "\(v): просьбы", file: file, line: line)
        XCTAssertEqual(f.asks.items.first?.kind, "act.feed", v, file: file, line: line)
    }
}

final class Wave48SaveUpgradeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: Paths.mirror)
    }

    func testEveryEpochFixtureExistsWithItsFields() throws {
        for e in upEpochs {
            let raw = try upData(e.v)
            let s = String(decoding: raw, as: UTF8.self)
            XCTAssertTrue(s.contains("\"fixture-pet\""), "\(e.v): синтетический щенок, без личных данных")
            let o = try upObject(raw)
            let has = upNewKeys.filter { o[$0] != nil }
            XCTAssertEqual(has, e.keys, "\(e.v) (\(e.commit)): какие поля эпоха уже писала")
        }
    }

    func testEveryEpochDecodesWithEverything() throws {
        for e in upEpochs {
            let raw = try upData(e.v)
            let f = try JSONDecoder().decode(SaveFile.self, from: raw)
            XCTAssertEqual(f.rev, 321, e.v)
            XCTAssertEqual(f.memories.items.count, 2, e.v)
            upCheck(f, raw: try upObject(raw), e.v)
        }
    }

    /// Новая сборка перезаписывает файл: ни одно поле старого не теряется, второй круг — байт в байт.
    func testEveryEpochRewriteKeepsEveryField() throws {
        for e in upEpochs {
            let raw = try upData(e.v)
            let f = try JSONDecoder().decode(SaveFile.self, from: raw)
            let again = try JSONEncoder().encode(f)
            XCTAssertEqual(upMissing(try upObject(raw), in: try upObject(again)), [], "\(e.v): поля пропали при перезаписи")
            let g = try JSONDecoder().decode(SaveFile.self, from: again)
            upCheck(g, raw: try upObject(raw), "\(e.v) перезапись")
            let enc = JSONEncoder()
            enc.outputFormatting = .sortedKeys
            XCTAssertEqual(try enc.encode(g), try enc.encode(JSONDecoder().decode(SaveFile.self, from: enc.encode(g))),
                           "\(e.v): формат устойчив")
        }
    }

    /// Первый запуск после установки поверх: стор читает файл эпохи, первая запись не путает его с аварией.
    func testEveryEpochSurvivesStoreAfterUpgrade() throws {
        for e in upEpochs {
            let dir = StoreHooks.makeTempStoreDir("pet-upgrade")
            defer { StoreHooks.removeTempStore(dir) }
            let store = PetStore(dir: dir)
            let raw = try upData(e.v)
            try raw.write(to: store.stateURL)
            upCheck(try XCTUnwrap(store.read(), e.v), raw: try upObject(raw), "\(e.v) чтение")

            try store.mutate { (f: inout SaveFile) -> Void in f.econ.wallet.coins += 1 }
            let f = try XCTUnwrap(store.read(), e.v)
            XCTAssertEqual(f.rev, 322, e.v)
            XCTAssertEqual(f.petId, "fixture-pet", "\(e.v): тот же щенок")
            XCTAssertTrue(f.pet.alive, e.v)
            XCTAssertEqual(f.econ.wallet.coins, 1235, e.v)
            XCTAssertFalse(f.journal.contains { $0.kind.hasPrefix("save_") }, "\(e.v): обновление — не авария")
            let before = try JSONDecoder().decode(SaveFile.self, from: raw)
            XCTAssertTrue(Set(before.memories.items.map(\.id)).isSubset(of: f.memories.items.map(\.id)), "\(e.v): воспоминания")
            var back = f
            back.econ.wallet.coins -= 1
            upCheck(back, raw: try upObject(raw), "\(e.v) после записи")
            let bak = try JSONDecoder().decode(SaveFile.self, from: Data(contentsOf: store.bakURL))
            XCTAssertEqual(bak.rev, 321, "\(e.v): копия — исходный файл эпохи")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            XCTAssertFalse(names.contains { $0.hasPrefix("corrupt-") || $0.hasPrefix("state.broken-") }, "\(e.v): \(names)")
        }
    }

    /// Первый догон новой сборкой (миграции уровня, клочков, заданий, просьб): нажитое не убывает, щенок жив.
    func testEveryEpochCatchUpKeepsProgress() throws {
        for e in upEpochs {
            let raw = try upData(e.v)
            let o = try upObject(raw)
            let old = try JSONDecoder().decode(SaveFile.self, from: raw)
            var f = old
            PetRunner.catchUp(&f, now: old.pet.t + 1800)
            let v = e.v
            XCTAssertEqual(f.petId, old.petId, v)
            XCTAssertTrue(f.pet.alive, "\(v): щенок жив после догона")
            XCTAssertGreaterThanOrEqual(f.econ.wallet.coins, old.econ.wallet.coins, "\(v): монеты не убыли")
            XCTAssertGreaterThanOrEqual(f.econ.wallet.shards, old.econ.wallet.shards, v)
            XCTAssertGreaterThanOrEqual(f.econ.wallet.tickets, old.econ.wallet.tickets, v)
            for (id, n) in old.econ.items { XCTAssertGreaterThanOrEqual(f.econ.items[id] ?? 0, n, "\(v): вещь \(id)") }
            XCTAssertEqual(f.worn, old.worn, v)
            XCTAssertEqual(f.tricks.items.keys.sorted(), old.tricks.items.keys.sorted(), v)
            XCTAssertEqual(f.cards.album.map(\.id).prefix(1), ["20369-feed"], v)
            XCTAssertGreaterThanOrEqual(f.level.xp, old.level.xp, "\(v): опыт не убыл")
            XCTAssertGreaterThanOrEqual(DogLevel.level(f), DogLevel.level(old), v)
            XCTAssertEqual(f.yard.plates, old.yard.plates, "\(v): двор")
            XCTAssertEqual(f.yard.stations, old.yard.stations, v)
            XCTAssertGreaterThanOrEqual(f.yard.collected, old.yard.collected, v)
            XCTAssertEqual(f.yard.gold, old.yard.gold, v)
            XCTAssertEqual(f.yard.moves, old.yard.moves, v)
            XCTAssertEqual(f.interior.owned, old.interior.owned, "\(v): интерьер")
            XCTAssertEqual(f.trip.album, old.trip.album, "\(v): альбом находок")
            XCTAssertGreaterThanOrEqual(f.trip.count, old.trip.count, v)
            XCTAssertGreaterThanOrEqual(f.challenge.count, old.challenge.count, v)
            XCTAssertGreaterThanOrEqual(f.growth.points, old.growth.points, v)
            XCTAssertGreaterThanOrEqual(f.shardLog.earned, old.shardLog.earned, v)
            XCTAssertTrue(Set(old.shardLog.achT.keys).isSubset(of: f.shardLog.achT.keys), "\(v): достижения")
            for (k, t) in old.shardLog.achT { XCTAssertEqual(f.shardLog.achT[k], t, "\(v): дата «Получено» \(k)") }
            XCTAssertGreaterThanOrEqual(f.tasks.total, old.tasks.total, "\(v): задания")
            XCTAssertGreaterThanOrEqual(f.asks.total, old.asks.total, "\(v): просьбы")
            if o["level"] != nil { XCTAssertEqual(f.level.migrated, 1, "\(v): перенос опыта не повторяется") }
        }
    }

    // MARK: устойчивость

    /// Откат на старую сборку и обратно, или файл от будущей версии: лишние поля на любом уровне не мешают.
    func testUnknownFieldsEverywhereDoNotBreakLatestSave() throws {
        let raw = try upData("w45")
        var o = try upObject(raw)
        o["future"] = ["friends": [1, 2, 3]]
        for k in ["pet", "econ", "yard", "level", "growth", "trip", "shardLog", "challenge", "interior", "tasks",
                  "asks", "tips", "runaway"] {
            var s = sub(o, k)
            s["futureField"] = ["x": 1]
            o[k] = s
        }
        var tasks = sub(o, "tasks")
        var items = try XCTUnwrap(tasks["items"] as? [[String: Any]])
        items[0]["future"] = true
        tasks["items"] = items
        o["tasks"] = tasks
        var asks = sub(o, "asks")
        var ask = try XCTUnwrap(asks["items"] as? [[String: Any]])
        ask[0]["future"] = "x"
        asks["items"] = ask
        o["asks"] = asks
        var trip = sub(o, "trip")
        var last = sub(trip, "last")
        last["future"] = 1
        trip["last"] = last
        o["trip"] = trip

        let f = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: o))
        upCheck(f, raw: try upObject(raw), "лишние поля")
    }

    /// Новое поле записано не тем типом (чужая сборка, ручная правка): сбрасывается только оно, щенок и остальное целы.
    func testWrongTypedNewFieldResetsOnlyItself() throws {
        let raw = try upData("w45")
        let good = try upObject(raw)
        for k in upNewKeys {
            for junk: Any in ["мусор", 5, [1, 2], NSNull()] {
                var o = good
                o[k] = junk
                let f = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: o))
                var rest = good
                rest.removeValue(forKey: k)
                upCheck(f, raw: rest, "\(k)=\(junk)")
            }
        }
        // Битый вложенный элемент: список не сбрасывает весь сейв.
        var o = good
        var yard = sub(o, "yard")
        yard["bank"] = "много"
        o["yard"] = yard
        let f = try JSONDecoder().decode(SaveFile.self, from: JSONSerialization.data(withJSONObject: o))
        XCTAssertEqual(f.petId, "fixture-pet")
        XCTAssertEqual(f.econ.wallet.coins, 1234)
        XCTAssertEqual(f.level.xp, 6500, "соседние подобъекты целы")
        XCTAssertEqual(f.interior.owned, ["wall_mint", "rug_oval"])
    }

    /// Установка оборвалась посреди записи: обрезанный или пустой сейв новой эпохи — продолжаем с копии со всем двором.
    func testTruncatedUpgradedSaveContinuesFromBak() throws {
        let cases: [(String, (Data) -> Data)] = [
            ("обрезан наполовину", { Data($0.prefix($0.count / 2)) }),
            ("обрезан у конца", { Data($0.dropLast(2)) }),
            ("пустой", { _ in Data() }),
            ("нули", { Data(repeating: 0, count: $0.count) }),
        ]
        for (name, cut) in cases {
            let dir = StoreHooks.makeTempStoreDir("pet-upgrade")
            defer { StoreHooks.removeTempStore(dir) }
            let store = PetStore(dir: dir)
            let raw = try upData("w45")
            try raw.write(to: store.stateURL)
            try store.mutate { (f: inout SaveFile) -> Void in f.econ.wallet.coins += 1 }
            // bak = файл эпохи (rev 321); основной обрывается.
            let main = try Data(contentsOf: store.stateURL)
            try cut(main).write(to: store.stateURL)

            let seen = try XCTUnwrap(store.read(), name)
            upCheck(seen, raw: try upObject(raw), "\(name): читатель видит копию")
            try store.mutate { (f: inout SaveFile) -> Void in f.econ.wallet.coins += 10 }
            let f = try XCTUnwrap(store.read(), name)
            XCTAssertEqual(f.petId, "fixture-pet", "\(name): тот же щенок")
            XCTAssertEqual(f.econ.wallet.coins, 1244, name)
            XCTAssertEqual(f.yard.plates.count, 4, "\(name): двор цел")
            XCTAssertEqual(f.level.xp, 6500, name)
            XCTAssertEqual(f.interior.owned.count, 2, name)
            XCTAssertEqual(f.asks.total, 6, name)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            XCTAssertEqual(names.filter { $0.hasPrefix("state.broken-") }.count, 1, "\(name): испорченный отложен, не стёрт")
            XCTAssertFalse(names.contains { $0.hasPrefix("corrupt-") }, "\(name): новый щенок не заведён")
        }
    }

    /// Обрезан, а копий нет (первая запись новой сборки): щенок не пропадает молча — читатель видит ошибку,
    /// а запись откладывает файл в corrupt-<дата>, ничего не стирая.
    func testTruncatedWithoutCopiesIsQuarantinedNotDeleted() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-upgrade")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        let raw = try upData("w45")
        let cut = Data(raw.prefix(raw.count / 3))
        try cut.write(to: store.stateURL)
        XCTAssertThrowsError(try store.read(), "не «первый запуск»")
        XCTAssertEqual(try Data(contentsOf: store.stateURL), cut, "читатель файл не трогает")
        try store.mutate { (_: inout SaveFile) -> Void in }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let folder = try XCTUnwrap(names.first { $0.hasPrefix("corrupt-") }, "\(names)")
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(folder).appendingPathComponent("state.json")), cut,
                       "испорченный файл лежит как был")
    }
}
