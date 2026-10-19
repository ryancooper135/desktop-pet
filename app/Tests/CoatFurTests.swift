// Шерсть в 3D (CoatFur, волна 11): текстура штрихами (сид, размер, стадии), коробочная развёртка,
// клочки на спине (сколько, где, после расчёсывания). Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let fT0: Double = 1_760_000_000
/// Основа Шибы (style_a.json: Main) и светлая (Main_Light).
private let fMain: UInt32 = 0xE9A15B
private let fLight: UInt32 = 0xFFF1DE

/// Щенок час от роду днём, look 0 — колтуны (как BrushTests.bDull и сид brush).
private func fDull() -> (SaveFile, Double) {
    let probe = SaveFile.fresh(now: fT0)
    var t0 = fT0
    while PetEngine.petNight(t0, Catalog.rules, probe.owner) || PetEngine.petNight(t0 + 7200, Catalog.rules, probe.owner) {
        t0 += 1800
    }
    var f = SaveFile.fresh(now: t0)
    let t = t0 + 3600
    PetRunner.catchUp(&f, now: t)
    for n in [Need.food, .energy, .fun, .love, .walk, .clean] { f.pet.needs[n] = 80 }
    f.pet.needs[.look] = 0
    f.pet.hearts = PetEngine.maxHearts(f.pet, Catalog.rules)
    return (f, t)
}

final class CoatFurTests: XCTestCase {
    // MARK: текстура

    func testPixelsDeterministicBySeed() {
        for st in CoatStage.allCases {
            XCTAssertEqual(CoatFur.pixels(stage: st, base: fMain), CoatFur.pixels(stage: st, base: fMain), st.rawValue)
        }
        XCTAssertNotEqual(CoatFur.pixels(stage: .normal, base: fMain, seed: 1),
                          CoatFur.pixels(stage: .normal, base: fMain, seed: 2), "другой сид — другие штрихи")
    }

    func testSizeAndOpaque() {
        for size in [64, 128, 256] {
            let px = CoatFur.pixels(stage: .shaggy, base: fMain, size: size)
            XCTAssertEqual(px.count, size * size * 4)
            XCTAssertTrue(stride(from: 3, to: px.count, by: 4).allSatisfy { px[$0] == 255 }, "непрозрачная")
        }
        XCTAssertEqual(CoatFur.size, 128)
        XCTAssertTrue((128...256).contains(CoatFur.size), "ROADMAP: 128–256 px")
    }

    func testStagesDiffer() {
        let px = CoatStage.allCases.map { CoatFur.pixels(stage: $0, base: fMain) }
        // Все четыре разные.
        XCTAssertEqual(Set(px.map { $0.hashValue }).count, 4)
        // Чем запущеннее — тем «шумнее» и темнее: matted > shaggy > normal > sleek по разбросу.
        let rough = px.map(CoatFur.roughness)
        XCTAssertGreaterThan(rough[0], rough[1], "колтуны шумнее лохматой")
        XCTAssertGreaterThan(rough[1], rough[2], "лохматая шумнее обычной")
        XCTAssertGreaterThan(rough[2], rough[3], "обычная шумнее гладкой")
        let lum = px.map { CoatFur.mean($0).sum() }
        XCTAssertLessThan(lum[0], lum[1])
        XCTAssertLessThan(lum[1], lum[2])
        XCTAssertLessThan(lum[2], lum[3], "гладкая светлее")
    }

    func testColorStaysNearBase() {
        // Стиль A: штрихи поверх плоского цвета, а не новая окраска. Средний цвет — рядом с основой.
        for base in [fMain, fLight] {
            let b = SIMD3<Double>(Double((base >> 16) & 0xff), Double((base >> 8) & 0xff), Double(base & 0xff)) / 255
            for st in CoatStage.allCases {
                let m = CoatFur.mean(CoatFur.pixels(stage: st, base: base))
                let d = m - b
                // Колтуны заметно тусклее (shade 0,92 и пятна), остальные — почти основа.
                let limit = st == .matted ? 0.2 : (st == .shaggy ? 0.12 : 0.08)
                XCTAssertLessThan((d * d).sum().squareRoot(), limit, "\(st.rawValue) \(String(base, radix: 16))")
            }
        }
        // Рыжая остаётся рыжей: красный > зелёный > синий у каждой стадии.
        for st in CoatStage.allCases {
            let m = CoatFur.mean(CoatFur.pixels(stage: st, base: fMain))
            XCTAssertTrue(m.x > m.y && m.y > m.z, st.rawValue)
        }
    }

