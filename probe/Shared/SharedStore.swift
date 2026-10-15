import Foundation

/// Состояние зонда, общее для приложения, виджета, острова и «Команд».
struct ProbeState: Codable {
    var food: Int = 0
    var pets: Int = 0
    var lastAction: String = "—"
    var lastActionBy: String = "—"
    var lastActionAt: Date = .distantPast
    var widgetRenders: Int = 0
    var widgetRenderedAt: Date?
    var widgetGroupID: String?
    var shortcutEvents: [String] = []
}

/// Sideload-инструменты переписывают ID группы (добавляют суффикс команды),
/// поэтому реальный ID ищем в рантайме, а захардкоженный — только запасной.
enum AppGroup {
    static let fallback = "group.com.vadimpet.probe"
    static let resolved: (id: String, source: String) = resolve()

    private static func resolve() -> (id: String, source: String) {
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String], let first = alt.first {
            return (first, "ALTAppGroups")
        }
        if let first = ProvisioningProfile.appGroups()?.first {
            return (first, "embedded.mobileprovision")
        }
        return (fallback, "захардкожен")
    }
}

enum ProvisioningProfile {
    /// embedded.mobileprovision — CMS-конверт, внутри лежит обычный XML plist.
    static func entitlements() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        return plist?["Entitlements"] as? [String: Any]
    }

    static func appGroups() -> [String]? {
        entitlements()?["com.apple.security.application-groups"] as? [String]
    }
}

enum SharedStore {
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.resolved.id)
    }

    static var isShared: Bool { containerURL != nil }

    private static var fileURL: URL {
        if let container = containerURL {
            return container.appendingPathComponent("probe-state.json")
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("probe-state.json")
    }

    static func load() -> ProbeState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(ProbeState.self, from: data)
        else { return ProbeState() }
        return state
    }

    static func save(_ state: ProbeState) {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    @discardableResult
    static func mutate(_ change: (inout ProbeState) -> Void) -> ProbeState {
        var state = load()
        change(&state)
        save(state)
        return state
    }

    static func diagnostics() -> [(String, String)] {
        let group = AppGroup.resolved
        return [
            ("Bundle ID", Bundle.main.bundleIdentifier ?? "?"),
            ("ID группы", group.id),
            ("Откуда ID", group.source),
            ("Контейнер", containerURL?.path ?? "НЕТ — группа не работает"),
            ("Группы в профиле", ProvisioningProfile.appGroups()?.joined(separator: ", ") ?? "профиля нет"),
            ("ALTAppGroups", (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.joined(separator: ", ") ?? "нет"),
        ]
    }
}

enum PetFace {
    static func face(for state: ProbeState) -> String {
        if state.food == 0 { return "🥺" }
        if state.lastAction == "pet" { return "🥰" }
        return "🐶"
    }

    static func status(for state: ProbeState) -> String {
        state.lastAction == "—" ? "ждёт тебя" : "\(state.lastAction) · \(state.lastActionBy)"
    }
}
