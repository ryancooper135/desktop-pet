// App Group и срок подписи. Код из probe, переписан под Swift 6: кэш только в Sendable `static let`.

import Foundation

/// Сайдлоадеры переписывают ID группы (дописывают суффикс команды), поэтому настоящий ID ищем
/// в рантайме, а захардкоженный — только запасной.
enum AppGroup {
    static let fallback = "group.com.vadimpet.pet"
    static let resolved: (id: String, source: String) = resolve()

    static var id: String { resolved.id }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    private static func resolve() -> (id: String, source: String) {
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String], let first = alt.first {
            return (first, "ALTAppGroups")
        }
        if let groups = ProvisioningProfile.appGroups(), !groups.isEmpty {
            // Если групп несколько, берём ту, что начинается с нашей (суффикс дописан в конец).
            let own = groups.first { $0.hasPrefix(fallback) } ?? groups[0]
            if !own.contains("*") { return (own, "embedded.mobileprovision") }
        }
        return (fallback, "захардкожен")
    }
}

/// embedded.mobileprovision — CMS-конверт, внутри обычный XML plist. На симуляторе и в CI без подписи его нет.
enum ProvisioningProfile {
    static func plist(_ bundle: Bundle = .main) -> [String: Any]? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    /// Отдельно от чтения файла, чтобы тест мог скормить фикстуру.
    static func parse(_ data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? [String: Any]
    }

    static func entitlements(_ bundle: Bundle = .main) -> [String: Any]? {
        plist(bundle)?["Entitlements"] as? [String: Any]
    }

    static func appGroups(_ bundle: Bundle = .main) -> [String]? {
        entitlements(bundle)?["com.apple.security.application-groups"] as? [String]
    }

    /// Когда подпись истечёт и приложение перестанет запускаться (build_age).
    static func expirationDate(_ bundle: Bundle = .main) -> Date? {
        plist(bundle)?["ExpirationDate"] as? Date
    }
}