    func testSleekHasFewerStrokesThanShaggy() {
        let s = CoatFur.style(.sleek), sh = CoatFur.style(.shaggy), m = CoatFur.style(.matted)
        XCTAssertLessThan(s.strokes, sh.strokes)
        XCTAssertLessThanOrEqual(sh.strokes, m.strokes)
        XCTAssertLessThanOrEqual(m.strokes, CoatFur.maxStrokes)
        XCTAssertLessThanOrEqual(m.blotches, CoatFur.maxBlotches)
        XCTAssertEqual(s.blotches, 0, "у гладкой пятен нет")
        XCTAssertGreaterThan(m.blotches, sh.blotches)
        XCTAssertGreaterThan(s.light, sh.light, "у гладкой штрихи светлые")
    }

    func testTileable() {
        // Штрих за краем продолжается с другой стороны: разница между последним и первым столбцом
        // не больше, чем между соседними внутри.
        let n = CoatFur.size
        let px = CoatFur.pixels(stage: .matted, base: fMain)
        func lum(_ x: Int, _ y: Int) -> Double {
            let i = (y * n + x) * 4
            return Double(px[i]) + Double(px[i + 1]) + Double(px[i + 2])
        }
        func colDiff(_ a: Int, _ b: Int) -> Double { (0..<n).map { abs(lum(a, $0) - lum(b, $0)) }.reduce(0, +) }
        let inner = (1..<(n - 1)).map { colDiff($0, $0 + 1) }.reduce(0, +) / Double(n - 2)
        XCTAssertLessThan(colDiff(n - 1, 0), inner * 2.5, "шов по краю")
    }

    // MARK: развёртка

    func testAxesOfShiba() {
        // Рамка меша shiba.glb: x — ширина, y — длина, z — высота.
        let ax = CoatFur.axes(lo: SIMD3(-0.0052, -0.024, 0), hi: SIMD3(0.0052, 0.015, 0.031))
        XCTAssertEqual(ax.width, 0)
        XCTAssertEqual(ax.length, 1)
        XCTAssertEqual(ax.up, 2)
        // Тело usdz (Y вверх, морда к +Z): ширина x, длина z, высота y.
        let b = CoatFur.axes(lo: WearMesh.restMin, hi: WearMesh.restMax)
        XCTAssertEqual(b.width, 0)
        XCTAssertEqual(b.length, 2)
        XCTAssertEqual(b.up, 1)
    }

    func testBoxUVsByNormal() {
        let lo = SIMD3<Float>(-0.5, 0, -1.6), hi = SIMD3<Float>(0.5, 3, 2.4)   // длина 4 по z
        let p = SIMD3<Float>(0.5, 1.5, 0.4)
        let side = CoatFur.boxUVs(positions: [p], normals: [SIMD3(1, 0, 0)], indices: [], lo: lo, hi: hi, tiles: 4)
        // Бок: u — по длине (z), v — по высоте (y); 4 повтора на 4 единицы длины.
        XCTAssertEqual(side[0].x, 2.0, accuracy: 1e-5)
        XCTAssertEqual(side[0].y, 1.5, accuracy: 1e-5)
        let top = CoatFur.boxUVs(positions: [p], normals: [SIMD3(0, 1, 0)], indices: [], lo: lo, hi: hi, tiles: 4)
        XCTAssertEqual(top[0].x, 2.0, accuracy: 1e-5, "спина: u тоже по длине")
        XCTAssertEqual(top[0].y, 1.0, accuracy: 1e-5)
        let front = CoatFur.boxUVs(positions: [p], normals: [SIMD3(0, 0.2, 1)], indices: [], lo: lo, hi: hi, tiles: 4)
        XCTAssertEqual(front[0].x, 1.0, accuracy: 1e-5, "грудь: u по ширине")
        XCTAssertEqual(front[0].y, 1.5, accuracy: 1e-5)
    }

