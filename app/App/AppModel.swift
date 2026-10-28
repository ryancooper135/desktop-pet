// Состояние экрана. Источник правды — стор (state.json); модель только держит последнюю копию и снимок.
// «Сейчас» всегда считается от часов: тикер раз в 30 секунд пересчитывает снимок (peek), ничего не пишет.
//
// Вход в приложение: догнать время, срок подписи, собрать «Пока тебя не было» от seen, запомнить seen.
// Уход в фон: снова запомнить seen — действия за сессию не попадают в следующий отчёт.

import CoreGraphics
import Foundation
import Observation
@preconcurrency import PetCore

struct Toast: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let ok: Bool
    /// Значок вместо галочки («🪙» — заработал монеты).
    var emoji: String? = nil
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var file: SaveFile? = nil
    private(set) var snap: PetSnapshot
    var away: AwayReport? = nil
    var toast: Toast? = nil
    /// Стор не читается: показываем экран ошибки, нового щенка сами не заводим.
    private(set) var storeError: String? = nil
    var showNeeds = false
    var showSettings = false
    var showAlbum = false
    /// Автомат с капсулами.
    var showCapsule = false
    /// «Лавка» дня — лист поверх автомата (ShopDaily).
    var showShop = false
    /// Экран «Дом»: улучшения за монеты.
    var showHouse = false
    /// Экран «Двор» (волна 34 G, YardScreen): тайкун во дворе, на весь экран.
    var showYard = false
    /// Лист «Трюки».
    var showTricks = false
    /// Мини-игра «Лови мячик» (CatchGameScreen), на весь экран.
    var showCatch = false
    /// Мини-игра «Блок Дуо» (волна 12, BlockDuoScreen), на весь экран.
    var showBlockDuo = false
    /// Мини-игра «Щенок против зомби» (волна 13, ZombieRunScreen), на весь экран.
    var showZombie = false
    /// Лист «Привычки» (волна 11) по pet://habits; из настроек тот же экран открывается внутри их стека.
    var showHabits = false
    /// Лист «Кухня» (волна 12) поверх «Дома»: угостить едой со скидкой и приготовить блюдо.
    var showKitchen = false
    /// Лист «Уровень» (волна 34 I, HomeChips.LevelChip → LevelSheet).
    var showLevel = false
    /// Вид роста для сцены (PetStage → PetRig); nil — как взрослый (UI-тесты без сида level*). Пишет noteLevel.
    var growthLook: GrowthLook? = nil
    /// Что из уровня и роста уже показали (AppModel+Level).
    @ObservationIgnored var levelSeen = LevelSeen()
    /// Лист «Карта» (волна 34, PlacesMapScreen): походы в места, pet://map.
    var showMap = false
    /// Волна 36 O: о каком походе уже сказали тостом «Сходил: …» (AppModel+Places, notePlaceNews).
    @ObservationIgnored var tripHerald = TripHerald()
    /// Идёт пауза notePlaceBack (1.6 с после праздника прогулки): тост о походе ждёт её.
    @ObservationIgnored var placeBackWaiting = false
    /// Идёт расчёсывание (волна 9): прогресс сеанса; nil — не чешем.
    private(set) var brush: BrushSession? = nil
    /// Колтунов на спине в начале сеанса (по стадии шерсти) — сцена убирает их по мере мазков.
    private(set) var brushTufts = 0
    /// Растёт на каждый засчитанный мазок: сцена пускает шерстинки и искры.
    private(set) var brushPuff = 0

    // MARK: волна 5: монеты, вкусы, шерсть, открытки

    /// Реплика поверх snap.line («Моё любимое!» после вкусной еды), гаснет сама.
    private(set) var sayLine: String? = nil
    /// Только что открытый вкус: карточка «Вкус открыт!» поверх экрана.
    var tasteOpened: TasteFact? = nil
    /// Вид шерсти для сцены. Меняется только при заметной разнице: перекраска материалов не бесплатна.
    private(set) var coat: CoatLook? = nil
    /// Уровни дома для сцены (RoomDecor). Меняются только при покупке: сцена перестраивает вещи по смене значения.
    private(set) var homeLevels = RoomPlan.Levels()
    /// Только UI-тесты (GlassSettle): сколько раз ряды стеклянных кнопок пересоздали поверх готовой комнаты.
    /// В обычном запуске всегда 0.
    private(set) var glassPass = 0
    /// Свет комнаты: «Комната вечером» и сон хозяина (RoomLighting). Меняется только при правке, не на каждый тик.
    private(set) var roomSchedule = RoomSchedule.standard
    /// Надетое на собаке (Wear.worn): сцена вешает на кости только при смене.
    private(set) var worn: [WearSlot: String] = [:]
    /// Вещица на полке и мячик для «Поиграть» (ItemCatalog): сцена перестраивает только при смене.
    private(set) var shelf: String? = nil
    private(set) var toy: String? = nil
    /// Обои, пол и ковёр (волна 41 G, Interior): сцена перекрашивает только при смене.
    private(set) var interior = InteriorShown.standard
    /// Свой персонаж вместо Шибы (волна 12): id папки в CharacterStore и её разбор для сцены; nil — Шиба.
    private(set) var character: String? = nil
    private(set) var characterEntry: CharacterStore.Entry? = nil
    /// Растёт на каждую установку активного пака заново: id тот же, файлы новые — сцена грузит модель снова.
    private(set) var characterRev = 0
    /// Установленные паки для экрана «Свой персонаж». Читаем диск только при открытии экрана и после правок.
    private(set) var characterPacks: [CharacterStore.Entry] = []
    /// Экран «Свой персонаж» внутри настроек (pet://characters).
    var showCharacters = false
    /// Открытка дня, которую ещё не сохранили и не выбросили.
    private(set) var pendingCard: Postcard? = nil
    /// Открытка на экране (лист). Из альбома — сохранённая.
    var postcard: Postcard? = nil

    /// Сколько держится карточка открытого вкуса.
    static let tasteCardFor: Double = 3.5

    // MARK: отклик на касания (juice)

    /// Реакция сцены на действие: id растёт на каждое действие сразу, до ответа ядра; при отказе — ещё раз, с ok = false.
    struct Reaction: Equatable, Sendable {
        var id: Int
        var kind: String
        var ok: Bool
        var reason: String?
    }

    /// Поза «радость/ест» в приложении держится 12 с (у виджетов — Presenter.reactionWindow, 90 с).
    static let reactionWindow: Double = 12
    static let maxPops = 16

    private(set) var reaction = Reaction(id: 0, kind: "", ok: true, reason: nil)
    /// Куда смотреть: −1…1 по x пальца относительно сцены; nil — пальца нет (через 0,6 с после отпускания).
    private(set) var lookX: Float? = nil
    /// Отказы по виду действия (feed, pet, play…): кнопка с этим видом качается.
    private(set) var refusals: [String: Int] = [:]
    private(set) var pops: [Pop] = []
    /// Вернулся с прогулки при открытом приложении (или пока оно было в фоне): id растёт, сцена приводит
    /// Шибу с находкой find, экран празднует. Находка к этому моменту уже в альбоме.
    struct WalkHome: Equatable, Sendable {
        var id: Int
        var find: String
    }
    private(set) var walkHome = WalkHome(id: 0, find: "")
    /// Как изменились видимые шкалы от последнего удачного действия из приложения: ["food": 12, "love": 8].
    var lastDelta: [String: Int] = [:]

    /// Размер сцены и последняя точка пальца — только для размещения всплывашек, экран их не читает.
    @ObservationIgnored var stageSize: CGSize = .zero
    @ObservationIgnored private var popAnchor: CGPoint? = nil

    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var lookTask: Task<Void, Never>?
    @ObservationIgnored private var poseTask: Task<Void, Never>?
    /// Действие, чью реакцию не показали сразу (кнопка была закрыта, ReactBeat.showsAtOnce): покажем по ответу ядра.
    @ObservationIgnored private var heldReaction: String? = nil
    /// Отложенный шаг ссылки pet://… (closeFirst или лист поверх листа). Новая ссылка и «закрыть всё» его отменяют.
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    /// Прогулка на прошлом взгляде на состояние: по её исчезновению ловим возвращение.
    @ObservationIgnored private var outing: Outing? = nil
    @ObservationIgnored private var walkTask: Task<Void, Never>?
    /// К какому возвращению стоит walkTask.
    @ObservationIgnored private var walkAt: Double? = nil
    @ObservationIgnored private var sayTask: Task<Void, Never>?
    @ObservationIgnored private var tasteTask: Task<Void, Never>?
    /// Открытые вкусы на прошлом refresh: новый ключ — карточка «Вкус открыт!». nil — ещё не смотрели.
    @ObservationIgnored private var knownTastes: Set<String>? = nil
    /// В какие сутки уже сказали «На сегодня монет хватит» — не чаще раза в день.
    @ObservationIgnored private var capNoticeDay: Int? = nil
    /// Время последней показанной награды клочками ✂️ — один тост на награду (волна 32).
    @ObservationIgnored private var shardToastT: Double? = nil
    /// Время последнего показанного достижения — тост «Достижение: …» один раз (волна 39 C).
    @ObservationIgnored private var achToastT: Double? = nil
    /// «Доброе утро», пока открыт «Пока тебя не было»: скажем, когда отчёт закроют (sayPending).
    @ObservationIgnored private var pendingLine: String? = nil

    init() {
        LaunchSeed.applyOnce()
        let now = Clock.now()
        do {
            // mutate сам заведёт щенка, если файла ещё нет (первый запуск).
            let f = try PetStore.shared.mutate { (f: inout SaveFile) -> SaveFile in f }
            // Сначала snap (без значения по умолчанию), потом остальное: у @Observable init-аксессоры.
            snap = Presenter.make(f, at: now, reactionWindow: Self.reactionWindow)
            file = f
            homeLevels = RoomPlan.levels(f)
            roomSchedule = f.roomSchedule
            worn = Wear.worn(f)
            shelf = ItemCatalog.shelf(f)
            toy = ItemCatalog.toy(f)
            interior = Interior.shown(f)
            noteCharacter(f.character)
            knownTastes = Set(f.tastes.opened.keys)
            tripHerald.sync(f)
            // Ушёл гулять при прошлом визите (seen), а вернулся, пока приложение было закрыто, — встретим на входе.
            outing = (f.seen ?? f.pet).outing
        } catch {
            snap = Presenter.make(SaveFile.fresh(now: now), at: now, reactionWindow: Self.reactionWindow)
            storeError = error.localizedDescription
        }
        NotificationScheduler.registerCategories()
        noteStoreRecovery()
    }

    /// Стор сам починил сохранение (волна 15) — сказать хозяину, что случилось, а не молча.
    private func noteStoreRecovery() {
        switch PetStore.shared.takeRecovery() {
        case .restored?:
            show("Сохранение было повреждено — взял запасную копию", ok: false)
        case .quarantined(let folder)?:
            show("Сохранение повреждено, копий нет: файлы отложены в \(folder), это новый щенок", ok: false)
        case nil:
            break
        }
    }

    // MARK: жизненный цикл

    func becameActive() {
        let now = Clock.now()
        if Env.isUnitTest || storeError != nil {
            refresh(now: now)
            return
        }
        let expires = ProvisioningProfile.expirationDate()
        do {
            let result = try PetStore.shared.mutate { (f: inout SaveFile) -> (report: AwayReport?, paused: Bool, f: SaveFile) in
                let prev = f.seen ?? f.pet
                // Сначала срок подписи: если сборка истекала, это время питомцу прощается (sign_pause).
                PetRunner.applyBuild(&f, expires: expires, now: now)
                let paused = f.journal.last?.kind == "sign_pause" && f.journal.last?.t == now
                PetRunner.catchUp(&f, now: now)
                let report = paused ? nil : AwayBuilder.make(f, prev: prev, now: now)
                f.seen = f.pet
                f.lastSeenT = now
                // Сон хозяина: зашёл — значит, не спит (OwnerSleep).
                OwnerSleep.note(&f.sleep, t: now, tzOffsetMin: f.owner.tzOffsetMin)
                return (report, paused, f)
            }
            if let report = result.report, away == nil {
                away = report
                // Отчёт уже рассказал о походе карточкой — тоста «Сходил: …» не будет.
                if report.cards.contains(where: { $0.id == "place0" }) { tripHerald.sync(result.f) }
            }
            if result.paused { show("Пока подпись не работала, время в комнате стояло") }
            noteStoreRecovery()
        } catch {
            storeError = error.localizedDescription
        }
        refresh(now: now)
        startTicker()
        startPhotoChores()
        Task { await AppActions.shared.afterActivation() }
    }

    func wentBackground() {
        ticker?.cancel()
        ticker = nil
        if Env.isUnitTest || storeError != nil { return }
        let now = Clock.now()
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in
            PetRunner.catchUp(&f, now: now)
            f.seen = f.pet
            f.lastSeenT = now
            // Ушёл из приложения: вечером это и есть «последний заход» перед сном.
            OwnerSleep.note(&f.sleep, t: now, tzOffsetMin: f.owner.tzOffsetMin)
        }
        Task { await AppActions.shared.afterBackground() }
    }

    /// Перечитать стор и пересчитать снимок на now. Ничего не пишет.
    func refresh(now: Double = Clock.now()) {
        if storeError != nil { return }
        do {
            guard let f = try PetStore.shared.read() else { return }
            file = f
            snap = Presenter.make(f, at: now, reactionWindow: Self.reactionWindow)
            noteWalk(PetRunner.peek(f, at: now))
            noteCoat(Coat.look(f, now: now))
            noteTastes(f)
            let home = RoomPlan.levels(f)
            if home != homeLevels { homeLevels = home }
            let schedule = f.roomSchedule
            if schedule != roomSchedule { roomSchedule = schedule }
            let w = Wear.worn(f)
            if w != worn { worn = w }
            let sh = ItemCatalog.shelf(f), ty = ItemCatalog.toy(f)
            if sh != shelf { shelf = sh }
            if ty != toy { toy = ty }
            let look = Interior.shown(f)
            if look != interior { interior = look }
            if f.character != character { noteCharacter(f.character) }
            let card = f.pet.alive ? Postcards.active(f, now: now).first(where: { !$0.isSaved }) : nil
            if card != pendingCard { pendingCard = card }
            noteOwnerSleep(f, now: now)
            noteLevel(f, now: now)
            notePlaceNews(f, now: now)
            noteAchievement(f, now: now)
        } catch {
            storeError = error.localizedDescription
        }
    }

    // MARK: сон хозяина (OwnerSleep)

    /// Сколько висит «Доброе утро» и «Отбой?» — дольше обычной реплики: их ждут раз в сутки.
    static let sleepLineFor: Double = 8

    /// Утром — «Доброе утро» раз за ночь, вечером у выученного «засыпаю» — «Отбой?» раз за вечер. Только когда
    /// Шиба может сказать: жив, дома и не спит (спал — поздороваемся на следующем заходе этим утром).
    private func noteOwnerSleep(_ f: SaveFile, now: Double) {
        guard !Env.isUnitTest, snap.alive, ![Pose.sleep, .nap, .away, .dead].contains(snap.pose) else { return }
        let tz = f.owner.tzOffsetMin
        if let night = OwnerSleep.greetingDue(f.sleep, now: now, tzOffsetMin: tz) {
            markSleep { $0.greeted = night }
            if let line = sleepLine("good_morning", f, now: now) { say(line) }
            return
        }
        let est = OwnerSleep.estimate(f.sleep, now: now, tzOffsetMin: tz)
        if let night = OwnerSleep.bedHintDue(f.sleep, est: est, bedMin: f.owner.bedMin, now: now, tzOffsetMin: tz) {
            markSleep { $0.hinted = night }
            if let line = sleepLine("bed_hint", f, now: now) { say(line) }
        }
    }

    private func sleepLine(_ key: String, _ f: SaveFile, now: Double) -> String? {
        Lines.shared.pick("widget", key, seed: f.petId, at: now, tzOffsetMin: f.owner.tzOffsetMin,
                          maxLen: LineLimit.widget)?.text
    }

    /// Отметка «уже сказали» прямо в сейв: иначе второй вход тем же утром поздоровается ещё раз.
    private func markSleep(_ change: (inout SleepLog) -> Void) {
        if let f = try? PetStore.shared.mutate({ (f: inout SaveFile) -> SaveFile in
            change(&f.sleep)
            return f
        }) {
            file = f
        }
    }

    /// Поверх «Пока тебя не было» реплику не видно — отложить до закрытия отчёта.
    private func say(_ line: String) {
        if away != nil {
            pendingLine = line
        } else {
            speak(line, for: Self.sleepLineFor)
        }
    }

    /// Отчёт «Пока тебя не было» закрыли (RootView): сказать отложенное.
    func sayPending() {
        guard away == nil, let line = pendingLine else { return }
        pendingLine = nil
        speak(line, for: Self.sleepLineFor)
    }

    /// Окно сна хозяина на сейчас — для строки «Я сплю примерно» в настройках.
    var ownerSleep: SleepEstimate {
        guard let f = file else {
            return SleepEstimate(window: OwnerSleep.defaultWindow, source: .learning(0), nights: 0)
        }
        return OwnerSleep.estimate(f.sleep, now: Clock.now(), tzOffsetMin: f.owner.tzOffsetMin)
    }

    /// «Я сплю примерно»: задать окно вручную или (nil) снова учиться самому. Тихие часы уведомлений — заново.
    func setOwnerSleep(_ w: SleepWindow?) {
        changeOwnerSleep { $0.manual = w }
    }

    /// «Забыть выученное»: ночи и ручное окно — с нуля, до 5 ночей снова 00:00–08:00.
    func forgetOwnerSleep() {
        changeOwnerSleep { log in
            log.nights = []
            log.manual = nil
        }
    }

    private func changeOwnerSleep(_ change: (inout SleepLog) -> Void) {
        do {
            try PetStore.shared.mutate { (f: inout SaveFile) -> Void in change(&f.sleep) }
            refresh()
            Task { await AppActions.shared.afterChange() }
        } catch {
            refuse(RefuseText.text("store"))
        }
    }

    /// Прогулка: вернулся — праздник (всплывашка «Принёс шишку!», сердечки, сцена с находкой); гуляет —
    /// пересчитать снимок ровно к возвращению (тикер ходит раз в 30 с).
    private func noteWalk(_ s: PetState) {
        let before = outing
        outing = s.outing
        if let find = Finds.returned(before: before, after: s) {
            walkHome = WalkHome(id: walkHome.id + 1, find: find)
            Feel.ambient(.success, .yip)
            pop(Finds.broughtText(find), at: anchor)
            heartBurst()
            notePhoto(PostcardPhotos.walkKind, delay: PostcardCamera.walkDelay)
            notePlaceBack()
            // Остров и виджет узнают о возвращении только через синк, иначе остров висит на «Гуляет 0:00».
            Task { await AppActions.shared.afterChange() }
        }
        // Не по сравнению с before: init берёт outing из стора, и на первом refresh прогулка «не меняется» —
        // таймер к возвращению тогда не ставился, и Шиба приходил только с тикером (до 30 с позже).
        guard s.outing?.until != walkAt else { return }
        walkTask?.cancel()
        walkAt = s.outing?.until
        guard let w = s.outing else { return }
        // Ядро снимает прогулку шагом позже until (Finds.backAt) — ждём именно этот шаг.
        let wait = Swift.max(0.5, Finds.backAt(w, stateT: s.t) - Clock.now() + 0.3)
        walkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
            // Ещё гуляет (часы чуть отстали) — следующий refresh поставит таймер заново.
            self?.walkAt = nil
            self?.refresh()
        }
    }

    /// Шерсть: перекрашивать сцену только при смене стадии, клочков или заметной разнице грязи и блеска.
    private func noteCoat(_ c: CoatLook) {
        if let old = coat, old.stage == c.stage, old.tufts == c.tufts, abs(old.dirt - c.dirt) < 0.02, abs(old.shine - c.shine) < 0.02 { return }
        coat = c
    }

    /// Вкус открылся (после действия или находки с прогулки) — карточка и реплика.
    private func noteTastes(_ f: SaveFile) {
        let keys = Set(f.tastes.opened.keys)
        defer { knownTastes = keys }
        guard let known = knownTastes, !keys.isSubset(of: known) else { return }
        guard let fact = Tastes.album(f).last(where: { !known.contains($0.id) }) else { return }
        tasteOpened = fact
        Feel.ambient(.success, .ok)
        if let line = Tastes.line(Tastes.openLineKey, seed: f.petId, at: Clock.now(), tzOffsetMin: f.owner.tzOffsetMin) {
            speak(line)
        }
        tasteTask?.cancel()
        tasteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.tasteCardFor))
            if Task.isCancelled { return }
            self?.tasteOpened = nil
        }
    }

    /// Реплика Шибы поверх обычной на несколько секунд.
    func speak(_ text: String, for seconds: Double = 5) {
        sayLine = text
        sayTask?.cancel()
        sayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if Task.isCancelled { return }
            self?.sayLine = nil
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                self?.refresh()
            }
        }
    }

    // MARK: действия с экрана

    /// Реакция сцены сразу, ядро — следом. Отклик один — итог из settle (AppActions.perform): ядро отвечает
    /// за миллисекунды, а «тик» нажатия перед «получилось/нельзя» был двойным откликом (волна 29).
    /// Волна 32: на закрытую кнопку (спит, откат) реакцию не начинаем — ядро ответит «нельзя», и пёс сразу покажет
    /// отказ, а не начнёт есть или играть, чтобы через миг передумать. Если ядро всё же пустило — покажем в settle.
    func act(_ a: PetAction) {
        let gate = file.flatMap { NeedHints.gates($0, at: Clock.now())[a.kind] }
        if ReactBeat.showsAtOnce(gate) {
            heldReaction = nil
            react(a.kind)
        } else {
            heldReaction = a.kind
        }
        Feel.prepare(.success, .denied)
        Task { _ = await AppActions.shared.perform(a, source: .app) }
    }

    /// Тап по питомцу: в беде — самое срочное (как кнопка «Спасти»), иначе только отклик, без ядра.
    /// Погладить — провести пальцем (StrokeTracker): так тап не тратит кулдаун ласки.
    func tapPet() {
        // Ушёл гулять — комната пустая, трогать некого.
        guard snap.alive, snap.pose != .away else { return }
        if snap.level >= 3, let a = snap.main.action {
            act(a)
        } else {
            // Тап — добавка TapWiggle (голова набок к пальцу, уши, хвост) плюс клип черты у свободного пса
            // (Traits.tapClips: игривый подпрыгнет, ласковый вильнёт) — только анимация, баланс не трогает.
            react(file.map { Traits.tapKind($0, at: snap.t) } ?? "tap")
            Feel.soft(.boop)
        }
    }

    /// Щекотка: несколько быстрых тапов подряд.
    func tickle() {
        guard snap.alive, snap.pose != .away else { return }
        react("tickle")
        Feel.bump(SoundKit.shared.dogCue(.tickle))
    }

    /// После «Блок Дуо» (волна 12): экран закрылся — Шиба в комнате подпрыгивает, виляет и говорит фразу про партию.
    /// Пауза — чтобы fullScreenCover успел уехать и прыжок было видно. toast — партию бросили посреди: сказать про монеты.
    func cheerBlockDuo(_ r: BlockDuoResult, toast: Bool) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self, !Task.isCancelled else { return }
            if r.played {
                self.react(BlockDuo.reactKind)
                Feel.success(.yip)
            }
            // Волна 32: «просто так» (спал, гулял, мылся…) — пёс не играл с нами, фразы в комнате нет.
            if r.free == nil { self.speak(BlockDuo.shibaLine(r)) }
            if toast, let text = BlockDuo.toastText(r) {
                self.show(text, emoji: "🧩")
            }
        }
    }

    /// После «Щенок против зомби» (волна 13): так же, как после «Блок Дуо» — прыжок, виляние и фраза про раунд.
    func cheerZombie(_ r: ZombieResult, toast: Bool) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self, !Task.isCancelled else { return }
            if r.played {
                self.react(ZombieRun.reactKind)
                Feel.success(.yip)
            }
            // Волна 32: «просто так» (спал, гулял, мылся…) — пёс не играл с нами, фразы в комнате нет.
            if r.free == nil { self.speak(ZombieRun.shibaLine(r)) }
            if toast, let reward = ZombieRun.rewardText(r) {
                self.show("Зомби: \(EconText.points(r.score)), \(reward)", emoji: "🧟")
            }
        }
    }

    /// Мгновенная реакция сцены, до ответа ядра.
    func react(_ kind: String) {
        reaction = Reaction(id: reaction.id + 1, kind: kind, ok: true, reason: nil)
    }

    /// Отказ пользователю: тост и мягкое «нельзя» с «не-а» (Feel.denied). Отказ не бывает немым (волна 29).
    func refuse(_ text: String) {
        Feel.denied()
        show(text, ok: false)
    }

    /// Ответ ядра на действие из приложения. AppActions.perform зовёт сразу после записи, до виджетов и острова.
    func settle(_ a: PetAction, _ out: ActOutcome, delta: [String: Int]) {
        let held = heldReaction == a.kind
        heldReaction = nil
        if out.ok {
            if held { react(a.kind) }
            // «Поиграть»: тявк, а изредка игривое рычание (волна 32, PetVoice).
            Feel.success(a == .play ? SoundKit.shared.dogCue(.play) : SoundRecipe.forAction(kind: a.kind, ok: true))
            lastDelta = delta
            popDelta(delta)
            if a == .pet { heartBurst() }
            noteEarn(a, out)
            noteShards()
            noteTaste(a)
            if let k = PostcardPhotos.kind(forAction: a.kind, key: a.key) { notePhoto(k, delay: PostcardCamera.actionDelay) }
            // Окно позы в приложении 12 с, а тикер ходит раз в 30 с — пересчитать снимок вовремя.
            poseTask?.cancel()
            poseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(12_500))
                if Task.isCancelled { return }
                self?.refresh()
            }
        } else {
            reaction = Reaction(id: reaction.id + 1, kind: a.kind, ok: false, reason: out.reason)
            refusals[a.kind, default: 0] += 1
            Feel.denied(SoundRecipe.forAction(kind: a.kind, ok: false))
            pop(Self.refuseIcon(out.reason), at: anchor)
        }
    }

    /// «+5 монет» после действия; «На сегодня монет хватит» — раз в сутки, на действие, упёршееся в потолок.
    private func noteEarn(_ a: PetAction, _ out: ActOutcome) {
        let now = Clock.now()
        if out.coins > 0 {
            let e = Earning(id: "", kind: a.kind, coins: out.coins, capped: false, t: now)
            if let text = EconText.toast(e) { show(text, emoji: "🪙") }
            return
        }
        guard let e = file?.econ.lastEarn, e.capped, e.coins == 0, e.kind == a.kind, now - e.t < 10 else { return }
        let day = DayKey.of(now)
        guard capNoticeDay != day else { return }
        capNoticeDay = day
        if let text = EconText.toast(e) { show(text, emoji: "🪙") }
    }

    /// «+3 ✂️ за день заботы» — клочки редкие, такую награду видно поверх тоста монет.
    private func noteShards() {
        let now = Clock.now()
        guard let f = file, let g = Shards.freshGain(f, now: now, shownT: shardToastT) else { return }
        shardToastT = g.t
        // Достижение — свой тост «Достижение: …» с суммой (несколько разом — одной строкой).
        if g.reason.hasPrefix("ach.") {
            noteAchievement(f, now: now)
            return
        }
        show(Shards.toastText(g), emoji: "✂️")
    }

    /// Волна 39 C: «Достижение: Ур. 10 · +3 ✂️» — один раз на получение, только свежее (до 10 с). Из refresh
    /// (догон, двор, походы) и после действия. В UI-тестах — как сцены уровня: только с сидом level*.
    private func noteAchievement(_ f: SaveFile, now: Double) {
        guard LevelSeen.on, let fr = Achievements.fresh(f, now: now, shownT: achToastT) else { return }
        achToastT = fr.t
        if let text = Achievements.toast(fr.ids) { show(text, emoji: "🏆") }
    }

    /// Вкус еды или игрушки: любимое — сердечки и «Моё любимое!», нелюбимое — сдержанное «😑» и реплика.
    private func noteTaste(_ a: PetAction) {
        guard let f = file, let r = Tastes.reaction(for: a, in: f), r.taste == .love || r.taste == .dislike else { return }
        if r.taste == .love {
            if a != .pet { heartBurst() }
        } else {
            // Без своей вибрации: settle в том же кадре уже дал success (волна 29).
            pop("😑", at: anchor)
        }
        // Только что открылся вкус — его реплика важнее.
        guard tasteOpened == nil, let key = r.lineKey,
              let line = Tastes.line(key, seed: f.petId, at: Clock.now(), tzOffsetMin: f.owner.tzOffsetMin) else { return }
        speak(line)
    }

    /// Всплывашка в точке сцены; сама исчезает через 0,9 с.
    func pop(_ text: String, at point: CGPoint, symbol: String? = nil) {
        let p = Pop(text: text, point: point, symbol: symbol)
        pops.append(p)
        if pops.count > Self.maxPops { pops.removeFirst(pops.count - Self.maxPops) }
        let id = p.id
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.pops.removeAll { $0.id == id }
        }
    }

    /// Палец на сцене: куда смотреть и где всплывать.
    func touch(at point: CGPoint) {
        lookTask?.cancel()
        popAnchor = point
        guard stageSize.width > 0 else { return }
        let x = Swift.min(1, Swift.max(-1, Float(point.x / stageSize.width) * 2 - 1))
        // Шаг 0,05: не дёргать наблюдателей на каждый пиксель.
        let q = (x * 20).rounded() / 20
        if lookX != q { lookX = q }
    }

    /// Палец отпущен: взгляд и точка всплывашек гаснут через 0,6 с.
    func touchEnded() {
        lookTask?.cancel()
        lookTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            self?.lookX = nil
            self?.popAnchor = nil
        }
    }

    /// Погладили и ядро приняло: три сердечка веером вокруг точки, одно за другим.
    /// Волна 31: с Reduce Motion — одно сердечко, без веера.
    private func heartBurst() {
        let base = anchor
        let spots: [(dx: CGFloat, dy: CGFloat)] = [(-34, -10), (30, -24), (-6, -44)]
        for (i, s) in A11y.steps(spots, reduce: Motion.reduce).enumerated() {
            let p = CGPoint(x: base.x + s.dx, y: base.y + s.dy)
            if i == 0 {
                pop("", at: p, symbol: "heart.fill")
                continue
            }
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120 * i))
                self?.pop("", at: p, symbol: "heart.fill")
            }
        }
    }

    /// Точка для всплывашек без пальца: над спиной питомца.
    private var anchor: CGPoint {
        popAnchor ?? CGPoint(x: stageSize.width / 2, y: stageSize.height * 0.45)
    }

    /// «+12 🍖», «+8 ❤» столбиком над точкой касания.
    private func popDelta(_ d: [String: Int]) {
        let base = anchor
        var i = 0
        for need in VisibleNeeds.all {
            guard let v = d[need.rawValue], v > 0 else { continue }
            pop("+\(v) \(Self.needEmoji(need))", at: CGPoint(x: base.x, y: base.y - 26 * CGFloat(i)))
            i += 1
            if i >= 3 { break }
        }
    }

    static func needEmoji(_ n: Need) -> String {
        switch n {
        case .food: return "🍖"
        case .clean: return "🫧"
        case .energy: return "⚡"
        case .fun: return "🎾"
        case .love: return "❤"
        case .walk: return "🐾"
        case .look: return "✨"
        }
    }

    /// Иконка отказа над питомцем (тост — отдельно, его может и не быть).
    static func refuseIcon(_ reason: String?) -> String {
        switch reason {
        case "cooldown": return "⏳"
        case "asleep": return "💤"
        case "tired": return "🥱"
        case "bathing": return "🫧"
        case "not_napping": return "👀"
        case "away": return "🐾"
        case "too_late": return "🌙"
        default: return "✋"
        }
    }

    func doMain() {
        if let a = snap.main.action { act(a) }
    }

    func setBedtime(minute: Int) {
        do {
            try PetRunner.setBedtime(minute: minute)
            refresh()
            Task { await AppActions.shared.afterChange() }
        } catch {
            refuse(RefuseText.text("store"))
        }
    }

    /// «Комната вечером»: по времени, по теме или всегда день. Выбор пишем явно — даже если он совпал
    /// с умолчанием: сменим умолчание (вопрос вкуса) — выбравших руками это не тронет.
    func setRoomEvening(_ mode: RoomEveningMode) {
        do {
            try PetStore.shared.mutate { (f: inout SaveFile) -> Void in
                f.roomEvening = mode.rawValue
            }
            refresh()
        } catch {
            refuse(RefuseText.text("store"))
        }
    }

    // MARK: свой персонаж (волна 12)

    private func noteCharacter(_ id: String?) {
        character = id
        characterEntry = id.flatMap { CharacterStore.standard.entry($0) }
        syncCharacterName()
    }

    /// Имя активного пака — в сохранение (SaveFile.characterName): шапка, виджет, остров и уведомления пак
    /// не читают. Нужна и для сохранений волн 12–13, где имени ещё нет, и после переустановки с новым именем.
    private func syncCharacterName() {
        guard let f = file, let id = f.character, let e = characterEntry, e.id == id, e.ok,
              f.characterName != e.name else { return }
        let name = e.name
        guard let g = try? PetStore.shared.mutate({ (g: inout SaveFile) -> SaveFile in
            if g.character == id { g.characterName = name }
            return g
        }) else { return }
        file = g
        snap = Presenter.make(g, at: Clock.now(), reactionWindow: Self.reactionWindow)
        Task { await AppActions.shared.afterChange() }
    }

    /// Список паков. Сначала разбираем хвосты прерванной установки или удаления (убили посреди копирования):
    /// недокопированное стираем, старый пак из «.old-…» возвращаем на место.
    func reloadCharacterPacks() {
        let store = CharacterStore.standard
        store.recover()
        characterPacks = store.list()
    }

    /// Сделать персонажа активным (nil — вернуть Шибу). Пак с ошибками не ставим — причина тостом.
    func setCharacter(_ id: String?) {
        let entry = id.flatMap { CharacterStore.standard.entry($0) }
        if let entry, !entry.ok {
            refuse("«\(entry.name)»: \(entry.check.errors.first ?? "пак не прошёл проверку")")
            return
        }
        do {
            try PetStore.shared.mutate { (f: inout SaveFile) -> Void in
                f.character = entry?.id
                f.characterName = entry?.name
            }
            refresh()
            Task { await AppActions.shared.afterChange() }
            Feel.select()
            show(entry.map { "В комнате — \($0.name)" } ?? "Снова Шиба", emoji: "🐾")
        } catch {
            refuse(RefuseText.text("store"))
        }
    }

    /// Папки и файлы из «Файлов» (fileImporter). URL чужие: доступ открываем на время копирования и сразу
    /// закрываем. Папка — пак целиком; отдельные файлы — один пак по character.json среди них.
    func installCharacters(_ urls: [URL]) {
        let opened = urls.map { $0.startAccessingSecurityScopedResource() }
        defer {
            for (url, ok) in zip(urls, opened) where ok { url.stopAccessingSecurityScopedResource() }
        }
        let store = CharacterStore.standard
        func isFolder(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        var last: CharacterStore.Entry?
        do {
            for u in urls where isFolder(u) { last = try store.install(folder: u) }
            let files = urls.filter { !isFolder($0) }
            if !files.isEmpty { last = try store.install(files: files) }
        } catch {
            reloadCharacterPacks()
            refuse((error as? CharacterPackError)?.message ?? error.localizedDescription)
            return
        }
        reloadCharacterPacks()
        guard let e = last else { return }
        if e.id == character {
            // Переставили активный: сцена берёт новые файлы, сломанный — Шиба с тостом при загрузке.
            noteCharacter(character)
            characterRev += 1
        }
        if e.ok {
            show("«\(e.name)» установлен", emoji: "📦")
        } else {
            show("«\(e.name)» установлен, но с ошибками — см. список", ok: false)
        }
    }

    /// Удалить пак. Выбранный — сначала вернуть Шибу (даже если стереть потом не выйдет: наполовину
    /// стёртого в сцену не ставим), так что сбой посреди удаления не оставит сохранение со ссылкой в пустоту.
    func deleteCharacter(_ id: String) {
        let wasActive = id == character || file?.character == id
        if wasActive {
            _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in
                f.character = nil
                f.characterName = nil
            }
            refresh()
            noteCharacter(nil)
            Task { await AppActions.shared.afterChange() }
        }
        var failed: Error?
        do {
            try CharacterStore.standard.delete(id)
        } catch {
            failed = error
        }
        reloadCharacterPacks()
        if let failed {
            refuse((failed as? CharacterPackError)?.message ?? "Не удалился: \(failed.localizedDescription)")
        } else if wasActive {
            show("Удалён. Снова Шиба", emoji: "🐾")
        }
    }

    /// Сцена собрана (конец make). В UI-тестах через GlassSettle.delay кнопки со стеклом пересоздаются и смотрят на
    /// готовую комнату — снимки не зависят от того, как быстро раннер её собрал. В обычном запуске ничего не делает.
    func stageBuilt() {
        guard Env.isUITest else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(GlassSettle.delay))
            guard let self else { return }
            self.glassPass = GlassSettle.next(self.glassPass, uiTest: Env.isUITest)
        }
    }

    /// Сцена не смогла поставить своего персонажа и показала Шибу. Выбор снимаем, чтобы не ругаться на каждом
    /// запуске; пак остаётся в списке — его можно поправить и поставить заново.
    func characterFailed(_ reason: String) {
        let name = characterEntry?.name ?? "Свой персонаж"
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in
            f.character = nil
            f.characterName = nil
        }
        refresh()
        Task { await AppActions.shared.afterChange() }
        show("\(name) не загрузился: \(reason). Вернул Шибу.", ok: false)
    }

    /// Новый щенок: после смерти или при испорченном сторе. Старый файл уходит в state.broken-<t>.json.
    func startOver() {
        // Умерший щенок здоровается сам (SoundLayer: alive false → true); живой — здесь.
        let wasAlive = snap.alive
        do {
            try PetStore.shared.startOver(now: Clock.now())
            storeError = nil
            away = nil
            // Сеанс расчёсывания старого пса не достаётся щенку (полоса и жест по спине висели поверх).
            endBrush()
            refresh()
            Feel.success(wasAlive ? .hello : nil)
            Task { await AppActions.shared.afterChange() }
        } catch {
            storeError = error.localizedDescription
        }
    }

    /// Волна 32: пёс убежал — что показать в пустой комнате (Runaway). nil — пёс дома.
    func runawayStatus(now: Double = Clock.now()) -> Runaway.Status? {
        guard let f = file, !f.pet.alive else { return nil }
        return Runaway.status(f, at: now)
    }

    /// «Искать по следам»: один поиск за заход.
    func searchTrail() {
        let now = Clock.now()
        do {
            let out = try PetStore.shared.mutate { (f: inout SaveFile) -> Runaway.Outcome in
                Runaway.searchTrail(&f, now: now)
            }
            refresh(now: now)
            switch out {
            case .found:
                Feel.success(.hearts)
                show(Runaway.toast(out), emoji: "🐾")
            case .ok:
                Feel.soft()
                show(Runaway.toast(out), emoji: "🐾")
            case .no:
                refuse(Runaway.toast(out))
            }
            Task { await AppActions.shared.afterChange() }
        } catch {
            storeError = error.localizedDescription
        }
    }

    /// «Вернуть домой»: нашёлся (следы/шаги) или сразу за ✂️. Тот же пёс — имя, память, вещи.
    func bringBack(_ way: Runaway.Way) {
        let now = Clock.now()
        do {
            let out = try PetStore.shared.mutate { (f: inout SaveFile) -> Runaway.Outcome in
                Runaway.bringBack(&f, way: way, now: now)
            }
            refresh(now: now)
            if out == .ok {
                // Здоровается SoundLayer (alive false → true), как у нового щенка.
                Feel.success()
                show(Runaway.toast(out, way: way), emoji: "🏠")
            } else {
                refuse(Runaway.toast(out))
            }
            Task { await AppActions.shared.afterChange() }
        } catch {
            storeError = error.localizedDescription
        }
    }

    /// «Попробовать снова» на экране ошибки: только чтение. Файла нет — ошибка остаётся, решает хозяин.
    func retryStore() {
        do {
            if let f = try PetStore.shared.read() {
                storeError = nil
                file = f
                snap = Presenter.make(f, at: Clock.now(), reactionWindow: Self.reactionWindow)
                becameActive()
            } else {
                storeError = "Сохранение отложено в сторону, восстановить не из чего."
            }
        } catch {
            storeError = error.localizedDescription
        }
    }

    func show(_ text: String, ok: Bool = true, emoji: String? = nil) {
        toast = Toast(text: text, ok: ok, emoji: emoji)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if Task.isCancelled { return }
            self?.toast = nil
        }
    }

    /// pet://home, pet://needs, pet://settings, pet://album, pet://capsule, pet://shop, pet://house, pet://tricks, pet://catch,
    /// pet://blockduo, pet://zombie, pet://brush, pet://habits, pet://kitchen, pet://characters, pet://map
    func open(_ url: URL) {
        guard url.scheme == "pet" else { return }
        // Волна 25: поверх открытого листа второй SwiftUI молча не покажет, а флаг останется true — и кнопка
        // этого листа потом мёртвая. Открыто что-то не по пути к цели — сначала закрыть всё, потом открыть.
        let host = url.host
        // Волна 30: прошлая ссылка ещё ждёт своего шага — новая важнее (иначе pet://shop, а следом pet://home
        // оставляли showShop = true без автомата: лист не виден, anyCover держит подсказки, лавка выскакивает потом).
        routeTask?.cancel()
        routeTask = nil
        switch DeepLink.step(target: host, open: openRoutes) {
        case .go:
            route(host)
        case .closeFirst:
            closeAllSheets()
            routeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(DeepLink.closeDelay))
                guard let self, !Task.isCancelled else { return }
                self.route(host)
            }
        }
    }

    /// Что показано сейчас — именами хостов pet://… (DeepLink.step).
    var openRoutes: Set<String> {
        var out: Set<String> = []
        let flags: [(Bool, String)] = [
            (showYard, "yard"),
            (showNeeds, "needs"), (showSettings, "settings"), (showAlbum, "album"), (showCapsule, "capsule"),
            (showShop, "shop"), (showHouse, "house"), (showTricks, "tricks"), (showCatch, "catch"),
            (showBlockDuo, "blockduo"), (showZombie, "zombie"), (showHabits, "habits"), (showKitchen, "kitchen"),
            (showCharacters, "characters"), (postcard != nil, "postcard"), (showMap, "map"),
            // Волна 35 N: лист уровня тоже лист — без него pet://map поверх «Уровня» терял карту, флаг оставался true.
            (showLevel, "level"),
        ]
        for (on, name) in flags where on { out.insert(name) }
        return out
    }

    private func route(_ host: String?) {
        switch host {
        case "needs": showNeeds = true
        case "settings": showSettings = true
        case "album": showAlbum = true
        case "capsule": showCapsule = true
        case "shop":
            // Лавка — лист поверх автомата: сначала автомат, потом лист (два листа сразу SwiftUI не покажет).
            showCapsule = true
            follow(host)
        case "house": showHouse = true
        case "yard": showYard = true   // волна 34 G: pet://yard — экран «Двор»
        case "tricks": showTricks = true
        case "catch": showCatch = true
        case "blockduo": showBlockDuo = true
        case "zombie": showZombie = true
        case "brush": startBrush()
        case "habits": showHabits = true
        case "map": showMap = true
        case "kitchen":
            // Кухня — лист поверх «Дома», как лавка поверх автомата.
            showHouse = true
            follow(host)
        case "characters":
            // Экран внутри стека настроек: сначала настройки, потом переход (SettingsScreen.navigationDestination).
            showSettings = true
            showCharacters = true
        default:
            closeAllSheets()
        }
    }

    /// Второй шаг лавки/кухни: через closeDelay лист поверх родителя — только если родитель всё ещё открыт один
    /// (DeepLink.mayFollow). Автомат или «Дом» успели закрыть — флаг ребёнка не ставим: его лист висит внутри родителя.
    private func follow(_ host: String?) {
        guard let child = DeepLink.followUp(host)?.child else { return }
        routeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(DeepLink.closeDelay))
            guard let self, !Task.isCancelled, DeepLink.mayFollow(host, open: self.openRoutes) else { return }
            switch child {
            case "shop": self.showShop = true
            case "kitchen": self.showKitchen = true
            default: break
            }
        }
    }

    /// pet://home: закрыть все листы и обложки комнаты.
    private func closeAllSheets() {
        routeTask?.cancel()
        routeTask = nil
        showNeeds = false
        showSettings = false
        showAlbum = false
        showCapsule = false
        showShop = false
        showHouse = false
        showYard = false
        showTricks = false
        showCatch = false
        showBlockDuo = false
        showZombie = false
        showHabits = false
        showKitchen = false
        showCharacters = false
        showMap = false
        showLevel = false
        postcard = nil
    }

    // MARK: трюки

    /// Команда из листа «Трюки». Лист закрывается, пёс пробует в комнате. Ядро не зовём: исход решает
    /// Tricks.attempt (бросок, счёт, ласка, монеты за первый раз), сцена играет клипы трюка или «Не понял…».
    func doTrick(_ t: Trick) {
        showTricks = false
        // UI-тесты: PET_TRICK_ROLL=0 — всегда выходит, 0.99 — всегда промах.
        let forced = Env.isUITest ? Env.value("PET_TRICK_ROLL").flatMap(Double.init) : nil
        let out: TrickOutcome
        do {
            out = try PetStore.shared.mutate { Tricks.attempt(t, in: &$0, now: Clock.now(), roll: forced) }
        } catch {
            refuse(RefuseText.text("store"))
            return
        }
        refresh()
        if let r = out.reason {
            // Пока лист был открыт, уснул или ушёл: без попытки, только причина.
            refuse(Tricks.reasonText(r, for: t))
            return
        }
        // Лист ещё уезжает вниз: трюк — когда комнату видно.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.trickReaction(t, out)
        }
        if out.love > 0 || out.coins > 0 {
            Task { await AppActions.shared.afterChange() }
        }
    }

    private func trickReaction(_ t: Trick, _ out: TrickOutcome) {
        guard out.ok else {
            reaction = Reaction(id: reaction.id + 1, kind: t.kind, ok: false, reason: nil)
            Feel.nudge(.boop)
            // Подросток упрямится (волна 34 I): без штрафа, другим текстом.
            show(out.refused ? Tricks.refuseText : Tricks.failText, ok: false)
            return
        }
        react(t.kind)
        // Выучил — одно арпеджио сердец, а не «динь» и сердца разом (волна 29).
        // «Голос» тявкает сам на прыжке (PetChoreo.begin), если сцена играет клипы; без движения — тявк сразу.
        let cue: SoundCue? = out.learnedNow ? .hearts : t != .speak ? .ok : PetModel.playsReactions ? nil : .yip
        Feel.success(cue)
        notePhoto(PostcardPhotos.trickKind, delay: PostcardCamera.actionDelay)
        let love = Int(out.love.rounded())
        if love > 0 {
            lastDelta = ["love": love]
            popDelta(lastDelta)
        }
        if out.learnedNow {
            heartBurst()
            let text = "Выучил «\(t.title)»!"
            if out.coins > 0 {
                show("\(text) +\(EconText.coins(out.coins))", emoji: "🪙")
            } else {
                show(text)
            }
        } else {
            show(t.done)
        }
    }

    // MARK: волна 9: расчесать

    /// Начать расчёсывание: лист трюков закрывается, над сценой — полоса прогресса, по спине — колтуны.
    /// Нельзя (спит, гуляет, недавно чесали) — причина тостом.
    func startBrush() {
        showTricks = false
        guard let f = file else {
            refuse(Brush.reasonText(Tricks.loadingReason))
            return
        }
        let now = Clock.now()
        if let r = Brush.gate(f, at: now) {
            refuse(Brush.reasonText(r, remaining: Brush.remaining(f, at: now)))
            return
        }
        brushTufts = Brush.tufts(Coat.look(f, now: now).stage)
        // UI-тесты: PET_BRUSH_STROKES=N — сеанс начинается с N засчитанных мазков (снимки 50% и «готово»).
        let start = Env.isUITest ? Env.value("PET_BRUSH_STROKES").flatMap(Int.init) ?? 0 : 0
        brush = BrushSession(counted: start)
    }

    /// Мазок по шерсти засчитан.
    func brushStroke(at point: CGPoint? = nil) {
        guard var s = brush, !s.done else { return }
        let finished = s.add()
        brush = s
        brushPuff += 1
        pop("", at: point ?? anchor, symbol: "sparkles")
        // Последний мазок — один отклик «дочесали» из finishBrush, а не мазок и успех разом (волна 29).
        if finished {
            finishBrush()
        } else {
            Feel.soft(.brush)
        }
    }

    /// Против шерсти: пёс морщится, мазок не в счёт.
    func brushAgainst(at point: CGPoint? = nil) {
        guard var s = brush, !s.done else { return }
        s.against += 1
        brush = s
        reaction = Reaction(id: reaction.id + 1, kind: Brush.journalKind, ok: false, reason: nil)
        Feel.nudge(.refuse)
        pop("😖", at: point ?? anchor)
    }

    /// Закрыть полосу расчёсывания (крестик или «Готово»). Недочесал — ничего не записано.
    func endBrush() {
        brush = nil
        brushTufts = 0
    }

    /// Дочесали: запись в стор, пёс отряхивается, шерсть на стадию лучше. Полоса остаётся на 100% до «Готово».
    private func finishBrush() {
        let out: BrushOutcome
        do {
            out = try PetStore.shared.mutate { Brush.finish(&$0, now: Clock.now()) }
        } catch {
            endBrush()
            refuse(RefuseText.text("store"))
            return
        }
        refresh()
        guard out.ok else {
            endBrush()
            refuse(Brush.reasonText(out.reason))
            return
        }
        react(Brush.journalKind)
        Feel.success(.brushDone)
        let love = Int(out.love.rounded())
        if love > 0 {
            lastDelta = ["love": love]
            popDelta(lastDelta)
        }
        show(Brush.doneText(out, name: snap.name), emoji: "✨")
        Task { await AppActions.shared.afterChange() }
    }

    // MARK: капсула и открытки

    /// Крутка автомата. Снимок не пересчитываем: экран сам зовёт refresh, когда капсула открылась,
    /// иначе кошелёк и инвентарь выдадут приз раньше анимации. nil — стор не записался.
    func pullCapsule(_ pay: CapsulePay) -> Result<CapsulePull, CapsuleRefusal>? {
        do {
            let r = try CapsuleMachine.perform(pay: pay)
            if case .success = r { Task { await AppActions.shared.afterChange() } }
            return r
        } catch {
            refuse(RefuseText.text("store"))
            return nil
        }
    }

    /// Мастерская ✂️ (волна 32): «Ателье» или лоскутная вещь за клочки. Вернёт текст отказа; nil — взяли
    /// (тост с вещью покажет сама модель) или стор не записался (тогда уже показан отказ стора).
    func takeShardOffer(_ o: ShardOffer) -> String? {
        do {
            let r: Result<CapsuleItem, ShardRefusal>
            switch o.kind {
            case .atelier(let rarity): r = try Shards.performAtelier(rarity)
            case .exclusive(let id): r = try Shards.performBuy(id)
            case .season(let id):
                // Волна 40 F: сезонная вещь — свои отказы («Это продают только зимой»).
                switch try Seasons.perform(id) {
                case .failure(let why):
                    Feel.denied()
                    return Seasons.refusalText(why)
                case .success(let it): r = .success(it)
                }
            }
            switch r {
            case .failure(let why):
                Feel.denied()
                return Shards.refusalText(why)
            case .success(let it):
                refresh()
                if it.rarity >= .epic { Feel.success(.hearts) } else { Feel.success(.ok) }
                show("Теперь у тебя «\(it.name)»", emoji: "✂️")
                Task { await AppActions.shared.afterChange() }
                return nil
            }
        } catch {
            refuse(RefuseText.text("store"))
            return nil
        }
    }

    /// «Надеть» / «Снять» в коллекции. Тот же предмет на месте — снять, иначе надеть (прежнее с этого места снимается).
    func wear(_ id: String) {
        do {
            let r = try Wear.perform(id)
            refresh()
            let name = EconomyConfig.shared.capsule.itemsById[id]?.name ?? id
            switch r {
            case .success(.put(_, let replaced)):
                Feel.success(.ok)
                if let replaced, let old = EconomyConfig.shared.capsule.itemsById[replaced]?.name {
                    show("Надели «\(name)» вместо «\(old)»", emoji: "👕")
                } else {
                    show("Надели «\(name)»", emoji: "👕")
                }
                Task { await AppActions.shared.afterChange() }
            case .success(.tookOff):
                Feel.tap()
                show("Сняли «\(name)»")
                Task { await AppActions.shared.afterChange() }
            case .failure(.notOwned): refuse("Этого предмета ещё нет")
            case .failure(.notWearable): refuse("Это не надевается")
            }
        } catch {
            refuse(RefuseText.text("store"))
        }
    }

    // MARK: волна 11: полка, мячик, лавка

    /// «На полку / Убрать» из коллекции.
    func toggleShelf(_ id: String) {
        do {
            let r = try ItemCatalog.performShelf(id)
            refresh()
            let name = EconomyConfig.shared.capsule.itemsById[id]?.name ?? id
            switch r {
            case .success(true):
                Feel.success(.ok)
                show("«\(name)» на полке", emoji: ItemCatalog.emoji(id))
                Task { await AppActions.shared.afterChange() }
            case .success(false):
                Feel.tap()
                show("Убрали «\(name)» с полки")
                Task { await AppActions.shared.afterChange() }
            case .failure(.notOwned): refuse("Этого предмета ещё нет")
            case .failure(.wrongRole): refuse("Это на полку не ставят")
            }
        } catch {
            refuse(RefuseText.text("store"))
        }
    }

    /// «Играть этим / Обычный мячик» из коллекции.
    func toggleToy(_ id: String) {
        do {
            let r = try ItemCatalog.performToy(id)
            refresh()
            let name = EconomyConfig.shared.capsule.itemsById[id]?.name ?? id
            switch r {
            case .success(true):
                Feel.success(.ok)
                show("Играем: «\(name)»", emoji: ItemCatalog.emoji(id))
                Task { await AppActions.shared.afterChange() }
            case .success(false):
                Feel.tap()
                show("Снова обычный мячик")
                Task { await AppActions.shared.afterChange() }
            case .failure(.notOwned): refuse("Этого предмета ещё нет")
            case .failure(.wrongRole): refuse("Этим не поиграешь")
            }
        } catch {
            refuse(RefuseText.text("store"))
        }
    }

    /// Открыли лавку: витрина суток закрепляется в файле.
    func openShop() {
        try? ShopDaily.open()
        refresh()
    }

    /// Купить с витрины. Купили — тост и кошелёк сразу; отказ экран показывает сам. nil — стор не записался.
    func buyShop(_ id: String) -> ShopDaily.BuyResult? {
        do {
            let r = try ShopDaily.perform(id)
            refresh()
            if case .ok = r {
                Feel.success(.hearts)
                let name = EconomyConfig.shared.capsule.itemsById[id]?.name ?? id
                show("Купили «\(name)»", emoji: ItemCatalog.emoji(id))
                Task { await AppActions.shared.afterChange() }
            } else {
                Feel.denied()
            }
            return r
        } catch {
            refuse(RefuseText.text("store"))
            return nil
        }
    }

    /// Купить следующий уровень линии дома. Купили — снимок, кошелёк и виджеты сразу; отказ экран показывает сам.
    /// nil — стор не записался.
    func buyHome(_ id: HomeLine) -> HomeShop.BuyResult? {
        do {
            let r = try HomeOffer.perform(id)
            refresh()
            if case .ok = r { Task { await AppActions.shared.afterChange() } }
            return r
        } catch {
            refuse(RefuseText.text("store"))
            return nil
        }
    }

    // MARK: волна 12: кухня шефа

    /// «Угостить» на кухне: купить еду и сразу дать (Cooking.buyFood). Вышло — листы закрываются и пёс ест
    /// в комнате, как после «Покормить»; отказ (нет монет, моется…) экран показывает сам строкой под карточкой.
    /// nil — стор не записался.
    func buyFood(_ id: String) -> Cooking.BuyResult? {
        let now = Clock.now()
        let before = try? PetStore.shared.read()
        let r: Cooking.BuyResult
        do {
            r = try PetStore.shared.mutate { Cooking.buyFood(id, in: &$0, now: now) }
        } catch {
            refuse(RefuseText.text("store"))
            return nil
        }
        refresh(now: now)
        guard case .ok(_, let out) = r else {
            Feel.denied()
            return r
        }
        var delta: [String: Int] = [:]
        if let before, let after = file {
            delta = AppActions.delta(PetRunner.peek(before, at: now), PetRunner.peek(after, at: now))
        }
        showKitchen = false
        showHouse = false
        let text = Cooking.buyText(r, name: Catalog.name(id))
        // Листы ещё уезжают: еда — когда комнату видно.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            self.react("feed")
            self.settle(.feed(id), out, delta: delta)
            self.show(text, emoji: "🪙")
        }
        Task { await AppActions.shared.afterChange() }
        return r
    }

    /// «Приготовить» на кухне шефа (Cooking.cook). Вышло — листы закрываются, пёс ест блюдо клипами кормёжки
    /// и говорит фразу; бонус дня — монеты тостом или карточка вкуса (её покажет noteTastes). Отказ — строкой
    /// в листе, листы остаются. nil — стор не записался.
    func cook(_ id: String) -> CookOutcome? {
        let now = Clock.now()
        let out: CookOutcome
        do {
            out = try PetStore.shared.mutate { Cooking.cook(id, in: &$0, now: now) }
        } catch {
            refuse(RefuseText.text("store"))
            return nil
        }
        refresh(now: now)
        guard out.ok else {
            Feel.denied()
            return out
        }
        showKitchen = false
        showHouse = false
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.cookReaction(out)
        }
        Task { await AppActions.shared.afterChange() }
        return out
    }

    private func cookReaction(_ out: CookOutcome) {
        react(Cooking.reactKind)
        Feel.success(SoundRecipe.forAction(kind: Cooking.reactKind, ok: true))
        lastDelta = out.gains
        popDelta(out.gains)
        heartBurst()
        notePhoto(.treat, delay: PostcardCamera.actionDelay)
        // Открылся вкус — его карточка и реплика важнее фразы про блюдо.
        if out.openedTaste == nil { speak(out.text) }
        // Тост — только бонус: фраза про блюдо уже в пузыре, второй раз её не показываем (волна 17).
        if let bonus = Cooking.bonusText(out) { show(bonus, emoji: "🪙") }
        // Окно позы «ест» 12 с, тикер — раз в 30 с: пересчитать снимок вовремя (как settle).
        poseTask?.cancel()
        poseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(12_500))
            if Task.isCancelled { return }
            self?.refresh()
        }
    }

    // MARK: волна 10: кадры открыток

    /// Поверх комнаты что-то открыто: лист, игра, открытка, «Пока тебя не было» или расчёсывание. Подсказки
    /// GuideCenter ждут, пока это пройдёт (волна 23): второй лист поверх первого iOS не показывает и молча роняет.
    var anyCover: Bool {
        brush != nil || postcard != nil || away != nil || showYard
            || showNeeds || showSettings || showAlbum || showCapsule || showShop || showHouse || showTricks || showCatch
            || showBlockDuo || showZombie || showHabits || showKitchen || showMap || showLevel
    }

    /// Сцена на виду и пёс в настроении: ничего не закрывает комнату, не спит, не гуляет.
    var sceneClear: Bool {
        guard snap.alive, storeError == nil, tasteOpened == nil, !anyCover else { return false }
        switch snap.pose {
        case .sleep, .nap, .away, .dead, .critical: return false
        default: return true
        }
    }

    /// Удачный момент ухода: камера тихо снимет сцену, если правила дня разрешают (PostcardPhotos).
    private func notePhoto(_ kind: MomentKind, delay: Double) {
        PostcardCamera.moment(kind, delay: delay) { [weak self] in
            guard let self else { return false }
            return self.sceneClear
        }
    }

    @ObservationIgnored private var photoChoresDone = false

    /// Раз за запуск: убрать кадры-сироты; в UI-тесте с сидом postcard_photo — снять кадр для открытки.
    private func startPhotoChores() {
        guard !photoChoresDone, !Env.isUnitTest else { return }
        photoChoresDone = true
        Task { [weak self] in
            if let id = LaunchSeed.photoCardId {
                // Сцена успевает загрузиться и встать.
                try? await Task.sleep(for: .seconds(3))
                await PostcardCamera.seedPhoto(for: id)
                self?.refresh()
            }
            try? await Task.sleep(for: .seconds(5))
            PostcardCamera.sweep()
        }
    }

    /// «В альбом».
    func savePostcard(_ c: Postcard) {
        do {
            switch try Postcards.save(c.id) {
            case .saved, .already:
                Feel.success(.ok)
                show("Открытка в альбоме")
            case .expired: refuse("Открытка уже пропала")
            case .notFound: refuse("Открытки уже нет")
            case .albumFull: refuse("Альбом полон: удали старую открытку")
            }
        } catch {
            refuse(RefuseText.text("store"))
        }
        postcardChanged()
    }

    /// «Не надо»: открытка уходит сразу.
    func discardPostcard(_ c: Postcard) {
        do {
            try Postcards.discard(c.id)
            Feel.tap()
        } catch {
            refuse(RefuseText.text("store"))
        }
        postcardChanged()
    }

    /// Удалить из альбома.
    func removePostcard(_ c: Postcard) {
        do {
            try Postcards.remove(c.id)
            Feel.tap()
        } catch {
            refuse(RefuseText.text("store"))
        }
        postcardChanged()
    }

    private func postcardChanged() {
        postcard = nil
        refresh()
        // Открытка ушла (выбросили, удалили) — её кадр больше не нужен.
        PostcardCamera.sweep()
        Task { await AppActions.shared.afterChange() }
    }
}
