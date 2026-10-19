// Аудит пятой волны: как экономика, капсула, вкусы, шерсть и открытки работают вместе через PetRunner,
// PetStore и SaveFile. Каждый тест — найденный стык: порядок вызовов, startOver, старые сейвы, имена типов,
// цена вызовов для виджета. Гоняется и на Linux (app/Package.swift), поэтому только Shared и PetCore.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let sT0: Double = 1_760_000_000

/// Свежий файл с заданным petId, шкалы на level.
private func sFile(_ petId: String = "seam-pet", at t: Double = sT0, level: Double = 90) -> SaveFile {
    var f = SaveFile.fresh(now: t)
    f.petId = petId
    for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = level }
    return f
}

/// Открытка-заглушка за день d (сохранённая или нет).
private func sCard(day d: Int, saved: Bool) -> Postcard {
    Postcard(id: "c\(d)", day: d, kind: "play", t: Double(d) * 86400 + 43200, tz: 0, score: 35,
             caption: "Играли весь день с мячиком.", lineId: "card_play_1", find: nil, item: nil, count: nil,
             pose: "happy", clip: "gallop_jump", prop: "ball", expiresT: Double(d + 8) * 86400,
             savedT: saved ? Double(d + 1) * 86400 : nil, image: saved ? "c\(d).heic" : nil)
}

/// Сейв как JSON-объект (JSONValue: на Linux JSONSerialization превращает true/false в числа).
private func sObject(_ f: SaveFile) throws -> [String: JSONValue] {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(f)).object
}

private func sDecode(_ o: [String: JSONValue]) throws -> SaveFile {
    try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(JSONValue.object(o)))
}