    func testBoxUVsWithoutNormals() {
        // Нет нормалей — по треугольникам: плоский квадрат в плоскости y = const — «спина».
        let pos: [SIMD3<Float>] = [SIMD3(0, 1, 0), SIMD3(0, 1, 1), SIMD3(1, 1, 1), SIMD3(1, 1, 0)]
        let uv = CoatFur.boxUVs(positions: pos, normals: nil, indices: [0, 1, 2, 0, 2, 3],
                                lo: SIMD3(0, 0, -2), hi: SIMD3(1, 2, 2), tiles: 4)
        XCTAssertEqual(uv.count, 4)
        XCTAssertTrue(uv.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        XCTAssertEqual(uv[1].x - uv[0].x, 1, accuracy: 1e-5, "u по длине (z)")
        XCTAssertEqual(uv[3].y - uv[0].y, 1, accuracy: 1e-5, "v по ширине (x)")
    }

    // MARK: клочки

    func testRestTufts() {
        XCTAssertEqual(CoatFur.restTufts(.matted, brushedAgo: nil, cooldownH: 6), Brush.tufts(.matted))
        XCTAssertEqual(CoatFur.restTufts(.shaggy, brushedAgo: nil, cooldownH: 6), Brush.tufts(.shaggy))
        XCTAssertEqual(CoatFur.restTufts(.normal, brushedAgo: nil, cooldownH: 6), 0)
        XCTAssertEqual(CoatFur.restTufts(.sleek, brushedAgo: nil, cooldownH: 6), 0)
        XCTAssertEqual(CoatFur.restTufts(.shaggy, brushedAgo: 3600, cooldownH: 6), 0, "только что расчесали")
        XCTAssertEqual(CoatFur.restTufts(.shaggy, brushedAgo: 7 * 3600, cooldownH: 6), 4, "откат прошёл")
        XCTAssertEqual(CoatFur.restTufts(.matted, brushedAgo: -60, cooldownH: 6), 6, "метка из будущего не держит")
        XCTAssertEqual(CoatFur.restTufts(.matted, brushedAgo: 3600, cooldownH: 0), 0, "без правил — 6 ч")
    }

    func testTuftGeometry() {
        let joints = Set(WearMesh.backJoints.map(\.joint))
        for st in CoatStage.allCases {
            let n = Brush.tufts(st)
            var lastZ = Float.infinity
            for i in 0..<n {
                let parts = CoatFur.tuft(i, of: n, stage: st)
                XCTAssertFalse(parts.isEmpty, "\(st.rawValue) \(i)")
                let spot = CoatFur.tuftSpot(i, of: n)
                XCTAssertLessThan(spot.z, lastZ, "от головы к хвосту")
                lastZ = spot.z
                for p in parts {
                    XCTAssertTrue(joints.contains(p.joint), p.joint)
                    XCTAssertEqual(p.positions.count, p.normals.count)
                    XCTAssertEqual(p.indices.count % 3, 0)
                    XCTAssertTrue(p.indices.allSatisfy { Int($0) < p.positions.count })
                    for v in p.positions {
                        XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite)
                        // На спине: выше оси спины, в длину спины, не дальше полуметра от поверхности.
                        XCTAssertGreaterThan(v.y, WearMesh.backAxisY)
                        XCTAssertTrue((-0.7...1.3).contains(v.z), "\(v)")
                        XCTAssertLessThan(abs(v.x), 0.9)
                    }
                }
            }
        }
    }

    func testTuftJointFollowsBack() {
        XCTAssertEqual(CoatFur.joint(z: -0.4), "Torso")
        XCTAssertEqual(CoatFur.joint(z: 0.3), "Torso2")
        XCTAssertEqual(CoatFur.joint(z: 0.9), "Torso3")
        XCTAssertEqual(CoatFur.joint(z: -3), "Torso")
        XCTAssertEqual(CoatFur.joint(z: 3), "Torso3")
    }

