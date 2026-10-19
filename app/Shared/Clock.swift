// «Сейчас» для всего приложения. В UI-тестах время сдвигается через PET_NOW (unix-секунды или ISO 8601):
// часы стартуют с этого момента и идут дальше, так что тикер и таймеры работают.

import Foundation

enum Clock {
    /// Сдвиг относительно настоящих часов, считается один раз при запуске.
    static let offset: Double = {
        guard let raw = ProcessInfo.processInfo.environment["PET_NOW"], let t = parse(raw) else { return 0 }
        return t - Date().timeIntervalSince1970
    }()

    static func now() -> Double { Date().timeIntervalSince1970 + offset }
    static func date() -> Date { Date(timeIntervalSince1970: now()) }

    /// Пояс для тестов (перелёт, летнее время). nil — пояс телефона. В приложении не меняется.
    nonisolated(unsafe) static var zoneOverride: TimeZone?
    static var zone: TimeZone { zoneOverride ?? .current }

    /// Смещение местного времени от UTC в минутах на момент t (учитывает летнее время).
    static func tzOffsetMin(at t: Double) -> Int {
        zone.secondsFromGMT(for: Date(timeIntervalSince1970: t)) / 60
    }

    static func parse(_ raw: String) -> Double? {
        if let n = Double(raw) { return n }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: raw) { return d.timeIntervalSince1970 }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: raw)?.timeIntervalSince1970
    }

    /// «18:00» по местному времени.
    static func hm(_ t: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}

/// Признаки тестового запуска. Под тестами не просим разрешений и не стартуем остров.
enum Env {
    static let vars: [String: String] = ProcessInfo.processInfo.environment
    static let isUnitTest: Bool = vars["XCTestConfigurationFilePath"] != nil
    static let isUITest: Bool = vars["PET_UI_TEST"] == "1" || ProcessInfo.processInfo.arguments.contains("-uiTesting")
    static var isTesting: Bool { isUnitTest || isUITest }

    static func value(_ key: String) -> String? {
        guard let v = vars[key], !v.isEmpty else { return nil }
        return v
    }
}
