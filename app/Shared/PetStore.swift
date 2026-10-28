// Общий стор: один JSON-файл в группе. Пишут приложение, виджеты и интенты (иногда одновременно),
// поэтому каждый доступ идёт через NSFileCoordinator, а внутри процесса — через замок.
// Вложенный mutate внутри mutate запрещён: замок не рекурсивный.
//
// Волна 15, надёжность (DECISIONS): щенок умирает только от забвения, не от сбоя.
// - Запись атомарная (временный файл + rename): обрезанного state.json от нас не бывает, при нехватке места
//   старый файл остаётся, а ошибка доходит до вызывающего.
// - Перед каждой записью прошлый валидный state.json кладётся в state.bak.json; state.prev.json — раз в 10 записей;
//   у приложения ещё зеркало в Documents. Порядок восстановления: state → bak → prev → зеркало.
// - Файл есть, но не читается (защита до первой разблокировки, ошибка диска) — ошибка, ничего не трогаем.
// - Читатель (read, виджеты) файлы не двигает: восстанавливает только в памяти. Чинит диск писатель (mutate).
// - Испорчен state, а копия цела — state уходит в state.broken-<t>.json, продолжаем с копии.
// - Испорчено всё — ничего не стираем: файлы уходят в папку corrupt-<дата>, заводится новый щенок
//   с записью save_corrupt в журнале. Нового щенка (с нуля или после порчи) заводит только приложение:
//   виджет и интенты из расширения получают ошибку и ждут приложения (у него ещё есть зеркало).

import Foundation
@preconcurrency import PetCore

enum StoreError: Error, LocalizedError {
    case corrupted(String)
    case writeFailed(String)
    /// Файл есть, но прочитать нельзя: телефон ещё не разблокировали после включения, ошибка диска.
    case unavailable(String)
    /// Сохранения нет, а завести щенка этот процесс не вправе (расширение): нужно открыть приложение.
    case noSave

    var errorDescription: String? {
        switch self {
        case .corrupted(let s): return "Сохранение повреждено: \(s)"
        case .writeFailed(let s): return "Не получилось сохранить: \(s)"
        case .unavailable(let s): return "Сохранение пока недоступно: \(s)"
        case .noSave: return "Сохранения ещё нет — открой приложение"
        }
    }
}

/// Что стор починил сам (для тоста в приложении и тестов).
enum StoreRecovery: Equatable, Sendable {
    /// Основной файл испорчен или пропал — продолжили с копии (имя файла копии).
    case restored(from: String)
    /// Испорчено всё: файлы отложены в папку (имя), заведён новый щенок.
    case quarantined(folder: String)
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

    /// Заводить щенка вправе только приложение (и тесты): у расширений может быть свой контейнер и нет зеркала.
    static let isAppProcess: Bool = Bundle.main.bundleURL.pathExtension != "appex"

    let dir: URL
    let mayCreate: Bool
    private let lock = NSLock()
    private var recovery: StoreRecovery?

    /// Волна 26: последний state.json в памяти (под замком). Ключ — отпечаток файла (inode, время, размер),
    /// снятый до чтения: другой процесс (виджет, интент) пишет атомарно — новый inode и время, кэш мимо.
    /// file — разобранный файл; после своей записи nil (разберём лениво из raw: Codable местами с потерями,
    /// поэтому читатель видит ровно то, что на диске, как и раньше).
    private var cached: (path: String, stamp: FileStamp, raw: Data, file: SaveFile?)?
    /// Сколько раз разбирали JSON (SmoothTests: правка и сколько угодно чтений после неё — один разбор).
    private(set) var decodes = 0

    init(dir: URL, mayCreate: Bool = PetStore.isAppProcess) {
        self.dir = dir
        self.mayCreate = mayCreate
        Paths.ensureDir(dir)
    }