    func testTuftColorsDarkerWhenMatted() {
        func lum(_ h: UInt32) -> UInt32 { ((h >> 16) & 0xff) + ((h >> 8) & 0xff) + (h & 0xff) }
        XCTAssertLessThan(lum(CoatFur.tuftColors(.matted).main), lum(CoatFur.tuftColors(.shaggy).main))
        XCTAssertLessThan(lum(CoatFur.tuftColors(.shaggy).main), lum(CoatFur.tuftColors(.sleek).main))
    }

    func testTuftColorsFollowCharacterFur() {
        // Серый свой персонаж: пучки серые (каналы равны), колтун темнее, кончики светлее; без цвета — как было.
        let grey: UInt32 = 0x8a8f99
        let normal = CoatFur.tuftColors(.normal, fur: grey)
        XCTAssertEqual(normal.main, grey)
        XCTAssertGreaterThan(normal.tip & 0xff, grey & 0xff)
        let matted = CoatFur.tuftColors(.matted, fur: grey)
        XCTAssertLessThan((matted.main >> 16) & 0xff, (grey >> 16) & 0xff)
        XCTAssertLessThan(matted.main & 0xff, grey & 0xff)
        XCTAssertEqual(CoatFur.tuftColors(.shaggy, fur: 0xffffff).tip, 0xffffff)
        XCTAssertEqual(CoatFur.tuftColors(.matted, fur: nil).main, 0x9c5f2e)
    }

    // MARK: шерсть из сейва

    func testLookCarriesTuftsAndBrushClearsThem() {
        var (f, t) = fDull()
        let before = Coat.look(f, now: t)
        XCTAssertEqual(before.stage, .matted)
        XCTAssertEqual(before.tufts, 6, "колтуны — шесть клочков, как Brush.tufts")
        XCTAssertTrue(Brush.finish(&f, now: t).ok)
        let after = Coat.look(f, now: t + 60)
        XCTAssertEqual(after.stage, .shaggy)
        XCTAssertEqual(after.tufts, 0, "только что расчесали — клочков нет, хоть и лохматый")
        XCTAssertEqual(Coat.look(f, now: t + 3 * 3600).tufts, 0)
        XCTAssertNotEqual(before, after)
    }

    /// Как сиды fur_shaggy / fur_brushed в LaunchSeed (снимки ui-71/72): новорождённый щенок днём, look 50.
    private func furSeed(brushed: Bool) -> (SaveFile, Double) {
        let (dull, _) = fDull()
        let now = dull.createdT + 60
        var f = SaveFile.fresh(now: dull.createdT)
        PetRunner.catchUp(&f, now: now)
        for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
        f.pet.needs[.look] = 50
        if brushed {
            f.createdT = min(f.createdT, now - 3 * 3600)
            f.log(Brush.actKind, t: now - 2 * 3600, source: .app, ok: true)
            XCTAssertTrue(Brush.finish(&f, now: now).ok)
        }
        return (f, now)
    }

    func testSnapshotSeeds() {
        let (shaggy, t1) = furSeed(brushed: false)
        let a = Coat.look(shaggy, now: t1)
        XCTAssertEqual(a.stage, .shaggy, "ui-71: лохматая")
        XCTAssertEqual(a.tufts, Brush.tufts(.shaggy))
        let (sleek, t2) = furSeed(brushed: true)
        let b = Coat.look(sleek, now: t2)
        XCTAssertEqual(b.stage, .sleek, "ui-72: гладкая")
        XCTAssertEqual(b.tufts, 0)
        XCTAssertGreaterThan(b.shine, a.shine)
    }

    func testLegacyBrushJournalAlsoClears() {
        var (f, t) = fDull()
        f.log(Brush.journalKind, t: t - 600, value: CoatStage.matted.rank)
        let look = Coat.look(f, now: t)
        XCTAssertEqual(look.tufts, 0, "запись «brush» до волны 10 тоже считается")
    }
}
