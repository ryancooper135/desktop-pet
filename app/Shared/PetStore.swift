// Общий стор: один JSON-файл в группе. Пишут приложение, виджеты и интенты (иногда одновременно),
// поэтому каждый доступ идёт через NSFileCoordinator, а внутри процесса — через замок.
// Вложенный mutate внутри mutate запрещён: замок не рекурсивный.
//
// Порча файла: state.json → state.broken-<t>.json, дальше пробуем state.prev.json (копия каждые 10 записей),
// потом зеркало в Documents. Если ничего нет — ошибка, а не новая собака: решает хозяин (startOver).

import Foundation
@preconcurrency import PetCore

enum StoreError: Error, LocalizedError {
    case corrupted(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .corrupted(let s): return "Сохранение повреждено: \(s)"
        case .writeFailed(let s): return "Не получилось сохранить: \(s)"
        }
    }
}

/// Стейт, досчитанный до момента t (без записи на диск).
struct PetNow: Sendable {
    let file: SaveFile
    let pet: PetState
    let owner: Owner
    let t: Double
}

final class PetStore: @unchecked Sendable {
    static let shared = PetStore(dir: Paths.dir)

    let dir: URL
    private let lock = NSLock()

    init(dir: URL) {
        self.dir = dir
        Paths.ensureDir(dir)
    }

    var stateURL: URL { dir.appendingPathComponent("state.json") }
    var prevURL: URL { dir.appendingPathComponent("state.prev.json") }

    // MARK: чтение и запись

    /// nil — файла ещё нет (первый запуск).
    func read() throws -> SaveFile? {
        lock.lock(); defer { lock.unlock() }
        var result: Result<SaveFile?, Error> = .success(nil)
        var coordErr: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: stateURL, options: [], error: &coordErr) { url in
            result = Result { try self.loadUnlocked(url) }
        }
        if let coordErr { throw StoreError.corrupted(coordErr.localizedDescription) }
        return try result.get()
    }

    /// Прочитать, изменить, записать. rev растёт на каждую запись.
    @discardableResult
    func mutate<T>(_ body: (inout SaveFile) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        var result: Result<T, Error>?
        var coordErr: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: stateURL, options: .forMerging, error: &coordErr) { url in
            result = Result {
                var f = try self.loadUnlocked(url) ?? SaveFile.fresh(now: Clock.now())
                let out = try body(&f)
                f.rev += 1
                try self.writeUnlocked(f, to: url)
                return out
            }
        }
        if let coordErr { throw StoreError.writeFailed(coordErr.localizedDescription) }
        guard let result else { throw StoreError.writeFailed("координатор не вызвал запись") }
        return try result.get()
    }

    /// Начать заново: старый файл уходит в broken-<t>, пишется новый щенок.
    func startOver(now: Double = Clock.now()) throws {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        if fm.fileExists(atPath: stateURL.path) {
            try? fm.moveItem(at: stateURL, to: dir.appendingPathComponent("state.broken-\(Int(now)).json"))
        }
        try writeUnlocked(SaveFile.fresh(now: now), to: stateURL)
    }

    /// Стереть всё (PET_RESET=1 в UI-тестах).
    func wipe() {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.removeItem(at: stateURL)
        try? fm.removeItem(at: prevURL)
        #if APP_TARGET
        try? fm.removeItem(at: Paths.mirror)
        #endif
    }

    // MARK: внутреннее (под замком)

    private func decode(_ data: Data) throws -> SaveFile {
        try JSONDecoder().decode(SaveFile.self, from: data)
    }

    private func loadUnlocked(_ url: URL) throws -> SaveFile? {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: url) {
            do { return try decode(data) } catch {
                // Испорченный файл не трогаем, а откладываем в сторону: по нему потом можно разобраться.
                let broken = dir.appendingPathComponent("state.broken-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.moveItem(at: url, to: broken)
                if let f = recover() { return f }
                throw StoreError.corrupted("\(error)")
            }
        }
        // Файла нет: если есть копии — это потеря группы при переподписи, восстанавливаемся из них.
        return recover()
    }

    private func recover() -> SaveFile? {
        var candidates = [prevURL]
        #if APP_TARGET
        candidates.append(Paths.mirror)
        #endif
        for u in candidates {
            if let data = try? Data(contentsOf: u), let f = try? decode(data) { return f }
        }
        return nil
    }

    private func writeUnlocked(_ f: SaveFile, to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data: Data
        do { data = try enc.encode(f) } catch { throw StoreError.writeFailed("\(error)") }
        let opts: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        do { try data.write(to: url, options: opts) } catch { throw StoreError.writeFailed("\(error)") }
        if f.rev % 10 == 0 { try? data.write(to: prevURL, options: opts) }
        #if APP_TARGET
        try? data.write(to: Paths.mirror, options: opts)
        #endif
    }

    // MARK: удобные входы

    /// Файл как есть, без догона времени. Нет файла или он испорчен — свежий щенок (без записи).
    static func load() -> SaveFile {
        ((try? shared.read()) ?? nil) ?? SaveFile.fresh(now: Clock.now())
    }

    /// Стейт, досчитанный до момента date. Ничего не пишет: так читают виджеты и превью.
    static func snapshot(at date: Date = Clock.date()) -> PetNow {
        let f = load()
        let t = date.timeIntervalSince1970
        return PetNow(file: f, pet: PetRunner.peek(f, at: t), owner: f.owner, t: t)
    }

    static func reset() { shared.wipe() }
}