    var stateURL: URL { dir.appendingPathComponent("state.json") }
    var bakURL: URL { dir.appendingPathComponent("state.bak.json") }
    var prevURL: URL { dir.appendingPathComponent("state.prev.json") }

    /// Последняя самопочинка (с прошлого вызова). Приложение показывает по ней тост.
    func takeRecovery() -> StoreRecovery? {
        lock.lock(); defer { lock.unlock() }
        let r = recovery
        recovery = nil
        return r
    }

    // MARK: чтение и запись

    /// nil — сохранения ещё нет (первый запуск). Испорченный файл подменяется копией только в памяти.
    func read() throws -> SaveFile? {
        lock.lock(); defer { lock.unlock() }
        var result: Result<SaveFile?, Error> = .success(nil)
        #if canImport(Darwin)
        var coordErr: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: stateURL, options: [], error: &coordErr) { url in
            result = Result { try self.readUnlocked(url) }
        }
        if let coordErr { throw StoreError.unavailable(coordErr.localizedDescription) }
        #else
        // NSFileCoordinator есть только на Apple; в Linux-сборке логики хватает замка.
        result = Result { try self.readUnlocked(stateURL) }
        #endif
        return try result.get()
    }

    /// Прочитать, изменить, записать. rev растёт на каждую запись.
    @discardableResult
    func mutate<T>(_ body: (inout SaveFile) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        var result: Result<T, Error>?
        #if canImport(Darwin)
        var coordErr: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: stateURL, options: .forMerging, error: &coordErr) { url in
            result = Result { try self.applyUnlocked(url, body) }
        }
        if let coordErr { throw StoreError.writeFailed(coordErr.localizedDescription) }
        #else
        result = Result { try self.applyUnlocked(stateURL, body) }
        #endif
        guard let result else { throw StoreError.writeFailed("координатор не вызвал запись") }
        return try result.get()
    }

    /// Начать заново: старый файл уходит в broken-<t>, пишется новый щенок.
    func startOver(now: Double = Clock.now()) throws {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        var fresh = SaveFile.fresh(now: now)
        // Кошелёк, предметы и гарант переживают щенка (death.keep в economy.json). Файл испорчен — из копий.
        let old = [stateURL, bakURL, prevURL].lazy
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? self.decode($0) }
            .first
        if let old {
            fresh.econ = old.econ.carriedOver()
            // Альбом тоже в death.keep: сохранённые открытки остаются памятью о прошлой собаке.
            fresh.cards = old.cards.carriedOver()
            // Дом тоже (death.keep "house"): купленные улучшения достаются новому щенку.
            fresh.pet.home = old.pet.home
            // «Лови мячик»: рекорд хозяина и дневной потолок монет — не обнуляются новым щенком.
            fresh.catchBest = old.catchBest
            fresh.catchDay = old.catchDay
            fresh.catchCoins = old.catchCoins
            fresh.catchGames = old.catchGames
            // «Блок Дуо» — так же: рекорд хозяина и потолок монет за сутки.
            fresh.blockduoBest = old.blockduoBest
            fresh.blockduoDay = old.blockduoDay
            fresh.blockduoCoins = old.blockduoCoins
            fresh.blockduoGames = old.blockduoGames
            fresh.zombieBest = old.zombieBest
            fresh.zombieDay = old.zombieDay
            fresh.zombieCoins = old.zombieCoins
            fresh.zombieGames = old.zombieGames
            // Надетое — вместе с предметами: шарф остаётся на месте и у нового щенка.
            fresh.worn = old.worn
            // Сон хозяина (OwnerSleep) — тоже: выученное окно про человека, а не про собаку.
            fresh.sleep = old.sleep
            // Полка, игрушка и лавка дня — тоже про вещи, а не про собаку.
            fresh.shelf = old.shelf
            fresh.toy = old.toy
            fresh.shop = old.shop
            // Привычки — хозяина: отметки «Команд» и дневной счётчик остаются.
            fresh.habits = old.habits
            // Кухня шефа — вместе с домом: дневной лимит блюд и бонус не обнуляются новым щенком.
            fresh.cooking = old.cooking
            // Интерьер (волна 41 G) — комната хозяина: обои, пол и ковёр остаются и у нового щенка.
            fresh.interior = old.interior
            fresh.shardLog = old.shardLog.carriedOver()
            // Задания дня (волна 42 J) — день хозяина: тот же набор и те же оплаты, без второго набора за сутки.
            fresh.tasks = old.tasks.carriedOver()
            // Просьбы пса (волна 43 K) — так же: те же просьбы дня и оплаты, курсор журнала с нуля.
            fresh.asks = old.asks.carriedOver()
            // Опыт — про собаку: новый щенок с ур. 1 (волна 32). Без отметки started первый DogLevel.settle принял бы
            // дни заботы хозяина (shardLog.goodDays переходит) за старый сейв и дал до ур. 10, а партии мини-игр
            // прошлого пса за сегодня — за свои (волна 40 E).
            fresh.level.started = true
            fresh.level.day = DayKey.of(now)
            for (game, g) in DogLevel.games(fresh) {
                fresh.level.gameDay[game] = g.day
                fresh.level.gameSeen[game] = g.n
            }
            // Свой персонаж (CharacterStore) — выбор хозяина: новый щенок в том же облике.
            fresh.character = old.character
            fresh.characterName = old.characterName
            // Подсказки жестов (волна 18) — знание хозяина: второй раз учить гладить не надо.
            fresh.tips = old.tips
            // Вкусы (Tastes) — нет: они от petId старого пса, у нового свои любимые находки и еда.
            // Память и характер (memories, care) — тоже нет: они про того пса.
            // Старый файл целиком остаётся в state.broken-<t>.json.
        }
        if fm.fileExists(atPath: stateURL.path) {
            try? fm.moveItem(at: stateURL, to: dir.appendingPathComponent("state.broken-\(Int(now)).json"))
        }
        let data = try writeUnlocked(fresh, to: stateURL, bak: nil)
        // Копия — уже нового щенка: иначе порча state.json до первой правки вернула бы прежнего.
        try? data.write(to: bakURL, options: Self.writeOptions)
    }

    /// Стереть всё (PET_RESET=1 в UI-тестах).
    func wipe() {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.removeItem(at: stateURL)
        try? fm.removeItem(at: bakURL)
        try? fm.removeItem(at: prevURL)
        cached = nil
        #if APP_TARGET
        try? fm.removeItem(at: Paths.mirror)
        #endif
    }

    // MARK: внутреннее (под замком)

    private func decode(_ data: Data) throws -> SaveFile {
        decodes += 1
        return try JSONDecoder().decode(SaveFile.self, from: data)
    }

    /// Отпечаток файла: inode, время правки, размер. nil — файла нет или атрибуты не читаются (тогда без кэша).
    struct FileStamp: Equatable {
        let inode: UInt64
        let modified: Date
        let size: UInt64

        static func of(_ path: String) -> FileStamp? {
            guard let a = try? FileManager.default.attributesOfItem(atPath: path),
                  let m = a[.modificationDate] as? Date,
                  let size = (a[.size] as? NSNumber)?.uint64Value,
                  let inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
            return FileStamp(inode: inode, modified: m, size: size)
        }
    }

    /// Разобранный state.json из памяти, если файл с тех пор не менялся. Вызывать под замком.
    private func cachedMain(_ url: URL, stamp: FileStamp?) -> Found? {
        guard let stamp, let c = cached, c.path == url.path, c.stamp == stamp else { return nil }
        if let f = c.file { return .main(f, raw: c.raw) }
        guard let f = try? decode(c.raw) else { cached = nil; return nil }
        cached = (c.path, c.stamp, c.raw, f)
        return .main(f, raw: c.raw)
    }

    /// Что лежит на диске. Ничего не меняет.
    private enum Found {
        /// state.json цел; raw — его байты (станут state.bak.json перед записью).
        case main(SaveFile, raw: Data)
        /// state.json испорчен (brokenMain) или пропал — взяли копию.
        case copy(SaveFile, from: String, brokenMain: Bool)
        /// Ни файла, ни копий: первый запуск.
        case nothing
        /// Всё, что есть, испорчено.
        case corrupt(String)
    }

    private var copies: [URL] {
        var list = [bakURL, prevURL]
        #if APP_TARGET
        list.append(Paths.mirror)
        #endif
        return list
    }

    private func inspect(_ url: URL) throws -> Found {
        let fm = FileManager.default
        var brokenMain = false
        var why = "основного файла нет, копии испорчены"
        if fm.fileExists(atPath: url.path) {
            // Отпечаток — до чтения: подменят файл между ними — в кэше окажется старый отпечаток, следующий вызов прочтёт заново.
            let stamp = FileStamp.of(url.path)
            if let hit = cachedMain(url, stamp: stamp) { return hit }
            let data: Data
            // Есть, но не читается — не порча: копии в той же папке недоступны так же. Ждём, ничего не трогаем.
            do { data = try Data(contentsOf: url) } catch { throw StoreError.unavailable(error.localizedDescription) }
            do {
                let f = try decode(data)
                if let stamp { cached = (url.path, stamp, data, f) } else { cached = nil }
                return .main(f, raw: data)
            } catch {
                cached = nil
                brokenMain = true
                why = data.isEmpty ? "пустой файл" : "\(error)"
            }
        } else {
            cached = nil
        }
        var anyCopy = false
        for u in copies where fm.fileExists(atPath: u.path) {
            anyCopy = true
            if let data = try? Data(contentsOf: u), let f = try? decode(data) {
                return .copy(f, from: u.lastPathComponent, brokenMain: brokenMain)
            }
        }
        return brokenMain || anyCopy ? .corrupt(why) : .nothing
    }

    private func readUnlocked(_ url: URL) throws -> SaveFile? {
        switch try inspect(url) {
        case .main(let f, _): return f
        case .copy(let f, _, _): return f
        case .nothing: return nil
        case .corrupt(let why): throw StoreError.corrupted(why)
        }
    }

    /// Прочитать (починив, если надо), применить правку, поднять rev и записать. Вызывать под замком.
    /// Тело бросило — на диске ничего не меняется (и испорченное не двигаем).
    private func applyUnlocked<T>(_ url: URL, _ body: (inout SaveFile) throws -> T) throws -> T {
        let now = Clock.now()
        let found = try inspect(url)
        var f: SaveFile
        var bak: Data?
        switch found {
        case .main(let g, let raw):
            f = g
            bak = raw
        case .copy(let g, let from, _):
            f = g
            f.log("save_restored", t: now, ok: true, reason: "основной файл испорчен или пропал, взята копия", key: from)
        case .nothing:
            guard mayCreate else { throw StoreError.noSave }
            f = SaveFile.fresh(now: now)
        case .corrupt(let why):
            guard mayCreate else { throw StoreError.corrupted(why) }
            f = SaveFile.fresh(now: now)
            f.log("save_corrupt", t: now, ok: false,
                  reason: "сохранение и все копии испорчены (\(why.prefix(120))), файлы отложены, заведён новый щенок")
        }
        // Сейв старше волны 15: пояс рождения — пояс телефона на момент рождения, записывается один раз.
        if f.birthTz == nil { f.birthTz = Clock.tzOffsetMin(at: f.createdT) }
        let out = try body(&f)
        // Память и характер — из того, что только что записано (новые записи журнала разбираются один раз).
        Memories.update(&f)
        Traits.update(&f)
        f.rev += 1
        // Диск чиним только теперь, когда тело не бросило.
        switch found {
        case .copy(_, let from, let brokenMain):
            if brokenMain {
                // Испорченный файл не стираем, а откладываем: по нему потом можно разобраться.
                try moveAside(url, to: dir.appendingPathComponent("state.broken-\(Int(now)).json"))
            }
            recovery = .restored(from: from)
        case .corrupt:
            let folder = try quarantine(now: now)
            if let i = f.journal.lastIndex(where: { $0.kind == "save_corrupt" }) {
                f.journal[i].key = folder
                let id = f.journal[i].id
                if let j = f.outbox.lastIndex(where: { $0.id == id }) { f.outbox[j].key = folder }
            }
            recovery = .quarantined(folder: folder)
        case .main, .nothing:
            break
        }
        try writeUnlocked(f, to: url, bak: bak)
        return out
    }

    /// Перенести файл; не вышло — ошибка: иначе следующая запись затёрла бы его.
    private func moveAside(_ from: URL, to: URL) throws {
        do { try FileManager.default.moveItem(at: from, to: to) } catch {
            throw StoreError.corrupted("не получилось отложить \(from.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Всё испорченное — в папку corrupt-<дата> рядом (зеркало приложения копируется: его место перезапишется).
    private func quarantine(now: Double) throws -> String {
        let fm = FileManager.default
        let stamp = Self.stamp(now)
        var name = "corrupt-\(stamp)"
        var n = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = "corrupt-\(stamp)-\(n)"
            n += 1
        }
        let folder = dir.appendingPathComponent(name, isDirectory: true)
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            throw StoreError.corrupted("не получилось создать \(name): \(error.localizedDescription)")
        }
        for u in [stateURL, bakURL, prevURL] where fm.fileExists(atPath: u.path) {
            try moveAside(u, to: folder.appendingPathComponent(u.lastPathComponent))
        }
        #if APP_TARGET
        if fm.fileExists(atPath: Paths.mirror.path) {
            try? fm.copyItem(at: Paths.mirror, to: folder.appendingPathComponent(Paths.mirror.lastPathComponent))
        }
        #endif
        return name
    }

    /// «2026-10-19-1050» по UTC: без DateFormatter, одинаково на Linux и на телефоне.
    static func stamp(_ t: Double) -> String {
        let m = DayKey.minute(t)
        let day = DayKey.floorDiv(m, 1440)
        let (y, mo, d) = Postcards.civil(day)
        let hm = m - day * 1440
        func two(_ x: Int) -> String { x < 10 ? "0\(x)" : "\(x)" }
        return "\(y)-\(two(mo))-\(two(d))-\(two(hm / 60))\(two(hm % 60))"
    }

    #if canImport(Darwin)
    private static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    #else
    private static let writeOptions: Data.WritingOptions = [.atomic]
    #endif

    /// bak — прошлый валидный state.json: кладётся до записи нового. Ошибка копии не мешает записи.
    @discardableResult
    private func writeUnlocked(_ f: SaveFile, to url: URL, bak: Data?) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data: Data
        do { data = try enc.encode(f) } catch { throw StoreError.writeFailed("\(error)") }
        let opts = Self.writeOptions
        if let bak { try? bak.write(to: bakURL, options: opts) }
        // Атомарно: временный файл и rename. Нет места — бросаем, а прежний state.json цел.
        do { try data.write(to: url, options: opts) } catch {
            cached = nil
            throw StoreError.writeFailed("\(error)")
        }
        // Записанное — в кэш байтами; разберём при первом чтении (не доверяем f: кодеки местами с потерями).
        if let stamp = FileStamp.of(url.path) { cached = (url.path, stamp, data, nil) } else { cached = nil }
        if f.rev % 10 == 0 { try? data.write(to: prevURL, options: opts) }
        #if APP_TARGET
        try? data.write(to: Paths.mirror, options: opts)
        #endif
        return data
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
