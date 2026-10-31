// Где лежит общий стейт. Порядок: PET_STORE_DIR (тесты) → <группа>/pet → Application Support/pet.
// Если группы нет (подпись её срезала), приложение и виджет живут в разных папках:
// приложение показывает баннер, виджет пишет «открой приложение».

import Foundation

enum Paths {
    static let resolved: (dir: URL, shared: Bool) = resolve()

    static var dir: URL { resolved.dir }
    static var isShared: Bool { resolved.shared }

    static var state: URL { dir.appendingPathComponent("state.json") }
    static var prev: URL { dir.appendingPathComponent("state.prev.json") }
    static func broken(_ t: Double) -> URL { dir.appendingPathComponent("state.broken-\(Int(t)).json") }

    /// Копия в Documents приложения: переживает потерю группы при переподписи (§8). Пишет только приложение.
    static var mirror: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("state.mirror.json")
    }

    private static func resolve() -> (dir: URL, shared: Bool) {
        let env = Env.vars
        if let custom = env["PET_STORE_DIR"], !custom.isEmpty {
            let url = URL(fileURLWithPath: custom, isDirectory: true)
            ensureDir(url)
            return (url, true)
        }
        if let group = AppGroup.containerURL {
            let url = group.appendingPathComponent("pet", isDirectory: true)
            ensureDir(url)
            return (url, true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base.appendingPathComponent("pet", isDirectory: true)
        ensureDir(url)
        return (url, false)
    }

    static func ensureDir(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
