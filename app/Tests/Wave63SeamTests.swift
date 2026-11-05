// Волна 63: охота на баги стыков волн 55b–62 (раннер, «Команды», две породы, задания дня, тосты).
// Каждый тест — найденный баг: сначала падал, потом починен.

import Foundation
import XCTest
@testable import Pet
@preconcurrency import PetCore

private let w63T0: Double = 1_760_054_400   // 2025-10-10 00:00 UTC
private let w63H: Double = 3600

final class Wave63SeamTests: XCTestCase {

    private func husky(now: Double = w63T0 + 12 * w63H) -> SaveFile {
        var f = SaveFile.fresh(now: now - 600)
        f.owner.tzOffsetMin = 0
        f.breed = PetBreed.husky.saved
        return f
    }

    private func noShiba(_ s: String, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(s.contains("Шиб"), "\(what): «\(s)» — у Хаски нет Шибы", file: file, line: line)
    }

    // MARK: Порода (58) × имя в шапке, виджете, острове, уведомлениях

    /// Было: выбран Хаски — SaveFile.petName «Шиба»: шапка, Live Activity, виджет и уведомления звали его Шибой.
    func testHuskyPetNameIsBreedTitle() {
        var f = husky()
        XCTAssertEqual(f.petName, "Хаски")
        let now = w63T0 + 12 * w63H
        XCTAssertEqual(Presenter.make(f, at: now).name, "Хаски", "шапка, виджет и остров берут имя из Presenter")
        XCTAssertEqual(IslandEvents.input(f, at: now).name, "Хаски", "остров")
        f.character = "murka"
        f.characterName = "Мурка"
        XCTAssertEqual(f.petName, "Мурка", "свой персонаж важнее породы")
        f.character = nil
        f.characterName = nil
        f.breed = nil
        XCTAssertEqual(f.petName, "Шиба", "старый сейв без породы — Шиба, как был")
        f.breed = "corgi-from-future"
        XCTAssertEqual(f.petName, "Шиба", "незнакомая порода — Шиба")
    }

    /// Было: тексты под Шибу у Хаски шли через «питомец/питомца» — «Очки питомца», «ход питомца».
    /// Хаски не склоняется и мужского рода: имя встаёт в любую форму.
    func testAdaptPutsIndeclinableBreedTitleEverywhere() {
        XCTAssertEqual(PetNames.adapt("Очки Шибы: 12", name: "Хаски"), "Очки Хаски: 12")
        XCTAssertEqual(PetNames.adapt("Последняя фигура — и ход Шибы", name: "Хаски"), "Последняя фигура — и ход Хаски")
        XCTAssertEqual(PetNames.adapt("Шиба убрал линию! Гав!", name: "Хаски"), "Хаски убрал линию! Гав!")
        XCTAssertEqual(PetNames.adapt("Шибе было весело!", name: "Хаски"), "Хаски было весело!")
        XCTAssertEqual(PetNames.adapt("Бежим с Шибой: двор, район, парк", name: "Хаски"), "Бежим с Хаски: двор, район, парк")
        XCTAssertEqual(PetNames.adapt("Шибы больше нет", name: "Хаски"), "Хаски больше не с нами")
        // Свой персонаж — как раньше: род неизвестен, «питомец».
        XCTAssertEqual(PetNames.adapt("Очки Шибы: 12", name: "Мурка"), "Очки питомца: 12")
        XCTAssertEqual(PetNames.adapt("Шиба убрал линию!", name: "Мурка"), "Питомец убрал линию!")
    }

    /// Было: VoiceOver «Шиба спокоен» у Хаски (имя Шиба) → после имени — «Хаски отдыхает»; лучше фразы Шибы с родом.
    func testHuskyPoseAndDeathTexts() {
        for pose in Pose.allCases {
            let s = HomeText.poseText(pose, name: "Хаски")
            noShiba(s, "поза \(pose)")
            XCTAssertTrue(s.contains("Хаски"), "поза \(pose): «\(s)» без имени")
        }
        XCTAssertEqual(HomeText.poseText(.idle, name: "Хаски"), "Хаски спокоен")
        XCTAssertEqual(AwayBuilder.deathText("starve", name: "Хаски"), "Хаски слишком долго был голодным.")
        XCTAssertEqual(HomeText.poseText(.idle, name: "Мурка"), "Мурка отдыхает", "свой персонаж — без рода, как был")
    }

