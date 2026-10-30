// Волна 34 J: снимки нового виджета-«экранчика» и карточек острова (§8) — тем же механизмом, что WidgetSnapshotTests
// (ImageRenderer → PNG в $SNAPSHOT_DIR и вложения xcresult). Имена ui-34-widget-* и ui-34-island-*.
// Время заморожено (petFrozenNow): таймеры и полоска похода стоят на месте — снимки стабильны.
// Только iOS: в Linux-сборке логики вью нет (Package.swift, exclude).

import SwiftUI
import UIKit
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class IslandLookSnapshotTests: XCTestCase {
    /// Кадры виджета: настроение × копилка (доля) × ярус двора.
    @MainActor
    static func widgetLooks() -> [(name: String, look: WidgetLook, t: Double)] {
        let t = PreviewFixtures.dayT
        return [
            ("fed", PreviewFixtures.widgetLook("fed", bank: 0.6, tier: 1), t),
            ("bank-full", PreviewFixtures.widgetLook("fed", bank: 1.2, tier: 3), t),
            ("hungry", PreviewFixtures.widgetLook("hungry", tier: 0), t),
            ("critical", PreviewFixtures.widgetLook("critical", tier: 0), t),
            ("walking", PreviewFixtures.widgetLook("walking", bank: 0.3, tier: 2), t),
            ("asleep", PreviewFixtures.widgetLook("asleep", bank: 0.8, tier: 2), t),
            // Волна 45 O: просьба пса — плашка «Почеши за ушком? · ещё 40 мин» вместо подписи.
            ("ask", PreviewFixtures.widgetLook("fed", bank: 0.6, tier: 1, ask: "pet"), t),
            // Волна 51: «что сейчас» — занятие с таймером без кнопки, нужда с кнопкой «Помыть».
            ("status-bath", statusLook { f, t in f.pet.bathUntil = t + 180 }, t),
            ("status-nap", statusLook { f, t in f.pet.needs[.energy] = 30; f.pet.napUntil = t + 1500 }, t),
            ("status-need", statusLook { f, _ in f.pet.needs[.clean] = 10 }, t),
        ]
    }

    /// Волна 51: сейв «сыт и доволен» с правкой → сейв на «сейчас» (PetStatusLogic внутри WidgetLook.looks).
    static func statusFile(_ edit: (inout SaveFile, Double) -> Void) -> (file: SaveFile, t: Double) {
        let r = PreviewFixtures.file("fed")
        var f = r.file
        edit(&f, r.t)
        return (f, r.t)
    }

    @MainActor
    static func statusLook(_ edit: (inout SaveFile, Double) -> Void) -> WidgetLook {
        let (f, t) = statusFile(edit)
        return WidgetLook.looks(f, now: t, tzOffsetMin: 0, asks: []).first ?? WidgetLook.empty(t: t)
    }

    /// Волна 51: карточки острова «что сейчас» (IslandLook.statusCard) — моется, дремлет, нужда с кнопкой.
    static func statusCards() -> [(name: String, card: IslandCard)] {
        let edits: [(String, (inout SaveFile, Double) -> Void)] = [
            ("status-bath", { f, t in f.pet.bathUntil = t + 180 }),
            ("status-nap", { f, t in f.pet.needs[.energy] = 30; f.pet.napUntil = t + 1500 }),
            ("status-need", { f, _ in f.pet.needs[.clean] = 10 }),
        ]
        return edits.map { name, edit in
            let (f, t) = statusFile(edit)
            return (name, IslandLook.statusCard(PetStatusLogic.of(f, now: t, tzOffsetMin: 0), at: t))
        }
    }

    /// Карточки острова по одной на событие §8 — из настоящей логики (IslandEvents.candidates → IslandLook.card).
    static func islandCards() -> [(name: String, card: IslandCard)] {
        let now = PreviewFixtures.dayT
        var i = IslandInput(now: now, name: "Шиба", alive: true, outlook: IslandOutlook())
        i.outlook.lastChanceAt = now - 600
        i.outlook.deathAt = now + 5400
        i.outlook.hunger = [IslandSpan(from: now - 600, until: nil)]
        i.trip = IslandTrip(from: now - 1800, backAt: now + 2400, place: "Маяк")
        i.bank = IslandBank(fullAt: now - 60, from: now - 12 * 3600, coins: 214)
        i.levelUp = IslandLevelUp(level: 14, at: now - 10)
        i.ask = IslandAsk(kind: "pet", start: now - 1200, end: now + 2400, coins: 10)
        var home = i
        home.trip = IslandTrip(from: now - 5400, backAt: now - 60, place: "Маяк")
        var lost = i
        lost.outlook.deathAt = now - 3600
        lost.outlook.lastChanceAt = nil

        let all = IslandEvents.candidates(i) + IslandEvents.candidates(home) + IslandEvents.candidates(lost)
        var out: [(String, IslandCard)] = []
        for kind in IslandEvent.Kind.allCases {
            // Идущее сейчас: побег — из «потерялся», дома — из второго входа.
            let source = kind == .runaway ? IslandEvents.candidates(lost)
                : kind == .home ? IslandEvents.candidates(home) : all
            guard let e = source.first(where: { $0.kind == kind && $0.from <= now }) else { continue }
            var c = IslandLook.card(e)
            if kind == .lastChance { c.act = .heal }
            if kind == .ask { c.act = .pet }   // пёс не спит, ядро примет — кнопка просьбы (IslandPick.calm)
            out.append((kind.rawValue, c))
        }
        out.append(("rest", IslandLook.rest(name: "Шиба", night: false, at: now)))
        return out
    }

    @MainActor
    static func cases() -> [SnapshotCase] {
        var out: [SnapshotCase] = []
        func add(_ name: String, _ family: SnapshotFamily, _ scheme: ColorScheme, t: Double, _ v: some View) {
            out.append(SnapshotCase(name: name, size: family.size, cornerRadius: family.cornerRadius, colorScheme: scheme,
                                    view: AnyView(v.environment(\.petFrozenNow, t))))
        }
        for (name, look, t) in widgetLooks() {
            for scheme in [ColorScheme.light, .dark] {
                let s = scheme == .light ? "light" : "dark"
                add("ui-34-widget-small-\(name)-\(s)", .small, scheme, t: t,
                    WidgetScreenSmallView(look: look).padding(14).background(WidgetPlastic()))
                add("ui-34-widget-medium-\(name)-\(s)", .medium, scheme, t: t,
                    WidgetScreenMediumView(look: look).padding(14).background(WidgetPlastic()))
            }
            add("ui-34-widget-large-\(name)", .large, .light, t: t,
                WidgetScreenLargeView(look: look).padding(16).background(WidgetPlastic()))
            add("ui-34-widget-circular-\(name)", .circular, .dark, t: t, WidgetLockCircularView(look: look))
            add("ui-34-widget-rectangular-\(name)", .rectangular, .dark, t: t, WidgetLockRectangularView(look: look))
            add("ui-34-widget-inline-\(name)", .inline, .dark, t: t, WidgetLockInlineView(look: look))
        }
        let t = PreviewFixtures.dayT
        for (name, card) in islandCards() + statusCards() {
            add("ui-34-island-expanded-\(name)", .islandExpanded, .dark, t: t, IslandCardExpandedPreview(card: card))
            add("ui-34-island-compact-\(name)", .islandCompact, .dark, t: t, IslandCardCompactPreview(card: card))
            add("ui-34-island-lock-\(name)", .lockActivity, .light, t: t,
                LockScreenCardView(name: "Шиба", card: card).padding(14).background(PetPalette.card))
        }
        return out
    }

    func testCardsCoverEveryEvent() {
        let names = Set(Self.islandCards().map(\.name))
        for kind in IslandEvent.Kind.allCases {
            XCTAssertTrue(names.contains(kind.rawValue), "нет карточки для \(kind.rawValue)")
        }
    }

    /// Волна 51: карточки «что сейчас» — таймер у занятий, кнопка только у нужды и только доступная.
    func testStatusCards() {
        let cards = Dictionary(uniqueKeysWithValues: Self.statusCards().map { ($0.name, $0.card) })
        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(cards["status-bath"]?.act, .open, "моется — только «Открыть», действия нет")
        XCTAssertEqual(cards["status-nap"]?.act, .open, "дремлет — только «Открыть», действия нет")
        XCTAssertNotNil(cards["status-bath"]?.timerEnd, "моется — таймер")
        XCTAssertEqual(cards["status-need"]?.act, .bath, "грязный — «Помыть»")
    }

    @MainActor
    func testRenderWave34() throws {
        let cases = Self.cases()
        XCTAssertGreaterThan(cases.count, 40)
        let dir = try WidgetSnapshotTests.outputDir()
        var failed: [String] = []
        var blank: [String] = []
        for c in cases {
            guard let image = WidgetSnapshotTests.render(c), let png = image.pngData() else {
                failed.append(c.name)
                continue
            }
            if WidgetSnapshotTests.isUniform(image) { blank.append(c.name) }
            try png.write(to: dir.appendingPathComponent(c.name + ".png"))
            let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            a.name = c.name
            a.lifetime = .keepAlways
            add(a)
        }
        XCTAssertTrue(failed.isEmpty, "Не отрисовались: \(failed.joined(separator: ", "))")
        XCTAssertTrue(blank.isEmpty, "Пустые снимки: \(blank.joined(separator: ", "))")
    }
}
