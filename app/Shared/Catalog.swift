// Правила ядра и имена из config/economy.json. Файл лежит в бандле и приложения, и виджетов.

import Foundation
@preconcurrency import PetCore

enum Catalog {
    /// Rules в ядре не Sendable, но после загрузки только читаются — поэтому nonisolated(unsafe).
    nonisolated(unsafe) static let rules: Rules = {
        guard let data = resource("economy", "json") else {
            fatalError("economy.json нет в бандле: проверь resources в app/project.yml (../config/economy.json)")
        }
        do { return try Rules(data: data) } catch {
            fatalError("economy.json не разобрался ядром: \(error)")
        }
    }()

    /// Главная еда (кнопка «Хрустик») и лечебный предмет для «Спасти».
    static let mainFood = "kibble"
    static let healItem = "vitamin"

    /// id предмета → имя («kibble» → «Хрустики»).
    static let names: [String: String] = loadNames()

    /// Имена шкал: «Сытость», «Чистота»…
    static let needNames: [Need: String] = loadNeedNames()

    static func name(_ id: String) -> String { names[id] ?? id }
    static func needName(_ n: Need) -> String { needNames[n] ?? n.rawValue }

    /// Файл из бандла. В юнит-тестах Bundle.main — приложение-хост, запасной путь — бандл с этим кодом.
    static func resource(_ name: String, _ ext: String) -> Data? {
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)]
        for b in bundles {
            if let url = b.url(forResource: name, withExtension: ext), let data = try? Data(contentsOf: url) {
                return data
            }
        }
        #if SWIFT_PACKAGE
        // Linux-сборка логики (app/Package.swift): бандла с ресурсами нет, читаем файлы из репозитория.
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let inRepo = ["economy.json": "config/economy.json", "lines.json": "content/ru/lines.json"]
        if let rel = inRepo["\(name).\(ext)"], let data = try? Data(contentsOf: repo.appendingPathComponent(rel)) {
            return data
        }
        #endif
        return nil
    }

    private static func economy() -> JSONValue? {
        guard let data = resource("economy", "json") else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func loadNames() -> [String: String] {
        guard let e = economy() else { return [:] }
        var out: [String: String] = [:]
        for section in ["food", "consumables", "toys"] {
            for item in e["shop"][section].array {
                if let id = item["id"].string, let name = item["name"].string { out[id] = name }
            }
        }
        return out
    }

    private static func loadNeedNames() -> [Need: String] {
        guard let e = economy() else { return [:] }
        var out: [Need: String] = [:]
        for n in Need.allCases {
            if let name = e["care"]["needs"][n.rawValue]["name"].string { out[n] = name }
        }
        return out
    }
}

private final class BundleToken {}