    /// Тексты, которые собираются из сейва Хаски, — без «Шибы»: отказы, подсказка, мини-игры, уведомления.
    func testHuskyTextsFromSaveSayHusky() {
        let now = w63T0 + 12 * w63H
        let f = husky(now: now)
        let name = Presenter.make(f, at: now).name
        noShiba(RefuseText.text("dead", name: name), "отказ dead")
        noShiba(PetNames.adapt(MiniGames.menuHint(), name: name), "меню игр")
        noShiba(MiniGames.noteText(MiniGames.capReason, name: name), "плашка игры")
        noShiba(PetNames.gone(name), "смерть")
        for p in NotificationPlanner.plan(f, now: now) {
            noShiba(p.title, "уведомление «\(p.id)»")
            noShiba(p.body, "уведомление «\(p.id)»")
        }
    }

    // MARK: Двор, фургон, карта — строки VoiceOver мимо adapt

    /// Было: «Останется: Шиба, его уровень…», «Шиба спит» во дворе, «Шиба сидит в кабине», «Шиба в пути» — у Хаски.
    func testYardAndMapLabelsUseName() {
        let keep = YardConfig.shared.moveKeepCoins
        XCTAssertEqual(YardText.moveConfirm(moves: 0).first,
                       "Останется: Шиба, его уровень и рост, вещи, дом, ✂️, альбом, \(keep) 🪙", "у Шибы как было")
        XCTAssertEqual(YardText.moveConfirm(moves: 0, name: "Хаски").first,
                       "Останется: Хаски, его уровень и рост, вещи, дом, ✂️, альбом, \(keep) 🪙")
        XCTAssertEqual(YardText.dogLabel(mode: .asleep, station: nil, acting: false, name: "Хаски"), ". Хаски спит")
        XCTAssertEqual(YardText.dogLabel(mode: .awake, station: "Сушилка", acting: true, name: "Хаски"),
                       ". Хаски у станции «Сушилка»")
        XCTAssertEqual(YardText.dogLabel(mode: .awake, station: "Сушилка", acting: false, name: "Шиба"),
                       ". Шиба бегает к станции «Сушилка»")
        XCTAssertEqual(YardText.dogLabel(mode: .awake, station: nil, acting: false, name: "Хаски"), ". Хаски отдыхает во дворе")
        XCTAssertEqual(YardText.dogLabel(mode: .absent, station: "Сушилка", acting: true, name: "Хаски"), "")
        XCTAssertEqual(YardText.vanLabel(name: "Хаски"), "Фургон у дома, коробки едут в кузов, Хаски сидит в кабине")
        XCTAssertEqual(YardText.mapDogLabel(name: "Хаски"), "Хаски в пути")
        XCTAssertEqual(YardText.mapDogLabel(name: "Шиба"), "Шиба в пути")
    }

    /// Было: свой персонаж не загрузился при выбранном Хаски — «Вернул Шибу», а в комнате Хаски.
    func testCharacterFailedNamesFallbackBreed() {
        XCTAssertEqual(PetBreed.shiba.characterFailed("Мурка", reason: "нет модели"), "Мурка не загрузился: нет модели. Вернул Шибу.")
        XCTAssertEqual(PetBreed.husky.characterFailed("Мурка", reason: "нет модели"), "Мурка не загрузился: нет модели. Вернул Хаски.")
    }

    // MARK: «Команды» × задания дня

    private func outcome(_ t: Trick, learnedNow: Bool = false, coins: Int = 0, ok: Bool = true) -> TrickOutcome {
        TrickOutcome(trick: t, ok: ok, reason: nil, counted: ok, progress: 1, learnedNow: learnedNow, coins: coins, love: 1)
    }

