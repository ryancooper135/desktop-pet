// Свои персонажи на диске (волна 12): <контейнер приложения>/Application Support/characters/<id>/.
// Не в App Group: виджет и остров рисуют картинки, 3D-модель им не нужна. PET_STORE_DIR (тесты) — рядом со стором.
// Копирует папку или пару файлов из «Файлов» целиком к себе: доступ к чужой папке (security scope)
// открывает и закрывает вызывающий (AppModel), здесь обычные URL. Проверка — CharacterPack.check.

import Foundation

struct CharacterStore: Sendable {
    let root: URL

    /// Модель больше — не берём: телефон её не потянет, а копия съест место.
    static let maxBytes = 150 * 1024 * 1024

    struct Entry: Identifiable, Equatable, Sendable {
        let id: String
        let folder: URL
        /// nil — character.json не прочитался (причина — в check.errors).
        let config: CharacterConfig?
        let check: CharacterCheck
        var name: String { config?.name ?? id }
        var ok: Bool { config != nil && check.ok }
        var modelURL: URL? { config.map { folder.appendingPathComponent(CharacterPack.modelName($0)) } }
    }

    static var standard: CharacterStore {
        let env = ProcessInfo.processInfo.environment
        if let custom = env["PET_STORE_DIR"], !custom.isEmpty {
            return CharacterStore(root: URL(fileURLWithPath: custom, isDirectory: true).appendingPathComponent("characters"))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return CharacterStore(root: base.appendingPathComponent("characters", isDirectory: true))
    }

    // MARK: чтение

    /// Все установленные, по имени. Временные папки копирования (с точки) не показываем.
    func list() -> [Entry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return names.filter { !$0.hasPrefix(".") }.sorted().compactMap { entry($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func entry(_ id: String) -> Entry? {
        guard CharacterPack.isSafeFileName(id) else { return nil }
        let folder = root.appendingPathComponent(id, isDirectory: true)
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &dir), dir.boolValue else { return nil }
        return Self.read(folder, id: id)
    }

    /// Прочитать и проверить папку пака (свою или ещё чужую).
    static func read(_ folder: URL, id: String) -> Entry {
        let url = folder.appendingPathComponent(CharacterPack.configName)
        guard let data = try? Data(contentsOf: url) else {
            return Entry(id: id, folder: folder, config: nil, check: CharacterCheck(errors: ["нет файла character.json"]))
        }
        do {
            let c = try CharacterPack.parse(data)
            let model = folder.appendingPathComponent(CharacterPack.modelName(c))
            let exists = CharacterPack.isSafeFileName(CharacterPack.modelName(c))
                && FileManager.default.fileExists(atPath: model.path)
            return Entry(id: id, folder: folder, config: c, check: CharacterPack.check(c, modelExists: exists))
        } catch {
            let text = (error as? CharacterPackError)?.message ?? "character.json не читается"
            return Entry(id: id, folder: folder, config: nil, check: CharacterCheck(errors: [text]))
        }
    }

    // MARK: установка

    /// Папка из «Файлов» (с character.json внутри) → своя копия. Такая уже есть — заменяем: так чинят пак.
    /// Пак с ошибками ставим тоже: в списке видно, что поправить. Нет конфига или слишком большой — ошибка.
    @discardableResult
    func install(folder src: URL) throws -> Entry {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.appendingPathComponent(CharacterPack.configName).path) else {
            throw CharacterPackError("В папке «\(src.lastPathComponent)» нет character.json")
        }
        try checkSize(Self.size(of: src))
        return try place(id: Self.id(for: src.lastPathComponent)) { tmp in
            for name in try fm.contentsOfDirectory(atPath: src.path) where !name.hasPrefix(".") {
                try fm.copyItem(at: src.appendingPathComponent(name), to: tmp.appendingPathComponent(name))
            }
        }
    }

    /// Отдельные файлы (character.json + модель) → пак по имени из конфига.
    @discardableResult
    func install(files: [URL]) throws -> Entry {
        guard let json = files.first(where: { $0.lastPathComponent.lowercased() == CharacterPack.configName }) else {
            throw CharacterPackError("Среди файлов нет character.json")
        }
        let data: Data
        do { data = try Data(contentsOf: json) } catch { throw CharacterPackError("character.json не открылся") }
        let name = (try? CharacterPack.parse(data))?.name ?? json.deletingLastPathComponent().lastPathComponent
        try checkSize(files.reduce(0) { $0 + Self.size(of: $1) })
        let fm = FileManager.default
        return try place(id: Self.id(for: name)) { tmp in
            for f in files where CharacterPack.isSafeFileName(f.lastPathComponent) {
                let name = f == json ? CharacterPack.configName : f.lastPathComponent
                try fm.copyItem(at: f, to: tmp.appendingPathComponent(name))
            }
        }
    }

    func delete(_ id: String) throws {
        guard CharacterPack.isSafeFileName(id) else { return }
        let folder = root.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// Положить пак целиком: копия во временную папку рядом, потом на место. Сбой — старый пак не тронут.
    @discardableResult
    func place(id: String, fill: (URL) throws -> Void) throws -> Entry {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let tmp = root.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        do {
            try fill(tmp)
            let dest = root.appendingPathComponent(id, isDirectory: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            try? fm.removeItem(at: tmp)
            throw (error as? CharacterPackError) ?? CharacterPackError("Не скопировалось: \(error.localizedDescription)")
        }
        guard let e = entry(id) else { throw CharacterPackError("Не скопировалось") }
        return e
    }

    private func checkSize(_ bytes: Int) throws {
        guard bytes <= Self.maxBytes else {
            throw CharacterPackError("Слишком большой персонаж: \(bytes / 1024 / 1024) МБ, можно до \(Self.maxBytes / 1024 / 1024) МБ")
        }
    }

    /// Имя папки → id: буквы, цифры, «-» и «_», не длиннее 40. Пусто — character.
    static func id(for name: String) -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines).map { ch -> Character in
            ch.isLetter || ch.isNumber || ch == "-" || ch == "_" ? ch : "_"
        }
        var s = String(String(cleaned).prefix(40))
        while s.hasPrefix("_") || s.hasPrefix(".") { s.removeFirst() }
        return s.isEmpty ? "character" : s
    }

    /// Размер файла или папки целиком (байты).
    static func size(of url: URL) -> Int {
        let fm = FileManager.default
        var dir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &dir) else { return 0 }
        if !dir.boolValue {
            return ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        }
        var total = 0
        if let items = try? fm.subpathsOfDirectory(atPath: url.path) {
            for p in items {
                let a = try? fm.attributesOfItem(atPath: url.appendingPathComponent(p).path)
                if a?[.type] as? FileAttributeType == .typeRegular { total += (a?[.size] as? NSNumber)?.intValue ?? 0 }
            }
        }
        return total
    }
}
