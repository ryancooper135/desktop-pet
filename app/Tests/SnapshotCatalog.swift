// Узкое место между тестами и кодом приложения. Тесты знают только этот файл,
// поэтому вью и стор можно переписывать, не трогая WidgetSnapshotTests / StoreTests.
//
// Вью берутся из каталога превью (app/Shared/Views/PreviewCatalog.swift), стор — настоящий PetStore.
// В Linux-сборке логики (app/Package.swift) вью нет: там компилируется только StoreHooks.

import Foundation
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
@testable import Pet
@preconcurrency import PetCore

#if canImport(UIKit)
// MARK: - Виджеты и остров

/// Где показывается вью. Размеры в точках, примерно как на iPhone Air (420×912);
/// важны пропорции, а не точные пиксели.
enum SnapshotFamily: String, CaseIterable, Sendable {
    case small, medium, large                          // рабочий стол
    case circular, rectangular, inline                 // экран блокировки
    case islandCompact, islandExpanded, lockActivity   // Live Activity

    var size: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        case .circular: CGSize(width: 76, height: 76)
        case .rectangular: CGSize(width: 172, height: 76)
        case .inline: CGSize(width: 257, height: 26)
        case .islandCompact: CGSize(width: 250, height: 37)
        case .islandExpanded: CGSize(width: 408, height: 160)
        case .lockActivity: CGSize(width: 408, height: 160)
        }
    }

    /// Скругление рамки, которой тест обводит снимок (у острова — «пилюля»).
    var cornerRadius: CGFloat {
        switch self {
        case .small, .medium, .large: 22
        case .circular: 38
        case .rectangular, .inline: 8
        case .islandCompact: 18.5
        case .islandExpanded: 44
        case .lockActivity: 24
        }
    }

    var isIsland: Bool { self == .islandCompact || self == .islandExpanded }
    /// Экран блокировки система рисует светлым по тёмному при любой теме.
    var isLockScreen: Bool { self == .circular || self == .rectangular || self == .inline }
}

/// Состояния питомца для снимков.
enum SnapshotMood: String, CaseIterable, Sendable {
    case fed       // сытый, всё хорошо
    case hungry    // голодный
    case asleep    // спит ночью
    case critical  // критично: мало сердец
}

struct SnapshotCase {
    let name: String
    let size: CGSize
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme
    let view: AnyView
}

enum SnapshotCatalog {
    /// Все снимки: имя файла (без .png) → вью. Имя «widget-…» или «island-…».
    @MainActor
    static func all() -> [SnapshotCase] {
        var out: [SnapshotCase] = []
        for family in SnapshotFamily.allCases {
            for mood in SnapshotMood.allCases {
                guard let view = view(family: family, mood: mood) else { continue }
                let prefix = family.isIsland || family == .lockActivity ? "island" : "widget"
                // Остров и экран блокировки всегда тёмные; ночное состояние смотрим в тёмной теме.
                let scheme: ColorScheme = family.isIsland || family.isLockScreen || mood == .asleep ? .dark : .light
                out.append(SnapshotCase(name: "\(prefix)-\(family.rawValue)-\(mood.rawValue)",
                                        size: family.size, cornerRadius: family.cornerRadius,
                                        colorScheme: scheme, view: view))
            }
        }
        return out
    }

    /// Вью для пары «где × состояние» — те же, что в каталоге превью (app/Shared/Views/PreviewCatalog.swift).
    /// nil — такой пары нет, снимок пропускается.
    /// Фон контейнера (`containerBackground`) ImageRenderer не рисует — тест подкладывает systemBackground.
    @MainActor
    static func view(family: SnapshotFamily, mood: SnapshotMood) -> AnyView? {
        previewView(family: family.rawValue, mood: mood.rawValue)
    }
}
#endif

// MARK: - Общий стор

/// Тесты стора работают во временной папке: настоящую App Group не трогают.
/// Зеркало Documents стор приложения (APP_TARGET) пишет попутно — его копию снимаем и возвращаем.
enum StoreHooks {
    /// Базовый ID группы из entitlements. На телефоне сайдлоадер дописывает суффикс,
    /// на симуляторе (ad-hoc подпись) группа ровно такая.
    static let appGroupID = "group.com.vadimpet.pet"

    /// Свежая временная папка под стор. Удаляет вызывающий (defer / removeTempStore).
    /// Рядом кладём копию зеркала приложения: стор его перезапишет.
    static func makeTempStoreDir(_ tag: String = "pet-store-test") -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Paths.mirror) {
            try? data.write(to: mirrorBackup(dir), options: .atomic)
        }
        return dir
    }

    /// Удалить папку и вернуть зеркало как было (не было — убрать).
    static func removeTempStore(_ dir: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        let backup = mirrorBackup(dir)
        if let data = try? Data(contentsOf: backup) {
            try? data.write(to: Paths.mirror, options: .atomic)
            try? fm.removeItem(at: backup)
        } else {
            try? fm.removeItem(at: Paths.mirror)
        }
    }

    private static func mirrorBackup(_ dir: URL) -> URL {
        dir.deletingLastPathComponent().appendingPathComponent(dir.lastPathComponent + ".mirror.json")
    }

    /// Записать метку тем API, каким пишет приложение (mutate), и прочитать её тем API, каким читает виджет (read).
    /// Два разных экземпляра PetStore над одной папкой — как два процесса над одной группой.
    static func writeThenRead(marker: Double) throws -> (written: Double, read: Double)? {
        let dir = makeTempStoreDir("pet-store-hooks")
        defer { removeTempStore(dir) }
        let app = PetStore(dir: dir)
        try app.mutate { (f: inout SaveFile) -> Void in f.debugMarker = marker }
        let widget = PetStore(dir: dir)
        let read = try widget.read()?.debugMarker ?? .nan
        return (marker, read)
    }

    /// Время идёт через стор: свежий щенок пишется во временную папку, читается обратно
    /// и догоняется на `hours` часов вперёд, как это делает виджет.
    static func food(afterHours hours: Double) throws -> (before: Double, after: Double)? {
        let dir = makeTempStoreDir()
        defer { removeTempStore(dir) }
        let store = PetStore(dir: dir)
        let now = Clock.now()
        try store.mutate { (f: inout SaveFile) -> Void in f = SaveFile.fresh(now: now) }
        guard let f = try store.read() else { return nil }
        let before = PetRunner.peek(f, at: now).needs[.food] ?? .nan
        let after = PetRunner.peek(f, at: now + hours * 3600).needs[.food] ?? .nan
        return (before, after)
    }
}
