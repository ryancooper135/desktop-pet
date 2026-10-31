// Строки раздела «Об игре» в настройках (волна 59). Без экрана — проверяются и на Linux.

import Foundation

enum AboutInfo {
    /// Куда писать отзыв. Без личных контактов: репозиторий публичный, ipa раздаёт тот, кто его собрал.
    static let feedbackLine = "Отзыв и идеи — тому, кто дал тебе приложение."

    /// «Версия 0.11 (сборка 1)» из Info.plist. Нет ключа — прочерк, не падаем.
    static func versionLine(_ info: [String: Any]?) -> String {
        let v = (info?["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        let b = (info?["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        return "Версия \(v) (сборка \(b))"
    }
}