private func ms(_ d: Duration) -> Double {
    Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

final class Wave5SeamTests: XCTestCase {

    // MARK: имена типов

    /// Shared компилируется в один модуль с экранами (цели Pet и PetWidgets в project.yml). Тип модуля с именем
    /// типа SwiftUI затеняет его: `enum Capsule` ломал `Capsule()` во всех вью. Linux этого не видит — ловим по исходникам.
    func testSharedDoesNotShadowSwiftUITypes() throws {
        let swiftUI: Set<String> = [
            "Capsule", "Circle", "Rectangle", "RoundedRectangle", "UnevenRoundedRectangle", "Ellipse", "Path", "Shape",
            "Text", "Image", "Label", "Color", "Gradient", "LinearGradient", "RadialGradient", "AngularGradient",
            "Button", "Toggle", "Picker", "Link", "Menu", "Group", "Section", "Spacer", "Divider", "Font", "Animation",
            "Canvas", "TimelineView", "Grid", "Material", "ForEach", "HStack", "VStack", "ZStack", "ScrollView",
            "ProgressView", "GeometryReader", "Angle", "Edge", "Alignment", "Transaction", "Namespace", "Environment",
        ]
        let shared = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Shared")
        let files = try FileManager.default.contentsOfDirectory(atPath: shared.path).filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty, "нет исходников в \(shared.path)")
        let re = try NSRegularExpression(
            pattern: #"^\s*(?:(?:public|internal|private|fileprivate|final|indirect)\s+)*(?:enum|struct|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            options: [.anchorsMatchLines])
        var clashes: [String] = []
        for name in files {
            let text = try String(contentsOf: shared.appendingPathComponent(name), encoding: .utf8)
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let type = ns.substring(with: m.range(at: 1))
                if swiftUI.contains(type) { clashes.append("\(name): \(type)") }
            }
        }
        XCTAssertEqual(clashes, [], "типы в Shared затеняют SwiftUI в приложении и виджетах")
    }

    // MARK: порядок в PetRunner

    /// AppModel.becameActive: applyBuild, потом catchUp. Прогулка, что кончилась во время паузы подписи,
    /// должна дать то же, что обычный догон: запись ev.back_home (открытка «находка») и наблюдение вкуса.
    func testSignPauseKeepsWalkReturn() throws {
        var f = sFile()
        let fav = try XCTUnwrap(Tastes.hidden(petId: f.petId, .find).love)
        f.pet.outing = Outing(from: sT0, until: sT0 + 3600, find: fav)
        f.build = SaveFile.BuildInfo(expiresT: sT0 + 3 * 3600, seenT: sT0)
        let now = sT0 + 10 * 3600

        var control = f
        PetRunner.catchUp(&control, now: now)
        XCTAssertEqual(Tastes.progress(.find, fav, in: control), 1, "обычный догон видит находку")
        XCTAssertTrue(control.journal.contains { $0.kind.hasPrefix("ev.back_home") })

        PetRunner.applyBuild(&f, expires: Date(timeIntervalSince1970: now + 7 * 86400), now: now)
        PetRunner.catchUp(&f, now: now)
        XCTAssertNil(f.pet.outing, "вернулся")
        XCTAssertEqual(f.pet.finds[fav], control.pet.finds[fav])
        XCTAssertEqual(f.journal.last { $0.kind != "taste.open" }?.kind, "sign_pause")
        XCTAssertEqual(Tastes.progress(.find, fav, in: f), 1, "вкус находки после паузы подписи не потерян")
        XCTAssertTrue(f.journal.contains { $0.kind.hasPrefix("ev.back_home") }, "возвращение есть в журнале")
    }

    /// Виджет зовёт Postcards.latest без записи. После полуночи он должен показать ту же открытку,
    /// что соберёт первая запись (catchUp), даже если вчерашние события ещё не в журнале.
    func testWidgetCardMatchesNextWrite() throws {
        let tz = Clock.tzOffsetMin(at: sT0)
        let d = DayKey.of(sT0, tzOffsetMin: tz)
        var f = sFile(at: DayKey.start(d - 1, tzOffsetMin: tz) + 9 * 3600)
        f.owner.tzOffsetMin = tz
        f.cards.doneDay = d - 1
        // День d: в 14:00 Шиба ушёл гулять, больше в тот день ничего не писали.
        let walkT = DayKey.start(d, tzOffsetMin: tz) + 14 * 3600
        let find = try XCTUnwrap(Tastes.candidates(.find).first)
        f.pet.t = walkT
        f.pet.outing = Outing(from: walkT, until: walkT + 3600, find: find)
        let now = DayKey.start(d + 1, tzOffsetMin: tz) + 9 * 3600

        let widget = Postcards.latest(f, now: now)
        var w = f
        PetRunner.catchUp(&w, now: now)
        let written = try XCTUnwrap(Postcards.latest(w, now: now), "запись собрала открытку за день d")
        XCTAssertEqual(written.day, d)
        XCTAssertEqual(widget?.id, written.id, "виджет до записи видит ту же открытку")
        XCTAssertEqual(widget?.kind, written.kind)
        XCTAssertEqual(widget?.caption, written.caption)
    }

    /// Одно действие — одна оплата, в каком бы порядке ни шли догон, пауза подписи, капсула и часы назад.
    func testCoinsPaidOncePerAction() throws {
        var f = sFile()
        var paid = 0
        var oks = 0
        var t = sT0
        for i in 0..<12 {
            t += 1800
            if i == 5 {
                // Подпись кончилась через 10 минут после последней записи, приложение открыли через 3 часа.
                f.build = SaveFile.BuildInfo(expiresT: f.pet.t + 600, seenT: f.pet.t)
                t += 3 * 3600
                PetRunner.applyBuild(&f, expires: Date(timeIntervalSince1970: t + 86400), now: t)
                XCTAssertEqual(f.journal.last?.kind, "sign_pause")
            }
            if i == 7 { _ = CapsuleMachine.pull(&f, pay: .ticket, now: t) }
            let now = i == 9 ? t - 3600 : t   // часы назад на час
            let out = PetRunner.apply(i.isMultiple(of: 2) ? .pet : .play, source: .app, to: &f, now: now)
            paid += out.coins
            if out.ok { oks += 1 }
            // Повторный settle (как будто второй писатель) ничего не добавляет.
            XCTAssertTrue(Economy.settle(&f).isEmpty)
        }
        XCTAssertGreaterThan(oks, 0)
        XCTAssertEqual(f.econ.wallet.coins, EconomyConfig.shared.coinsStart + paid, "капсула за билетик монет не тратит")
        XCTAssertEqual(f.econ.paidSeq, f.seq, "оплачено всё до последней записи")
    }

    // MARK: начать заново

    /// Решение аудита (config/economy.json death.keep: album): сохранённые открытки — память хозяина и переходят
    /// новому щенку; ждущие решения (снимки старого) и doneDay — нет. Вкусы привязаны к petId: у нового щенка
    /// другие, поэтому лог вкусов не переносится (старый файл остаётся в state.broken-<t>.json для страницы памяти).
    func testStartOverKeepsAlbumDropsTastes() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-seam")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        let tz = Clock.tzOffsetMin(at: sT0)
        let d = DayKey.of(sT0, tzOffsetMin: tz)
        try store.startOver(now: sT0)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.cards.album = [sCard(day: d - 5, saved: true), sCard(day: d - 3, saved: true)]
            f.cards.pending = [sCard(day: d - 1, saved: false)]
            f.cards.doneDay = d - 1
            let love = Tastes.hidden(petId: f.petId, .food).love ?? "kibble"
            Tastes.observe(.food, love, at: sT0, in: &f)
        }
        let old = try XCTUnwrap(store.read())
        XCTAssertFalse(old.tastes.isEmpty)

        let restart = sT0 + 100
        try store.startOver(now: restart)
        var f = try XCTUnwrap(store.read())
        XCTAssertNotEqual(f.petId, old.petId)
        XCTAssertEqual(f.cards.album.map(\.id), ["c\(d - 5)", "c\(d - 3)"], "альбом переживает щенка")
        XCTAssertEqual(f.cards.album.first?.image, "c\(d - 5).heic")
        XCTAssertTrue(f.cards.pending.isEmpty, "несохранённые открытки старого щенка не переходят")
        XCTAssertNil(f.cards.doneDay)
        XCTAssertTrue(f.tastes.isEmpty, "вкусы — нового щенка")

        // Открытка нового щенка не сталкивается с альбомом старого: его дни раньше дня знакомства.
        let next = DayKey.start(DayKey.of(restart, tzOffsetMin: f.owner.tzOffsetMin) + 1,
                                      tzOffsetMin: f.owner.tzOffsetMin) + 600
        PetRunner.catchUp(&f, now: next)
        XCTAssertEqual(f.cards.pending.map(\.kind), ["first_day"])
        XCTAssertEqual(f.cards.album.count, 2)
    }

    // MARK: сейвы

    func testRoundTripWithEconTastesAndCards() throws {
        var f = sFile()
        Economy.grant(&f, coins: 77, tickets: 2, shards: 5)
        _ = CapsuleMachine.pull(&f, pay: .ticket, now: sT0)
        let love = try XCTUnwrap(Tastes.hidden(petId: f.petId, .food).love)
        for i in 0..<Tastes.needed(.food) { Tastes.observe(.food, love, at: sT0 + Double(i) * Tastes.gap, in: &f) }
        f.cards.pending = [sCard(day: 20_300, saved: false)]
        f.cards.album = [sCard(day: 20_290, saved: true)]
        f.cards.doneDay = 20_300
        _ = PetRunner.apply(.pet, source: .widget, to: &f, now: sT0 + 3 * 3600)

        let back = try JSONDecoder().decode(SaveFile.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.econ, f.econ)
        XCTAssertEqual(back.tastes, f.tastes)
        XCTAssertEqual(back.cards, f.cards)
        XCTAssertEqual(back.journal, f.journal)
        XCTAssertEqual(back.seq, f.seq)
        XCTAssertFalse(back.tastes.opened.isEmpty)
        XCTAssertFalse(back.econ.items.isEmpty)
        // Второй круг даёт тот же файл байт в байт (sortedKeys, как пишет PetStore).
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try enc.encode(back), try enc.encode(try JSONDecoder().decode(SaveFile.self, from: enc.encode(back))))
    }

    /// Старый сейв, где есть только одно из трёх новых полей: остальные — по умолчанию, ничего не теряется.
    func testOldSavesWithOnlyOneNewField() throws {
        var f = sFile()
        Economy.grant(&f, coins: 10)
        let love = try XCTUnwrap(Tastes.hidden(petId: f.petId, .food).love)
        Tastes.observe(.food, love, at: sT0, in: &f)
        f.cards.album = [sCard(day: 20_290, saved: true)]
        f.cards.doneDay = 20_300
        for i in 0..<5 { f.log("act.pet", t: sT0 + Double(i), source: .app, ok: true) }
        f.econ.paidSeq = f.seq
        let full = try sObject(f)
        for k in ["econ", "tastes", "cards"] { XCTAssertNotNil(full[k], k) }

        func only(_ key: String) throws -> SaveFile {
            var o = full
            for k in ["econ", "tastes", "cards"] where k != key { o.removeValue(forKey: k) }
            return try sDecode(o)
        }
        let e = try only("econ")
        XCTAssertEqual(e.econ, f.econ)
        XCTAssertTrue(e.tastes.isEmpty)
        XCTAssertEqual(e.cards, PostcardBook())

        let t = try only("tastes")
        XCTAssertEqual(t.tastes, f.tastes)
        XCTAssertEqual(t.econ, Econ.start(paidSeq: f.seq), "без econ — стартовый кошелёк, журнал задним числом не оплачен")
        XCTAssertEqual(t.cards, PostcardBook())

        let c = try only("cards")
        XCTAssertEqual(c.cards, f.cards)
        XCTAssertTrue(c.tastes.isEmpty)
        XCTAssertEqual(c.econ.paidSeq, f.seq)

        // Ни одного нового поля — как сейв четвёртой волны.
        let none = try only("-")
        XCTAssertEqual(none.econ, Econ.start(paidSeq: f.seq))
        XCTAssertTrue(none.tastes.isEmpty)
        XCTAssertEqual(none.cards, PostcardBook())
        var g = none
        XCTAssertTrue(Economy.settle(&g).isEmpty, "старые действия не оплачиваются при первой записи")
    }

    // MARK: цена для виджета

    /// Сколько стоят Coat.look и Postcards.active на ленте виджета (48 кадров по 30 минут) и сколько весит файл
    /// с полным альбомом. Печатает замеры (debug-сборка на Linux — оценка сверху); проверяет только размер.
    func testWidgetCostAndFileSize() throws {
        let start = sT0 - 8 * 86400
        var f = sFile(at: start)
        var t = start
        var i = 0
        while t < sT0 {
            t += 1800
            let a: PetAction = i % 24 == 0 ? .bath : (i % 8 == 0 ? .feed(Catalog.mainFood) : .pet)
            _ = PetRunner.apply(a, source: .app, to: &f, now: t)
            i += 1
        }
        XCTAssertEqual(f.journal.count, SaveFile.journalMax, "журнал заполнен")
        f.cards.album = (0..<PostcardBook.albumMax).map { sCard(day: 20_000 + $0, saved: true) }
        f.econ.items = Dictionary(uniqueKeysWithValues: EconomyConfig.shared.capsule.itemsById.keys.map { ($0, 1) })

        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let total = try enc.encode(f).count
        var noAlbum = f
        noAlbum.cards.album = []
        let albumBytes = total - (try enc.encode(noAlbum).count)
        var noLogs = noAlbum
        noLogs.journal = []
        noLogs.outbox = []
        let logBytes = (try enc.encode(noAlbum).count) - (try enc.encode(noLogs).count)
        let econBytes = try enc.encode(f.econ).count
        let tasteBytes = try enc.encode(f.tastes).count
        print("[seam] файл \(total) Б: альбом \(PostcardBook.albumMax) шт. \(albumBytes) Б, журнал+outbox \(logBytes) Б, econ \(econBytes) Б, tastes \(tasteBytes) Б")
        XCTAssertLessThan(total, 300_000, "файл в App Group читается виджетом на каждом обновлении")

        let clock = ContinuousClock()
        let frames = (0..<48).map { sT0 + Double($0) * 1800 }
        var sink = 0.0
        let peek = clock.measure { for t in frames { sink += PetRunner.peek(f, at: t).hearts } }
        let coat = clock.measure { for t in frames { sink += Coat.look(f, now: t).groom } }
        let cards = clock.measure { for t in frames { sink += Double(Postcards.active(f, now: t).count) } }
        var stale = f
        stale.cards.doneDay = nil
        let cardsStale = clock.measure { for t in frames { sink += Double(Postcards.active(stale, now: t).count) } }
        let decode = clock.measure { for _ in 0..<10 { sink += (try? JSONDecoder().decode(SaveFile.self, from: enc.encode(f)))?.pet.hearts ?? 0 } }
        print(String(format: "[seam] 48 кадров: peek %.1f мс, Coat.look %.1f мс, Postcards.active %.1f мс (неразобранные дни %.1f мс); чтение файла %.1f мс",
                     ms(peek), ms(coat), ms(cards), ms(cardsStale), ms(decode) / 10))
        XCTAssertFalse(sink.isNaN)
    }
}
