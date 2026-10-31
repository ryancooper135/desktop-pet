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
        /// Метка установки (волна 15): своя на каждую установку, даже в ту же папку. Шапка по ней сбрасывает
        /// аватар, а снимок морды старой модели, досчитанный после переустановки, в новую папку не пишется.
        var stamp: String = ""
        var name: String { config.map { PetNames.clean($0.name) }.flatMap { $0.isEmpty ? nil : $0 } ?? id }
        var ok: Bool { config != nil && check.ok }
        var modelURL: URL? { config.map { folder.appendingPathComponent(CharacterPack.modelName($0)) } }

        /// Аватар для шапки (волна 14): avatar.png из пака, иначе снимок морды, отрисованный приложением
        /// один раз (avatarCacheURL). nil — ни того ни другого: шапка рисует мордочку Шибы, пока снимка нет.
        var avatarURL: URL? {
            let fm = FileManager.default
            let own = folder.appendingPathComponent(CharacterStore.avatarName)
            if fm.fileExists(atPath: own.path) { return own }
            let cache = avatarCacheURL
            return fm.fileExists(atPath: cache.path) ? cache : nil
        }

        /// Свой avatar.png в паке — снимок не нужен.
        var hasOwnAvatar: Bool {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(CharacterStore.avatarName).path)
        }

        /// Куда кладём снимок морды. С точки: при переустановке из «Файлов» не копируется (install пропускает
        /// скрытые), а вместе со старой папкой уходит — новая модель снимается заново.
        var avatarCacheURL: URL { folder.appendingPathComponent(CharacterStore.avatarCacheName) }
    }

    /// Необязательная картинка пака для шапки.
    static let avatarName = "avatar.png"
    /// Снимок морды, отрисованный приложением (CharacterAvatar).
    static let avatarCacheName = ".avatar-snapshot.png"
    /// Метка установки (Entry.stamp). С точки — install её не копирует и в список не попадает.
    static let stampName = ".installed"

    /// Метка установки папки: пусто — пак старше волны 15 (или метка не записалась).
    static func stamp(of folder: URL) -> String {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent(stampName)) else { return "" }
        return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var standard: CharacterStore {
        let env = Env.vars
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
        var e = parse(folder, id: id)
        e.stamp = stamp(of: folder)
        return e
    }

    private static func parse(_ folder: URL, id: String) -> Entry {
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

    /// Удалить пак: сначала переименовать в «.trash-…» — из списка он пропадает целиком и сразу, — потом стереть.
    /// Не стёрлось до конца — хвост уберёт recover. Переименовать не вышло — ошибка, пак на месте.
    func delete(_ id: String) throws {
        guard Self.isPackName(id) else { return }
        let fm = FileManager.default
        let folder = root.appendingPathComponent(id, isDirectory: true)
        guard fm.fileExists(atPath: folder.path) else { return }
        let trash = root.appendingPathComponent("\(Self.trashPrefix)\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.moveItem(at: folder, to: trash)
        } catch {
            throw CharacterPackError("Не удалился: \(error.localizedDescription)")
        }
        try? fm.removeItem(at: trash)
    }

    /// Положить пак целиком: копия во временную папку «.incoming-…» рядом, потом подмена переименованиями.
    /// Старый пак на время подмены уходит в «.old-<uuid>.<id>»; не встал новый — старый возвращается на место.
    /// Сбой посреди копирования (кончилось место, файл не читается) — временная папка стирается, старый пак цел.
    /// Убили между переименованиями — recover при следующей установке или открытии списка вернёт старый.
    @discardableResult
    func place(id: String, fill: (URL) throws -> Void) throws -> Entry {
        guard Self.isPackName(id) else { throw CharacterPackError("Плохое имя папки персонажа: \(id)") }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        recover()
        let tmp = root.appendingPathComponent("\(Self.incomingPrefix)\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        func fail(_ error: Error) -> Error {
            try? fm.removeItem(at: tmp)
            return (error as? CharacterPackError) ?? CharacterPackError("Не скопировалось: \(error.localizedDescription)")
        }
        do { try fill(tmp) } catch { throw fail(error) }
        // Своя метка на каждую установку (Entry.stamp); снимок морды, если вдруг попал в копию, — убрать.
        try? fm.removeItem(at: tmp.appendingPathComponent(Self.avatarCacheName))
        try? Data(UUID().uuidString.utf8).write(to: tmp.appendingPathComponent(Self.stampName), options: .atomic)
        let dest = root.appendingPathComponent(id, isDirectory: true)
        var backup: URL?
        if fm.fileExists(atPath: dest.path) {
            let b = root.appendingPathComponent("\(Self.oldPrefix)\(UUID().uuidString).\(id)", isDirectory: true)
            do { try fm.moveItem(at: dest, to: b) } catch { throw fail(error) }
            backup = b
        }
        do {
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            if let b = backup { try? fm.moveItem(at: b, to: dest) }
            throw fail(error)
        }
        if let b = backup { try? fm.removeItem(at: b) }
        guard let e = entry(id) else { throw CharacterPackError("Не скопировалось") }
        return e
    }

    // MARK: хвосты прерванных установок и удалений

    static let incomingPrefix = ".incoming-"
    static let oldPrefix = ".old-"
    static let trashPrefix = ".trash-"

    /// Имя папки пака: безопасное и не служебное (служебные начинаются с точки).
    static func isPackName(_ id: String) -> Bool {
        CharacterPack.isSafeFileName(id) && !id.hasPrefix(".")
    }

    /// «.incoming-…» (недокопированное) и «.trash-…» (недостёртое) — стереть; «.old-<uuid>.<id>» — вернуть
    /// на место, если пака <id> нет (подмену прервали), иначе стереть. Всё зовётся с главного потока
    /// (AppModel), поэтому чужое копирование посреди работы не заденет. Возвращает, сколько хвостов разобрано.
    @discardableResult
    func recover() -> Int {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return 0 }
        var n = 0
        for name in names.sorted() {
            let url = root.appendingPathComponent(name, isDirectory: true)
            if name.hasPrefix(Self.incomingPrefix) || name.hasPrefix(Self.trashPrefix) {
                try? fm.removeItem(at: url)
                n += 1
            } else if name.hasPrefix(Self.oldPrefix) {
                let rest = name.dropFirst(Self.oldPrefix.count)
                let id = rest.firstIndex(of: ".").map { String(rest[rest.index(after: $0)...]) } ?? ""
                let dest = root.appendingPathComponent(id, isDirectory: true)
                if Self.isPackName(id), !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: url, to: dest)
                } else {
                    try? fm.removeItem(at: url)
                }
                n += 1
            }
        }
        return n
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