    /// Было: показ команды закрыл задание «Покажи трюки» — тост задания из refresh, а через 0,35 с «Сидит!» его стирал.
    func testTrickToastDoesNotEraseTaskToast() {
        XCTAssertEqual(Tricks.doneToast(.sit, outcome(.sit), taskFresh: false)?.text, "Сидит!")
        XCTAssertNil(Tricks.doneToast(.sit, outcome(.sit), taskFresh: true), "тост задания на экране — «Сидит!» молчит")
        let learned = Tricks.doneToast(.paw, outcome(.paw, learnedNow: true, coins: 10), taskFresh: true)
        XCTAssertEqual(learned?.text, "Выучил «Лапу»! +\(EconText.coins(10))")
        XCTAssertEqual(learned?.emoji, "🪙")
        XCTAssertEqual(learned?.wait, true, "«Выучил» — раз на трюк: ждёт тост задания, не стирает его")
        XCTAssertEqual(Tricks.doneToast(.paw, outcome(.paw, learnedNow: true), taskFresh: false)?.wait, false)
        XCTAssertNil(Tricks.doneToast(.sit, outcome(.sit, ok: false), taskFresh: false), "промах — свой тост в AppModel")
    }

    /// Стык: показ команды и правда закрывает задание «Покажи трюки» той же записью — тост задания свежий.
    func testCountedTrickClosesTricksTaskInSameWrite() {
        let now = w63T0 + 12 * w63H
        var f = husky(now: now)
        f.tasks.started = true
        f.tasks.day = DayKey.of(now)
        f.tasks.items = [DailyTask(id: "tricks", need: 1, coins: 4)]
        let out = Tricks.attempt(.sit, in: &f, now: now, roll: 0)
        XCTAssertTrue(out.ok && out.counted, "предусловие: показ засчитан")
        let w = try? XCTUnwrap(f.tasks.last)
        XCTAssertEqual(w?.task, "tricks")
        XCTAssertEqual(w?.t, now, "тост задания выйдет из refresh сразу после команды — «Сидит!» должен его пропустить")
    }

    // MARK: Мини-игры (fullScreenCover) × тост задания дня

    /// Было: забег закрыл задание «Поиграть» — refresh под обложкой раннера показывал тост на главном, под игрой;
    /// после 10 с на карточке итога он не выходил вовсе. Теперь под игрой — отложить и показать после закрытия.
    func testTaskToastWaitsForGameCover() {
        let won = w63T0
        XCTAssertEqual(HeldToastStep.of(winT: won, shownT: nil, heldT: nil, now: won + 1, covered: false), .show)
        XCTAssertEqual(HeldToastStep.of(winT: won, shownT: nil, heldT: nil, now: won + 1, covered: true), .hold)
        XCTAssertEqual(HeldToastStep.of(winT: won, shownT: nil, heldT: won, now: won + 90, covered: false), .show,
                       "отложенный — и после 10 с на итоге забега")
        XCTAssertEqual(HeldToastStep.of(winT: won, shownT: nil, heldT: won, now: won + 90, covered: true), .hold)
        XCTAssertEqual(HeldToastStep.of(winT: won, shownT: nil, heldT: nil, now: won + 90, covered: false), .skip,
                       "старое и не отложенное (догон после фона) — не показываем, как раньше")
        XCTAssertEqual(HeldToastStep.of(winT: won, shownT: won, heldT: nil, now: won + 1, covered: false), .skip,
                       "уже показан")
        XCTAssertEqual(HeldToastStep.of(winT: won, shownT: won - 5, heldT: won - 5, now: won + 1, covered: false), .show,
                       "новое задание после прошлого отложенного")
    }

    /// Стык: финиш забега (как RunnerScreen.finish) закрывает «Поиграть» — это и есть тост под обложкой.
    func testRunnerFinishClosesPlayTask() {
        let now = w63T0 + 12 * w63H
        var f = husky(now: now)
        f.tasks.started = true
        f.tasks.day = DayKey.of(now)
        f.tasks.items = [DailyTask(id: "play", need: 1, coins: 4)]
        let r = Challenges.play(.runner, in: &f, now: now) { g, t in
            Runner.finish(score: 120, metres: 120, picked: 3, in: &g, now: t)
        }
        XCTAssertTrue(r.played, "предусловие: пёс бодр, забег настоящий")
        XCTAssertEqual(f.tasks.last?.task, "play", "задание дня закрыто забегом — пока открыт раннер")
    }
}
