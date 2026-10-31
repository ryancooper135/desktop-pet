// Свой персонаж — до конца (волна 14): имя в шапке и репликах. У Шибы тексты как были; у своего персонажа
// ни одного «Шибы» не остаётся — имя в именительном или «питомец» в нужном падеже (PetNames).
// Гоняется и на Linux (app/Package.swift).

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

final class PetNamesTests: XCTestCase {
    private let cat = "Мурка"

    // MARK: adapt

    func testShibaTextsUnchanged() {
        for s in Brush.doneLines + Trick.allCases.map(\.done) {
            XCTAssertEqual(PetNames.adapt(s, name: PetNames.shiba), s)
            XCTAssertEqual(PetNames.adapt(s, name: ""), s)
            XCTAssertEqual(PetNames.adapt(s, name: "  Шиба "), s)
        }
        XCTAssertEqual(HomeText.poseText(.idle), "Шиба спокоен")
        XCTAssertEqual(HomeText.poseText(.idle, name: PetNames.shiba), "Шиба спокоен")
        XCTAssertEqual(RefuseText.text("dead", name: PetNames.shiba), "Шибы больше нет")
        XCTAssertEqual(Cooking.reasonText(Cooking.reasons.night), "Ночью кухня закрыта: Шиба спит")
    }

    func testNameOnlyWhereSafe() {
        XCTAssertEqual(PetNames.adapt("Ночью кухня закрыта: Шиба спит", name: cat), "Ночью кухня закрыта: Мурка спит")
        XCTAssertEqual(PetNames.adapt("Фрр! Шиба отряхнулся и сияет", name: cat), "Фрр! Питомец отряхнулся и сияет",
                       "мужской род рядом — «питомец», с большой буквы после «!»")
        XCTAssertEqual(PetNames.adapt("Вода — это хорошо. Шиба согласен", name: cat), "Вода — это хорошо. Питомец согласен")
        XCTAssertEqual(PetNames.adapt("Шибе было весело!", name: cat), "Питомцу было весело!")
        XCTAssertEqual(PetNames.adapt("Спина Шибы", name: cat), "Спина питомца")
        XCTAssertEqual(PetNames.adapt("вместе с Шибой", name: cat), "вместе с питомцем")
        XCTAssertEqual(PetNames.adapt("Веди Шибу пальцем", name: cat), "Веди питомца пальцем")
        XCTAssertEqual(PetNames.adapt("Шибы так умеют", name: cat), "Питомцы так умеют")
        XCTAssertEqual(PetNames.adapt("Без собак", name: cat), "Без собак", "без «Шиб» — как есть")
    }

    func testGone() {
        XCTAssertEqual(PetNames.gone(PetNames.shiba), "Шибы больше нет")
        XCTAssertEqual(PetNames.gone(cat), "Мурка больше не с нами")
        XCTAssertEqual(PetNames.adapt("Шибы больше нет", name: cat), "Мурка больше не с нами")
        XCTAssertEqual(RefuseText.text("dead", name: cat), "Мурка больше не с нами")
        XCTAssertEqual(HomeText.poseText(.dead, name: cat), "Мурка больше не с нами")
    }

    func testNameWithShibaInsideNotDoubled() {
        // Сид charpack зовётся «Серый Шиба»: имя подставляется один раз и само не переписывается.
        let grey = "Серый Шиба"
        XCTAssertFalse(PetNames.isShiba(grey))
        XCTAssertEqual(PetNames.adapt("Ночью кухня закрыта: Шиба спит", name: grey), "Ночью кухня закрыта: Серый Шиба спит")
        XCTAssertEqual(PetNames.adapt("Шибы больше нет", name: grey), "Серый Шиба больше не с нами")
        XCTAssertEqual(PetNames.adapt("Шибе было весело!", name: grey), "Питомцу было весело!")
    }

