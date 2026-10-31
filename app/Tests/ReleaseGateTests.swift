// Волна 59: сборка для друзей. Release (из него CI делает ipa) не слушает PET_* и не применяет LaunchSeed,
// раздела «Для разработки» в нём нет; UI-тесты идут на Debug и работают как раньше.
// Под чужим Apple ID (SideStore) общая папка может не подключиться: виджет тогда показывает заглушку,
// а не выдуманного щенка; приложение заводит щенка и показывает знакомство.

import XCTest
@testable import Pet

private let rgTestsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let rgAppDir = rgTestsDir.deletingLastPathComponent()
private let rgRepoDir = rgAppDir.deletingLastPathComponent()

private func rgRead(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

final class ReleaseGateTests: XCTestCase {
    // MARK: ворота

    func testReleaseIgnoresEnvironmentAndArguments() {
        let raw = ["PET_SEED": "house_rich", "PET_RESET": "1", "PET_NOW": "2026-01-01T00:00:00Z",
                   "PET_STORE_DIR": "/tmp/x", "PET_DEVTOOLS": "1", "PET_UI_TEST": "1"]
        XCTAssertTrue(DevGate.env(raw, dev: false).isEmpty, "Release: окружение не слушаем совсем")
        XCTAssertEqual(DevGate.env(raw, dev: true), raw, "Debug: всё как раньше")
        XCTAssertTrue(DevGate.args(["Pet", "-uiTesting"], dev: false).isEmpty)
        XCTAssertEqual(DevGate.args(["Pet", "-uiTesting"], dev: true), ["Pet", "-uiTesting"])
    }

    func testDevSectionHiddenInFriendBuild() {
        // ipa для друзей: ни под каким видом, даже если отметка о 7 тапах осталась от старой сборки.
        for ui in [false, true] {
            for env in [false, true] {
                for unlocked in [false, true] {
                    XCTAssertFalse(DevGate.showDevSection(menu: false, dev: false, uiTest: ui, devtoolsEnv: env,
                                                          unlocked: unlocked))
                }
            }
        }
        // ipa для себя (PET_DEV_IPA): только после 7 тапов; env не слушаем.
        XCTAssertFalse(DevGate.showDevSection(menu: true, dev: false, uiTest: false, devtoolsEnv: true, unlocked: false))
        XCTAssertTrue(DevGate.showDevSection(menu: true, dev: false, uiTest: false, devtoolsEnv: false, unlocked: true))
        // Debug: как до волны 59 — виден, кроме скриншотов UI-тестов без PET_DEVTOOLS.
        XCTAssertTrue(DevGate.showDevSection(menu: true, dev: true, uiTest: false, devtoolsEnv: false, unlocked: false))
        XCTAssertFalse(DevGate.showDevSection(menu: true, dev: true, uiTest: true, devtoolsEnv: false, unlocked: false))
        XCTAssertTrue(DevGate.showDevSection(menu: true, dev: true, uiTest: true, devtoolsEnv: true, unlocked: false))
    }

    /// Тесты сами идут на Debug: так UI-тесты получают PET_SEED, PET_NOW и прочее.
    func testTestsRunOnDevBuild() {
        XCTAssertTrue(DevGate.isDevBuild)
        XCTAssertTrue(DevGate.devMenu)
    }

    // MARK: исходники держат ворота

    func testLaunchSeedGuardedByDevGate() throws {
        let src = try rgRead(rgAppDir.appendingPathComponent("App/LaunchSeed.swift"))
        let body = try XCTUnwrap(src.range(of: "static func applyOnce()"), "applyOnce на месте")
        let tail = src[body.upperBound...]
        let guardAt = try XCTUnwrap(tail.range(of: "guard DevGate.isDevBuild else { return }"), "applyOnce закрыт воротами")
        let resetAt = try XCTUnwrap(tail.range(of: "Env.value(\"PET_RESET\")"))
        XCTAssertLessThan(guardAt.lowerBound, resetAt.lowerBound, "ворота — до первого сида")
    }

    /// Окружение процесса читает только Env (через DevGate). Новый ProcessInfo.environment мимо ворот — сюда.
    func testEnvironmentReadOnlyThroughGate() throws {
        let fm = FileManager.default
        var offenders: [String] = []
        for folder in ["App", "Shared", "Widgets"] {
            let root = rgAppDir.appendingPathComponent(folder)
            guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk where url.pathExtension == "swift" {
                let src = try rgRead(url)
                for (i, line) in src.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("processInfo.environment") || line.contains("processInfo.arguments.contains") {
                    let ok = url.lastPathComponent == "Clock.swift" && line.contains("DevGate.")
                    if !ok { offenders.append("\(folder)/\(url.lastPathComponent):\(i + 1)") }
                }
            }
        }
        XCTAssertEqual(offenders, [], "env и аргументы — только через Env/DevGate")
    }

    func testSettingsDevSectionUsesGate() throws {
        let src = try rgRead(rgAppDir.appendingPathComponent("App/Screens.swift"))
        XCTAssertTrue(src.contains("DevGate.showDevSection("), "раздел «Для разработки» решают ворота")
        XCTAssertTrue(src.contains("if DevGate.devMenu {"), "7 тапов по версии — только где есть раздел")
        XCTAssertFalse(src.contains("|| devUnlocked"), "отметка о тапах сама раздел не открывает")
        XCTAssertTrue(src.contains("AboutInfo.versionLine(") && src.contains("AboutInfo.feedbackLine"),
                      "в «Об игре» версия, сборка и куда писать")
    }

    /// ipa — Release, UI-тесты — Debug (схема и workflow). Если кто-то соберёт тесты на Release, сиды умрут молча.
    func testCIBuildsIpaInReleaseAndTestsInDebug() throws {
        let yml = try rgRead(rgRepoDir.appendingPathComponent(".github/workflows/app.yml"))
        let ipaStart = try XCTUnwrap(yml.range(of: "\n  ipa:\n"))
        let testStart = try XCTUnwrap(yml.range(of: "\n  test:\n"))
        let ipaJob = yml[ipaStart.upperBound..<testStart.lowerBound]
        XCTAssertTrue(ipaJob.contains("-configuration Release"), "ipa собирается в Release")
        XCTAssertFalse(ipaJob.contains("-configuration Debug"))
        XCTAssertFalse(ipaJob.contains("-DDEBUG") || ipaJob.contains("CONDITIONS=DEBUG")
                       || ipaJob.contains("CONDITIONS='$(inherited) DEBUG"), "в ipa не протаскиваем DEBUG флагами")
        XCTAssertTrue(ipaJob.contains("if [ \"$DEV_IPA\" = 1 ]"), "PET_DEV_IPA — только по входу dev")
        let rest = yml[testStart.lowerBound...]
        for chunk in rest.components(separatedBy: "xcodebuild build-for-testing").dropFirst() {
            let cmd = chunk.prefix(400)
            XCTAssertFalse(cmd.contains("-configuration Release"), "тесты — на Debug схемы")
        }
        let proj = try rgRead(rgAppDir.appendingPathComponent("project.yml"))
        XCTAssertTrue(proj.contains("    test:\n      config: Debug"), "схема: тесты на Debug")
        XCTAssertTrue(proj.contains("    archive:\n      config: Release"))
    }

    // MARK: «Об игре»

    func testAboutVersionLine() {
        XCTAssertEqual(AboutInfo.versionLine(["CFBundleShortVersionString": "0.31", "CFBundleVersion": "7"]),
                       "Версия 0.31 (сборка 7)")
        XCTAssertEqual(AboutInfo.versionLine(nil), "Версия — (сборка —)")
        XCTAssertEqual(AboutInfo.versionLine(["CFBundleShortVersionString": ""]), "Версия — (сборка —)")
    }

    /// Репозиторий публичный: ни ников, ни ссылок, ни телефонов.
    func testFeedbackLineHasNoContacts() {
        let s = AboutInfo.feedbackLine
        XCTAssertFalse(s.isEmpty)
        for bad in ["@", "http", "t.me", "www", ".com", ".ru", "+7", "+381"] {
            XCTAssertFalse(s.contains(bad), bad)
        }
        XCTAssertFalse(s.contains { $0.isNumber }, "без номеров")
    }

    // MARK: чужая подпись: виджет без сейва

    func testWidgetWithoutSaveShowsPlaceholder() {
        let now = 1_800_000_000.0
        let open = WidgetFallback.looks(nil, now: now, shared: true)
        XCTAssertEqual(open.count, 1)
        let l = open[0]
        XCTAssertEqual(l.caption, WidgetFallback.openAppCaption)
        XCTAssertNil(l.main)
        XCTAssertTrue(l.bars.isEmpty, "шкал не выдумываем")
        XCTAssertNil(l.coins)
        XCTAssertNil(l.bankLine)
        XCTAssertNil(l.status.act, "кнопки действия нет — некого кормить")
        XCTAssertFalse(l.statusLeads, "подпись — сама заглушка")
        XCTAssertEqual(WidgetFallback.looks(nil, now: now, shared: false).first?.caption, WidgetFallback.noLinkCaption)
    }

    func testWidgetWithSaveIsUnchanged() {
        let now = 1_800_000_000.0
        let f = SaveFile.fresh(now: now - 3600)
        XCTAssertEqual(WidgetFallback.looks(f, now: now, shared: false), WidgetLook.looks(f, now: now),
                       "есть сейв — кадры прежние")
        XCTAssertEqual(WidgetFallback.status(f, now: now, shared: false), PetStatusLogic.of(f, now: now))
    }

    func testControlWithoutSaveOpensApp() {
        let st = WidgetFallback.status(nil, now: 1_800_000_000, shared: true)
        XCTAssertNil(st.act, "кнопка откроет приложение")
        XCTAssertEqual(st.title, WidgetFallback.openAppCaption)
        XCTAssertEqual(WidgetFallback.status(nil, now: 0, shared: false).title, WidgetFallback.noLinkCaption)
    }

    // MARK: чужая подпись: стор

    /// Расширение со своей пустой папкой (группа не подключилась): сейва нет, щенка оно не заводит и не падает.
    func testExtensionWithEmptyFolderReadsNothingAndCreatesNothing() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-nogroup")
        defer { StoreHooks.removeTempStore(dir) }
        let ext = PetStore(dir: dir, mayCreate: false)
        XCTAssertNil(try ext.read(), "пустая папка — nil, а не выдуманный щенок")
        XCTAssertThrowsError(try ext.mutate { (f: inout SaveFile) -> Void in f.seq += 1 }) { err in
            guard case .noSave? = err as? StoreError else { return XCTFail("ждали noSave, пришло \(err)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: ext.stateURL.path), "файл не появился")
    }

    /// Приложение в пустой папке (первый запуск у друга, или группа не подключилась и это Application Support):
    /// заводит щенка, и знакомство показывается.
    func testAppFirstLaunchInEmptyFolderStartsIntro() throws {
        let dir = StoreHooks.makeTempStoreDir("pet-firstrun")
        defer { StoreHooks.removeTempStore(dir) }
        try? FileManager.default.removeItem(at: Paths.mirror)
        let app = PetStore(dir: dir, mayCreate: true)
        XCTAssertNil(try app.read())
        let f = try app.mutate { (f: inout SaveFile) -> SaveFile in f }
        XCTAssertTrue(f.pet.alive)
        XCTAssertTrue(Onboarding.shouldShowIntro(tips: f.tips, alive: f.pet.alive), "новичку — знакомство")
        XCTAssertNotNil(try app.read(), "щенок записан")
    }

    /// Переподпись другой командой меняет суффикс группы — новая папка пустая. Сейв приходит из зеркала
    /// в Documents приложения (пишет только приложение, APP_TARGET; на Linux — пропуск).
    func testNewGroupFolderRestoresFromMirror() throws {
        let old = StoreHooks.makeTempStoreDir("pet-group-a")
        let new = StoreHooks.makeTempStoreDir("pet-group-b")
        defer { StoreHooks.removeTempStore(old); StoreHooks.removeTempStore(new) }
        try? FileManager.default.removeItem(at: Paths.mirror)
        let a = PetStore(dir: old, mayCreate: true)
        try a.startOver(now: 1_800_000_000)
        try a.mutate { (f: inout SaveFile) -> Void in f.debugMarker = 59 }
        guard FileManager.default.fileExists(atPath: Paths.mirror.path) else {
            throw XCTSkip("зеркало пишет только приложение (APP_TARGET)")
        }
        let b = PetStore(dir: new, mayCreate: true)
        let f = try XCTUnwrap(b.read(), "новая группа пустая — спасает зеркало")
        XCTAssertEqual(f.debugMarker, 59)
    }
}
