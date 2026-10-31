// Ворота отладки. Сборка для друзей (Release, из неё CI делает ipa) не читает PET_* из окружения,
// не применяет LaunchSeed и не показывает «Для разработки». UI-тесты и запуск из Xcode — Debug,
// там всё как раньше. Ipa для себя с каталогом превью: флаг PET_DEV_IPA (вход dev в app.yml).

import Foundation

enum DevGate {
    /// Debug-сборка: env-читы (PET_NOW, PET_SEED, PET_RESET, PET_STORE_DIR…) и LaunchSeed работают.
    #if DEBUG
    static let isDevBuild = true
    #else
    static let isDevBuild = false
    #endif

    /// Раздел «Для разработки» и 7 тапов по версии. В ipa для друзей — нет.
    #if DEBUG || PET_DEV_IPA
    static let devMenu = true
    #else
    static let devMenu = false
    #endif

    /// Окружение процесса, которое приложение готово слушать. В Release — пустое.
    static func env(_ raw: [String: String], dev: Bool = isDevBuild) -> [String: String] {
        dev ? raw : [:]
    }

    /// Аргументы запуска (-uiTesting). В Release не слушаем.
    static func args(_ raw: [String], dev: Bool = isDevBuild) -> [String] {
        dev ? raw : []
    }

    /// Виден ли раздел «Для разработки».
    /// В Debug — всегда, кроме UI-тестов (там по PET_DEVTOOLS=1) или после 7 тапов.
    /// В Release без PET_DEV_IPA — никогда, даже если отметка о 7 тапах осталась от старой сборки.
    static func showDevSection(menu: Bool = devMenu, dev: Bool = isDevBuild,
                               uiTest: Bool, devtoolsEnv: Bool, unlocked: Bool) -> Bool {
        guard menu else { return false }
        if unlocked { return true }
        guard dev else { return false }
        return !uiTest || devtoolsEnv
    }
}