    func testMasculine() {
        XCTAssertTrue(PetNames.hasMasculine("Шиба принёс тапок"))
        XCTAssertTrue(PetNames.hasMasculine("какой пушистый"))
        XCTAssertTrue(PetNames.hasMasculine("Шиба рад"))
        XCTAssertFalse(PetNames.hasMasculine("Шиба спит"))
        XCTAssertFalse(PetNames.hasMasculine("Шибы больше нет"), "сама «Шиба» не в счёт")
    }

    /// Все тексты, что видит хозяин своего персонажа, — без «Шибы».
    func testNoShibaLeftForOwnCharacter() {
        var texts: [String] = []
        for t in Trick.allCases { texts.append(PetNames.adapt(t.done, name: cat)) }
        for (id, list) in Cooking.lines {
            for n in 1...list.count { texts.append(PetNames.adapt(Cooking.dishLine(id, n: n), name: cat)) }
        }
        texts.append(PetNames.adapt(Cooking.dishLine("nope", n: 1), name: cat))
        for why in [Cooking.reasons.night, Cooking.reasons.noKitchen, Cooking.reasons.enough, "dead", nil] {
            texts.append(Cooking.reasonText(why, name: cat))
        }
        for n in 1...Brush.doneLines.count {
            texts.append(Brush.doneText(BrushOutcome(ok: true, reason: nil, before: .sleek, after: .sleek, love: 1, count: n), name: cat))
        }
        for pose in Pose.allCases { texts.append(HomeText.poseText(pose, name: cat)) }
        for r in ["dead", "asleep", "away", "store", "x", nil] { texts.append(RefuseText.text(r, name: cat)) }
        for s in texts {
            XCTAssertFalse(s.contains("Шиб"), s)
            XCTAssertFalse(s.contains("\u{E000}") || s.contains("\u{E001}"), "метки убраны: \(s)")
            XCTAssertFalse(s.isEmpty)
        }
    }

    func testNotificationTitleIsName() {
        let lines = Lines.shared
        let n = lines.notification("no_such_key_w14", seed: "s", slot: 0, name: cat)
        XCTAssertEqual(n.title, cat)
        XCTAssertEqual(lines.notification("no_such_key_w14", seed: "s", slot: 0).title, PetNames.shiba)
    }

    // MARK: SaveFile

    func testPetNameFollowsCharacter() throws {
        var f = SaveFile.fresh(now: 1_760_000_000)
        XCTAssertEqual(f.petName, "Шиба")
        f.characterName = "Мурка"
        XCTAssertEqual(f.petName, "Шиба", "без выбранного пака имя пака не в счёт")
        f.character = "murka"
        XCTAssertEqual(f.petName, "Мурка")
        f.characterName = "   "
        XCTAssertEqual(f.petName, "Шиба", "пустое имя — Шиба")
        f.characterName = "Мурка"
        let back = try JSONDecoder().decode(SaveFile.self, from: try JSONEncoder().encode(f))
        XCTAssertEqual(back.characterName, "Мурка")
        XCTAssertEqual(back.petName, "Мурка")

        let plain = String(decoding: try JSONEncoder().encode(SaveFile.fresh(now: 1)), as: UTF8.self)
        XCTAssertFalse(plain.contains("characterName"), "nil в файл не пишется")
    }

    func testCharacterNameCarriedToNewPuppy() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-names-w14")
        defer { StoreHooks.removeTempStore(dir) }
        let store = PetStore(dir: dir)
        try store.startOver(now: 1_760_000_000)
        try store.mutate { (f: inout SaveFile) -> Void in
            f.character = "murka"
            f.characterName = "Мурка"
        }
        try store.startOver(now: 1_760_000_100)
        let f = try XCTUnwrap(store.read())
        XCTAssertEqual(f.petName, "Мурка", "облик и имя — выбор хозяина, переходят к новому")
        XCTAssertEqual(Presenter.make(f, at: 1_760_000_100).name, "Мурка", "шапка, виджет и остров берут имя отсюда")
    }
}
