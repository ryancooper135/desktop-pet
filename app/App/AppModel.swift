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
    /// Свет комнаты: «Комната вечером» и сон хозяина (RoomLighting). Меняется только при правке, не на каждый тик.
    private(set) var roomSchedule = RoomSchedule.standard
    /// Надетое на собаке (Wear.worn): сцена вешает на кости только при смене.
    private(set) var worn: [WearSlot: String] = [:]
    /// Вещица на полке и мячик для «Поиграть» (ItemCatalog): сцена перестраивает только при смене.
    private(set) var shelf: String? = nil
    private(set) var toy: String? = nil
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

    enum BuzzKind: Sendable { case light, medium, success, warning }

    /// Счётчики хаптики по видам: каждый — свой trigger для .sensoryFeedback.
    struct Buzzes: Equatable, Sendable {
        var light = 0
        var medium = 0
        var success = 0
        var warning = 0
    }

    /// Поза «радость/ест» в приложении держится 12 с (у виджетов — Presenter.reactionWindow, 90 с).
    static let reactionWindow: Double = 12
    static let maxPops = 16

    private(set) var reaction = Reaction(id: 0, kind: "", ok: true, reason: nil)
    /// Куда смотреть: −1…1 по x пальца относительно сцены; nil — пальца нет (через 0,6 с после отпускания).
    private(set) var lookX: Float? = nil
    private(set) var buzz = 0
    private(set) var buzzKind: BuzzKind = .light
    private(set) var buzzes = Buzzes()
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
            noteCharacter(f.character)
            knownTastes = Set(f.tastes.opened.keys)
            // Ушёл гулять при прошлом визите (seen), а вернулся, пока приложение было закрыто, — встретим на входе.
            outing = (f.seen ?? f.pet).outing
        } catch {
            snap = Presenter.make(SaveFile.fresh(now: now), at: now, reactionWindow: Self.reactionWindow)
            storeError = error.localizedDescription
        }
        NotificationScheduler.registerCategories()
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
            let result = try PetStore.shared.mutate { (f: inout SaveFile) -> (report: AwayReport?, paused: Bool) in
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
                return (report, paused)
            }
            if let report = result.report, away == nil { away = report }
            if result.paused { show("Пока подпись не работала, время для \(snap.name) стояло") }
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
            if f.character != character { noteCharacter(f.character) }
            let card = f.pet.alive ? Postcards.active(f, now: now).first(where: { !$0.isSaved }) : nil
            if card != pendingCard { pendingCard = card }
            noteOwnerSleep(f, now: now)
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
            show(RefuseText.text("store"), ok: false)
        }
    }

    /// Прогулка: вернулся — праздник (всплывашка «Принёс шишку!», сердечки, сцена с находкой); гуляет —
    /// пересчитать снимок ровно к возвращению (тикер ходит раз в 30 с).
    private func noteWalk(_ s: PetState) {
        let before = outing
        outing = s.outing
        if let find = Finds.returned(before: before, after: s) {
            walkHome = WalkHome(id: walkHome.id + 1, find: find)
            haptic(.success)
            SoundKit.shared.ambient(.yip)
            pop(Finds.broughtText(find), at: anchor)
            heartBurst()
            notePhoto(PostcardPhotos.walkKind, delay: PostcardCamera.walkDelay)
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
        haptic(.success)
        SoundKit.shared.ambient(.ok)
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

    /// Отклик сразу (реакция сцены + хаптика), ядро — следом. Итог разбирает settle из AppActions.perform.
    func act(_ a: PetAction) {
        react(a.kind)
        haptic(.light)
        SoundKit.shared.play(.button)
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
            // Характер (Traits): игривый подпрыгнет, ласковый склонит голову — только анимация, баланс не трогает.
            react(file.map { Traits.tapKind($0, at: snap.t) } ?? "tap")
            haptic(.light)
            SoundKit.shared.play(.boop)
        }
    }

    /// Щекотка: несколько быстрых тапов подряд.
    func tickle() {
        guard snap.alive, snap.pose != .away else { return }
        react("tickle")
        haptic(.medium)
        SoundKit.shared.play(.yip)
    }

    /// После «Блок Дуо» (волна 12): экран закрылся — Шиба в комнате подпрыгивает, виляет и говорит фразу про партию.
    /// Пауза — чтобы fullScreenCover успел уехать и прыжок было видно. toast — партию бросили посреди: сказать про монеты.
    func cheerBlockDuo(_ r: BlockDuoResult, toast: Bool) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self, !Task.isCancelled else { return }
            if r.played {
                self.react(BlockDuo.reactKind)
                self.haptic(.success)
                SoundKit.shared.play(.yip)
            }
            self.speak(BlockDuo.shibaLine(r))
            if toast, let reward = BlockDuo.rewardText(r) {
                self.show("Блок Дуо: \(r.score) очков, \(reward)", emoji: "🧩")
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
                self.haptic(.success)
                SoundKit.shared.play(.yip)
            }
            self.speak(ZombieRun.shibaLine(r))
            if toast, let reward = ZombieRun.rewardText(r) {
                self.show("Зомби: \(r.score) очков, \(reward)", emoji: "🧟")
            }
        }
    }

    /// Мгновенная реакция сцены, до ответа ядра.
    func react(_ kind: String) {
        reaction = Reaction(id: reaction.id + 1, kind: kind, ok: true, reason: nil)
    }

    func haptic(_ kind: BuzzKind) {
        buzz += 1
        buzzKind = kind
        switch kind {
        case .light: buzzes.light += 1
        case .medium: buzzes.medium += 1
        case .success: buzzes.success += 1
        case .warning: buzzes.warning += 1
        }
    }

    /// Ответ ядра на действие из приложения. AppActions.perform зовёт сразу после записи, до виджетов и острова.
    func settle(_ a: PetAction, _ out: ActOutcome, delta: [String: Int]) {
        SoundKit.shared.settled(kind: a.kind, ok: out.ok)
        if out.ok {
            lastDelta = delta
            haptic(.success)
            popDelta(delta)
            if a == .pet { heartBurst() }
            noteEarn(a, out)
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
            haptic(.warning)
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
        let day = Economy.day(now)
        guard capNoticeDay != day else { return }
        capNoticeDay = day
        if let text = EconText.toast(e) { show(text, emoji: "🪙") }
    }

    /// Вкус еды или игрушки: любимое — сердечки и «Моё любимое!», нелюбимое — сдержанное «😑» и реплика.
    private func noteTaste(_ a: PetAction) {
        guard let f = file, let r = Tastes.reaction(for: a, in: f), r.taste == .love || r.taste == .dislike else { return }
        if r.taste == .love {
            if a != .pet { heartBurst() }
        } else {
            pop("😑", at: anchor)
            haptic(.light)
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
    private func heartBurst() {
        let base = anchor
        let spots: [(dx: CGFloat, dy: CGFloat)] = [(-34, -10), (30, -24), (-6, -44)]
        for (i, s) in spots.enumerated() {
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
            show(RefuseText.text("store"), ok: false)
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
            show(RefuseText.text("store"), ok: false)
        }
    }

    // MARK: свой персонаж (волна 12)

    private func noteCharacter(_ id: String?) {
        character = id
        characterEntry = id.flatMap { CharacterStore.standard.entry($0) }
    }

    func reloadCharacterPacks() {
        characterPacks = CharacterStore.standard.list()
    }

    /// Сделать персонажа активным (nil — вернуть Шибу). Пак с ошибками не ставим — причина тостом.
    func setCharacter(_ id: String?) {
        let entry = id.flatMap { CharacterStore.standard.entry($0) }
        if let entry, !entry.ok {
            show("«\(entry.name)»: \(entry.check.errors.first ?? "пак не прошёл проверку")", ok: false)
            return
        }
        do {
            try PetStore.shared.mutate { (f: inout SaveFile) -> Void in
                f.character = entry?.id
            }
            refresh()
            show(entry.map { "В комнате — \($0.name)" } ?? "Снова Шиба", emoji: "🐾")
        } catch {
            show(RefuseText.text("store"), ok: false)
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
            show((error as? CharacterPackError)?.message ?? error.localizedDescription, ok: false)
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

    func deleteCharacter(_ id: String) {
        if id == character { setCharacter(nil) }
        do {
            try CharacterStore.standard.delete(id)
        } catch {
            show("Не удалился: \(error.localizedDescription)", ok: false)
        }
        reloadCharacterPacks()
    }

    /// Сцена не смогла поставить своего персонажа и показала Шибу. Выбор снимаем, чтобы не ругаться на каждом
    /// запуске; пак остаётся в списке — его можно поправить и поставить заново.
    func characterFailed(_ reason: String) {
        let name = characterEntry?.name ?? "Свой персонаж"
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in f.character = nil }
        refresh()
        show("\(name) не загрузился: \(reason). Вернул Шибу.", ok: false)
    }

    /// Новый щенок: после смерти или при испорченном сторе. Старый файл уходит в state.broken-<t>.json.
    func startOver() {
        do {
            try PetStore.shared.startOver(now: Clock.now())
            storeError = nil
            away = nil
            refresh()
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
    /// pet://blockduo, pet://zombie, pet://brush, pet://habits, pet://kitchen, pet://characters
    func open(_ url: URL) {
        guard url.scheme == "pet" else { return }
        switch url.host {
        case "needs": showNeeds = true
        case "settings": showSettings = true
        case "album": showAlbum = true
        case "capsule": showCapsule = true
        case "shop":
            // Лавка — лист поверх автомата: сначала автомат, потом лист (два листа сразу SwiftUI не покажет).
            showCapsule = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.8))
                self?.showShop = true
            }
        case "house": showHouse = true
        case "tricks": showTricks = true
        case "catch": showCatch = true
        case "blockduo": showBlockDuo = true
        case "zombie": showZombie = true
        case "brush": startBrush()
        case "habits": showHabits = true
        case "kitchen":
            // Кухня — лист поверх «Дома», как лавка поверх автомата.
            showHouse = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.8))
                self?.showKitchen = true
            }
        case "characters":
            // Экран внутри стека настроек: сначала настройки, потом переход (SettingsScreen.navigationDestination).
            showSettings = true
            showCharacters = true
        default:
            showNeeds = false
            showSettings = false
            showAlbum = false
            showCapsule = false
            showShop = false
            showHouse = false
            showTricks = false
            showCatch = false
            showBlockDuo = false
            showZombie = false
            showHabits = false
            showKitchen = false
            showCharacters = false
            postcard = nil
        }
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
            show(RefuseText.text("store"), ok: false)
            return
        }
        refresh()
        if let r = out.reason {
            // Пока лист был открыт, уснул или ушёл: без попытки, только причина.
            haptic(.warning)
            SoundKit.shared.play(.refuse)
            show(Tricks.reasonText(r, for: t), ok: false)
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
            haptic(.light)
            SoundKit.shared.play(.boop)
            show(Tricks.failText, ok: false)
            return
        }
        react(t.kind)
        haptic(.success)
        notePhoto(PostcardPhotos.trickKind, delay: PostcardCamera.actionDelay)
        // «Голос» тявкает сам на прыжке (PetChoreo.begin), если сцена играет клипы; без движения — тявк сразу.
        if t != .speak {
            SoundKit.shared.play(.ok)
        } else if !PetModel.playsReactions {
            SoundKit.shared.play(.yip)
        }
        let love = Int(out.love.rounded())
        if love > 0 {
            lastDelta = ["love": love]
            popDelta(lastDelta)
        }
        if out.learnedNow {
            heartBurst()
            SoundKit.shared.play(.hearts)
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
            show(Brush.reasonText(Tricks.loadingReason), ok: false)
            return
        }
        let now = Clock.now()
        if let r = Brush.gate(f, at: now) {
            haptic(.warning)
            SoundKit.shared.play(.refuse)
            show(Brush.reasonText(r, remaining: Brush.remaining(f, at: now)), ok: false)
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
        haptic(.light)
        SoundKit.shared.play(.brush)
        pop("", at: point ?? anchor, symbol: "sparkles")
        if finished {
            finishBrush()
        }
    }

    /// Против шерсти: пёс морщится, мазок не в счёт.
    func brushAgainst(at point: CGPoint? = nil) {
        guard var s = brush, !s.done else { return }
        s.against += 1
        brush = s
        reaction = Reaction(id: reaction.id + 1, kind: Brush.journalKind, ok: false, reason: nil)
        haptic(.medium)
        SoundKit.shared.play(.refuse)
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
            show(RefuseText.text("store"), ok: false)
            return
        }
        refresh()
        guard out.ok else {
            endBrush()
            haptic(.warning)
            SoundKit.shared.play(.refuse)
            show(Brush.reasonText(out.reason), ok: false)
            return
        }
        react(Brush.journalKind)
        haptic(.success)
        SoundKit.shared.play(.brushDone)
        let love = Int(out.love.rounded())
        if love > 0 {
            lastDelta = ["love": love]
            popDelta(lastDelta)
        }
        show(Brush.doneText(out), emoji: "✨")
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
            show(RefuseText.text("store"), ok: false)
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
                haptic(.success)
                SoundKit.shared.play(.ok)
                if let replaced, let old = EconomyConfig.shared.capsule.itemsById[replaced]?.name {
                    show("Надели «\(name)» вместо «\(old)»", emoji: "👕")
                } else {
                    show("Надели «\(name)»", emoji: "👕")
                }
                Task { await AppActions.shared.afterChange() }
            case .success(.tookOff):
                haptic(.light)
                show("Сняли «\(name)»")
                Task { await AppActions.shared.afterChange() }
            case .failure(.notOwned): show("Этого предмета ещё нет", ok: false)
            case .failure(.notWearable): show("Это не надевается", ok: false)
            }
        } catch {
            show(RefuseText.text("store"), ok: false)
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
                haptic(.success)
                SoundKit.shared.play(.ok)
                show("«\(name)» на полке", emoji: ItemCatalog.emoji(id))
                Task { await AppActions.shared.afterChange() }
            case .success(false):
                haptic(.light)
                show("Убрали «\(name)» с полки")
                Task { await AppActions.shared.afterChange() }
            case .failure(.notOwned): show("Этого предмета ещё нет", ok: false)
            case .failure(.wrongRole): show("Это на полку не ставят", ok: false)
            }
        } catch {
            show(RefuseText.text("store"), ok: false)
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
                haptic(.success)
                SoundKit.shared.play(.ok)
                show("Играем: «\(name)»", emoji: ItemCatalog.emoji(id))
                Task { await AppActions.shared.afterChange() }
            case .success(false):
                haptic(.light)
                show("Снова обычный мячик")
                Task { await AppActions.shared.afterChange() }
            case .failure(.notOwned): show("Этого предмета ещё нет", ok: false)
            case .failure(.wrongRole): show("Этим не поиграешь", ok: false)
            }
        } catch {
            show(RefuseText.text("store"), ok: false)
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
                haptic(.success)
                SoundKit.shared.play(.hearts)
                let name = EconomyConfig.shared.capsule.itemsById[id]?.name ?? id
                show("Купили «\(name)»", emoji: ItemCatalog.emoji(id))
                Task { await AppActions.shared.afterChange() }
            } else {
                haptic(.warning)
                SoundKit.shared.play(.refuse)
            }
            return r
        } catch {
            show(RefuseText.text("store"), ok: false)
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
            show(RefuseText.text("store"), ok: false)
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
            show(RefuseText.text("store"), ok: false)
            return nil
        }
        refresh(now: now)
        guard case .ok(_, let out) = r else {
            haptic(.warning)
            SoundKit.shared.play(.refuse)
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
            show(RefuseText.text("store"), ok: false)
            return nil
        }
        refresh(now: now)
        guard out.ok else {
            haptic(.warning)
            SoundKit.shared.play(.refuse)
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
        haptic(.success)
        SoundKit.shared.settled(kind: Cooking.reactKind, ok: true)
        lastDelta = out.gains
        popDelta(out.gains)
        heartBurst()
        notePhoto(.treat, delay: PostcardCamera.actionDelay)
        // Открылся вкус — его карточка и реплика важнее фразы про блюдо.
        if out.openedTaste == nil { speak(out.text) }
        if out.coins > 0 { show(Cooking.reply(out), emoji: "🪙") }
        // Окно позы «ест» 12 с, тикер — раз в 30 с: пересчитать снимок вовремя (как settle).
        poseTask?.cancel()
        poseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(12_500))
            if Task.isCancelled { return }
            self?.refresh()
        }
    }

    // MARK: волна 10: кадры открыток

    /// Сцена на виду и пёс в настроении: ничего не закрывает комнату, не спит, не гуляет.
    var sceneClear: Bool {
        guard snap.alive, storeError == nil, brush == nil, postcard == nil, away == nil, tasteOpened == nil,
              !showNeeds, !showSettings, !showAlbum, !showCapsule, !showShop, !showHouse, !showTricks, !showCatch,
              !showBlockDuo, !showZombie, !showHabits, !showKitchen else { return false }
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
                haptic(.success)
                SoundKit.shared.play(.ok)
                show("Открытка в альбоме")
            case .expired: show("Открытка уже пропала", ok: false)
            case .notFound: show("Открытки уже нет", ok: false)
            case .albumFull: show("Альбом полон: удали старую открытку", ok: false)
            }
        } catch {
            show(RefuseText.text("store"), ok: false)
        }
        postcardChanged()
    }

    /// «Не надо»: открытка уходит сразу.
    func discardPostcard(_ c: Postcard) {
        do {
            try Postcards.discard(c.id)
            haptic(.light)
        } catch {
            show(RefuseText.text("store"), ok: false)
        }
        postcardChanged()
    }

    /// Удалить из альбома.
    func removePostcard(_ c: Postcard) {
        do {
            try Postcards.remove(c.id)
            haptic(.medium)
        } catch {
            show(RefuseText.text("store"), ok: false)
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

// MARK: - «Пока тебя не было»

struct AwayReport: Identifiable, Sendable {
    struct Card: Identifiable, Hashable, Sendable {
        let id: String
        let icon: String
        let text: String
    }

    let id: String
    let greet: String
    let subtitle: String
    let cards: [Card]
    let cta: String
    let died: Bool
}

/// Лента из 3–6 карточек по away-ключам lines.json. Последняя — подсказка, кнопку рисует экран.
enum AwayBuilder {
    static let minAwayH = 0.5
    static let maxMiddle = 4

    static func make(_ f: SaveFile, prev: PetState, now: Double) -> AwayReport? {
        guard prev.alive, now > prev.t else { return nil }
        let r = Catalog.rules
        let o = PetRunner.owner(f, at: now)
        let s = PetEngine.awaySummary(prev, r, o, now: now, journal: f.timedActs(from: prev.t, to: now))
        let notable = s.events.contains { $0.kind != "sleep" && $0.kind != "wake" }
        guard s.awayH >= minAwayH, s.show || notable || s.died else { return nil }

        let lines = Lines.shared
        let seed = f.petId
        let slot = Int(now / 3600)
        var cards: [AwayReport.Card] = []
        func add(_ key: String, _ icon: String, _ vars: [String: String] = [:]) {
            guard cards.count < maxMiddle, let text = lines.away(key, seed: seed, slot: slot, vars: vars) else { return }
            cards.append(AwayReport.Card(id: key, icon: icon, text: text))
        }

        if s.died {
            let cause = s.events.last(where: { $0.kind == "death" })?.key
            cards.append(AwayReport.Card(id: "death", icon: "heart.slash",
                                         text: deathText(cause, name: f.name)))
            return AwayReport(id: "away-\(Int(now))", greet: "\(f.name) больше нет",
                              subtitle: subtitle(s.awayH), cards: cards,
                              cta: "Можно начать заново с новым щенком.", died: true)
        }

        // Сходил погулять: находка уже в альбоме — первой карточкой, это самое приятное.
        if let b = s.events.last(where: { $0.kind == "back_home" }) {
            add("back_home", "figure.walk", ["item": Finds.name(b.key ?? "")])
        }
        // Кухня с автокормушкой выручила, пока никого не было.
        if s.events.contains(where: { $0.kind == "autofeed" }) {
            add("autofed", "fork.knife")
        }
        if s.sleptH >= 3 {
            add("slept", "moon.zzz")
        } else if s.events.contains(where: { $0.kind == "nap" }) {
            add("nap", "moon")
        }
        if s.events.contains(where: { $0.kind == "heart" }) {
            add("heart_lost", "heart.slash")
        }
        let mood = PetEngine.mood(s.state, r, o, now: now)
        let lonely = s.events.contains { ($0.kind == "distress" && $0.key == "toska") || ($0.kind == "low" && $0.key == "love") }
        if mood == .sulky {
            add("sulked", "cloud")
        } else if lonely {
            add("missed", "heart")
        }

        let steps = f.journal.filter { $0.kind == "act.steps" && $0.ok == true && $0.t > prev.t && $0.t <= now }
            .reduce(0) { $0 + ($1.value ?? 0) }
        if steps > 0 { add("steps", "figure.walk", ["steps": "\(steps)"]) }

        let remote = f.journal.filter {
            $0.kind.hasPrefix("act.") && $0.ok == true && $0.t > prev.t && $0.t <= now
                && $0.source != nil && $0.source != .app && $0.source != .steps
        }.count
        if remote > 0, cards.count < maxMiddle {
            cards.append(AwayReport.Card(id: "remote", icon: "hand.wave",
                                         text: "Ты заботился издалека: \(remote) \(times(remote)). Я заметил."))
        }

        // Одна история «сам по себе»: стабильно по petId и часу, но с оглядкой на шкалы.
        let fun = s.state.needs[.fun] ?? 100
        let love = s.state.needs[.love] ?? 100
        let own: String
        if fun < 30 {
            own = "played_alone"
        } else if love < 30 {
            own = "waited_door"
        } else {
            let pool = ["chased_fly", "waited_door", "played_alone", "zoomies"]
            own = pool[Int(StableHash.fnv1a("\(seed):own:\(slot)") % UInt64(pool.count))]
        }
        add(own, "pawprint")

        if cards.isEmpty { add("nothing", "leaf") }

        let greet = lines.away(s.greet ?? "welcome", seed: seed, slot: slot) ?? "Ты вернулся!"
        let cta = lines.away(s.cta ?? "cta_ok", seed: seed, slot: slot) ?? "Я тут. Загляни ко мне."
        return AwayReport(id: "away-\(Int(now))", greet: greet, subtitle: subtitle(s.awayH),
                          cards: cards, cta: cta, died: false)
    }

    static func subtitle(_ h: Double) -> String {
        if h < 1 { return "Тебя не было \(Int((h * 60).rounded())) мин" }
        if h < 48 { return "Тебя не было \(Int(h.rounded())) ч" }
        return "Тебя не было \(Int((h / 24).rounded())) дн"
    }

    static func times(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return "раз" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "раза" }
        return "раз"
    }

    static func deathText(_ cause: String?, name: String) -> String {
        switch cause {
        case "starve": return "\(name) слишком долго был голодным."
        case "dirty": return "\(name) слишком долго был грязным."
        case "toska": return "\(name) затосковал без тебя."
        default: return "\(name) не дождался."
        }
    }
}

// MARK: - Сиды для тестов и отладки

/// PET_RESET=1 — стереть стор; PET_AWAY_H=<часы> — будто приложение не открывали столько часов;
/// PET_SEED=critical|dead|nap|bath|walk|walk_back — готовое состояние (walk — гуляет ещё 20 мин,
/// walk_back — вернётся через 6 с при открытом приложении, для раскадровки anim-walk;
/// tastes — один открытый вкус и один «???» в альбоме; postcard — неразобранная открытка за вчера;
/// postcard_photo — открытка «играли» за вчера, кадр снимет камера сцены; postcard_expiring — открытке неделя;
/// room_max — все линии дома на верхнем уровне, room_mid — уровни 1–2 вперемешку, для снимков комнаты;
/// house_rich — все линии дома на базе и 50 000 монет: в HouseUITests покупка проходит с первого нажатия;
/// tricks — «Сидеть» выучен, «Лежать» 3 из 5, дальше замки;
/// brush — сытый бодрый щенок со свалявшейся шерстью, для снимков расчёсывания;
/// wear — в коллекции шапочка, бантик, бандана, шарф, плащ и миска, надеты шапочка, шарф и плащ (ui-61/62);
/// memories — месяц вместе: прогулки, трюки, рекорд, вещь, кровать, любимая еда и неделя игр — игривый характер,
/// а в полдень (PET_NOW) пузырь — воспоминание (ui-73/74);
/// items — 14 предметов всех ролей, кубок на полке, теннисный мячик, корона и бабочка, 5000 монет (ui-67/68);
/// fur_shaggy — сытый щенок с лохматой шерстью и клочками на спине (ui-71); fur_brushed — он же, расчёсанный
/// дважды (раз два часа назад, раз только что): гладкая шерсть без клочков (ui-72);
/// blockduo — бодрый щенок с рекордом «Блок Дуо» 1800 (ui-79/80);
/// zombie — бодрый щенок с рекордом «Щенок против зомби» 300 (ui-83/84);
/// charpack — свои персонажи (волна 12) из шибы бандла: «Серый Шиба» (клипы переименованы, рост 0,8, серая
/// шерсть) активен, «Без стойки» — без клипа idle, с ошибкой в списке (ui-81/82)).
/// Срабатывает один раз за запуск.
enum LaunchSeed {
    @MainActor private static var done = false
    /// Сид postcard_photo: какой открытке приложение снимет настоящий кадр после старта.
    @MainActor private(set) static var photoCardId: String? = nil

    @MainActor
    static func applyOnce() {
        guard !done else { return }
        done = true
        if Env.value("PET_RESET") == "1" { PetStore.reset() }
        let away = Env.value("PET_AWAY_H").flatMap { Double($0) }
        let seed = Env.value("PET_SEED")
        guard away != nil || seed != nil else { return }
        let now = Clock.now()
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in
            if let h = away, h > 0 {
                let t = now - h * 3600
                f.pet.t = t
                f.seen = f.pet
                f.lastSeenT = t
            }
            switch seed {
            case "critical":
                PetRunner.catchUp(&f, now: now)
                f.pet.needs[.food] = 0
                f.pet.needs[.clean] = 15
                f.pet.needs[.energy] = 20
                f.pet.needs[.fun] = 10
                f.pet.needs[.love] = 10
                f.pet.hearts = 1
                f.seen = f.pet
                f.lastSeenT = now
            case "dead":
                // Для скриншота экрана «Нет с нами»: умер только что, отчёт «пока не было» не всплывает.
                PetRunner.catchUp(&f, now: now)
                f.pet.needs[.food] = 0
                f.pet.hearts = 0
                f.pet.lastChanceH = nil
                f.pet.alive = false
                f.pet.diedAt = now
                f.pet.cause = .starve
                f.seen = f.pet
                f.lastSeenT = now
            case "nap":
                PetRunner.catchUp(&f, now: now)
                f.pet.napUntil = now + 40 * 60
            case "bath":
                PetRunner.catchUp(&f, now: now)
                f.pet.bathUntil = now + 10 * 60
            case "walk", "walk_back":
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                if seed == "walk" {
                    f.pet.outing = Outing(from: now - 40 * 60, until: now + 20 * 60, find: "cone")
                } else {
                    // Ядро снимает прогулку на шаге в 60 с, засчитанном целиком: состояние «состарено» на 54 с,
                    // и шаг с t ≥ until закончится через 6 с после запуска.
                    f.pet.t = now - 54
                    f.pet.outing = Outing(from: now - 40 * 60, until: f.pet.t, find: "cone")
                }
                f.seen = f.pet
                f.lastSeenT = now
            case "tastes":
                // Любимая еда открыта, нелюбимая игрушка — на полпути (2 из 3).
                PetRunner.catchUp(&f, now: now)
                if let love = Tastes.hidden(petId: f.petId, .food, log: f.tastes).love {
                    f.tastes.opened[Tastes.key(.food, love)] = TasteLog.Fact(r: Taste.love.rawValue, t: now - 3600)
                }
                if let d = Tastes.hidden(petId: f.petId, .toy, log: f.tastes).dislike {
                    f.tastes.seen[Tastes.key(.toy, d)] = TasteLog.Seen(n: 2, t: now - 3600, r: Taste.dislike.rawValue)
                }
            case "postcard_photo":
                // Открытка «играли» за вчера; кадр снимет сама камера сцены после старта (startPhotoChores).
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                let tz = f.owner.tzOffsetMin
                let day = Postcards.day(now, tzOffsetMin: tz) - 1
                let card = Postcards.make(Moment(kind: .play, t: Postcards.dayStart(day, tzOffsetMin: tz) + 17 * 3600 + 20 * 60,
                                                 score: 35), day: day, petId: f.petId, tzOffsetMin: tz)
                if f.cards.card(card.id) == nil { f.cards.pending.append(card) }
                photoCardId = card.id
                f.seen = f.pet
                f.lastSeenT = now
            case "postcard_expiring":
                // Открытка недельной давности: сегодня её последний день (Postcards.isLastDay).
                PetRunner.catchUp(&f, now: now)
                let tz = f.owner.tzOffsetMin
                let day = Postcards.day(now, tzOffsetMin: tz) - Postcards.lifeDays
                let m = Moment(kind: .bath, t: Postcards.dayStart(day, tzOffsetMin: tz) + 11 * 3600 + 5 * 60, score: 30)
                let card = Postcards.make(m, day: day, petId: f.petId, tzOffsetMin: tz)
                if f.cards.card(card.id) == nil { f.cards.pending.append(card) }
            case "postcard":
                // Открытка «первый день» за вчера, ещё не разобрана: карточка на главной.
                PetRunner.catchUp(&f, now: now)
                let tz = f.owner.tzOffsetMin
                let day = Postcards.day(now, tzOffsetMin: tz) - 1
                // Подпись с дефисом («Начало чего-то хорошего»): на снимке видно, что слово не рвётся.
                // petId здесь только зерно выбора строки — перебираем, пока не выпадет нужная.
                let m = Moment(kind: .firstDay, t: now - 86400, score: 100)
                var card = Postcards.make(m, day: day, petId: f.petId, tzOffsetMin: tz)
                for i in 0..<64 where card.lineId != "a.card_first_day.03" {
                    card = Postcards.make(m, day: day, petId: "\(f.petId)-\(i)", tzOffsetMin: tz)
                }
                if f.cards.card(card.id) == nil { f.cards.pending.append(card) }
            case "room_max", "room_mid":
                // Дом в комнате (RoomDecor): уровни ставим прямо, без покупок — монеты и журнал не нужны.
                PetRunner.catchUp(&f, now: now)
                let mid: [HomeLine: Int] = [.bath: 2, .bed: 1, .kitchen: 2, .kennel: 1, .play: 2, .yard: 1]
                for line in HomeLine.allCases {
                    f.pet.home[line] = seed == "room_max" ? RoomPlan.maxLevel : mid[line] ?? 1
                }
            case "house_rich":
                // Экран «Дом» (HouseUITests): комната пустая, монет хватит на любой уровень любой линии.
                PetRunner.catchUp(&f, now: now)
                for line in HomeLine.allCases { f.pet.home[line] = 0 }
                Economy.grant(&f, coins: 50_000)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                f.seen = f.pet
                f.lastSeenT = now
            case "tricks":
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                var sit = TrickLog.Entry()
                sit.n = Tricks.needed
                sit.t = now - 3600
                sit.tries = 9
                sit.learned = now - 3600
                f.tricks[.sit] = sit
                var lie = TrickLog.Entry()
                lie.n = 3
                lie.t = now - 3600
                lie.tries = 6
                f.tricks[.lie] = lie
                f.seen = f.pet
                f.lastSeenT = now
            case "brush":
                // С PET_RESET щенок новорождённый: при look 0 шерсть «свалялась» (Coat.newborn).
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                f.pet.needs[.look] = 0
                f.seen = f.pet
                f.lastSeenT = now
            case "blockduo":
                // «Блок Дуо» (ui-79/80): бодрый щенок, рекорд 1800 — на карточке итога видно «рекорд», в игре — бейдж.
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                f.blockduoBest = max(f.blockduoBest, 1800)
                f.seen = f.pet
                f.lastSeenT = now
            case "zombie":
                // «Щенок против зомби» (ui-83/84): бодрый щенок, рекорд 300 — на карточке «Играть» виден рекорд.
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                f.zombieBest = max(f.zombieBest, 300)
                f.seen = f.pet
                f.lastSeenT = now
            case "fur_shaggy", "fur_brushed":
                // С PET_RESET щенок новорождённый: look 50 — ухоженность 0,30, «лохматая» (CoatFur: 4 клочка).
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                f.pet.needs[.look] = 50
                if seed == "fur_brushed" {
                    // Расчёсывание поднимает на одну стадию: прошлое (лохматая → обычная) и сейчас (→ гладкая).
                    f.createdT = min(f.createdT, now - 3 * 3600)
                    f.log(Brush.actKind, t: now - 2 * 3600, source: .app, ok: true)
                    _ = Brush.finish(&f, now: now)
                }
            case "habits":
                // Экран «Привычки»: утро и три стакана воды отмечены сегодня, зарядка была вчера, остальное — ни разу.
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk] { f.pet.needs[n] = 80 }
                Habits.checkIn(.workout, in: &f, now: now - 86400)
                Habits.checkIn(.wake, in: &f, now: now - 600)
                Habits.checkIn(.water, times: 3, in: &f, now: now - 300)
                f.seen = f.pet
                f.lastSeenT = now
            case "wear":
                // Надетое на собаке (PetWear) и кнопки «Надеть/Снять» в коллекции. Миска — не надевается.
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 80 }
                for id in ["leaf_hat", "bow_blue", "bandana_red", "scarf_knit", "cape_champion", "bowl_plain"] {
                    f.econ.items[id] = 1
                }
                for id in ["leaf_hat", "scarf_knit", "cape_champion"] { _ = Wear.put(&f, id) }
                f.seen = f.pet
                f.lastSeenT = now
            case "sleep_learned", "good_morning":
                // Сон хозяина выучен (OwnerSleep): 10 ночей вокруг 00:40–08:10 с разбросом, последняя — вчера.
                // good_morning: прошлый заход в 00:20 — первый заход утром поздоровается «Доброе утро».
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 80 }
                let day = OwnerSleep.local(now, tzOffsetMin: f.owner.tzOffsetMin).day
                let eve = [-20, 15, 0, -10, 25, 5, -5, 10, -15, 0]
                let morn = [10, -25, 0, 15, -5, 5, -10, 20, 0, -15]
                f.sleep.nights = (0..<10).map { i in
                    SleepLog.Night(n: day - 10 + i, eve: 760 + eve[i], morn: 1210 + morn[i])
                }
                f.sleep.lastT = seed == "good_morning" ? now - 8 * 3600 : now
                f.seen = f.pet
                f.lastSeenT = now
            case "memories":
                seedMemories(&f, now: now)
            case "charpack":
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 80 }
                f.character = seedCharacters()
                f.seen = f.pet
                f.lastSeenT = now
            case "items":
                // Волна 11: коллекция всех трёх ролей с иконками, кубок на полке, теннисный мячик вместо жёлтого,
                // корона и бабочка на собаке; 5000 монет — в лавке «Купить» с первого нажатия.
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 80 }
                for id in ["leaf_hat", "bow_blue", "bell_collar", "beret_red", "bowtie_dots", "wreath_autumn",
                           "crown_champion", "raincoat", "bowl_plain", "pumpkin_small", "lamp_mushroom", "trophy_cup",
                           "ball_tennis", "ball_star"] {
                    f.econ.items[id] = 1
                }
                for id in ["crown_champion", "bowtie_dots"] { _ = Wear.put(&f, id) }
                _ = ItemCatalog.toggleShelf(&f, "trophy_cup")
                _ = ItemCatalog.toggleToy(&f, "ball_tennis")
                f.econ.wallet.coins = 5000
                f.seen = f.pet
                f.lastSeenT = now
            case "kitchen":
                // Волна 12: «Кухня шефа» (L3, скидка и готовка), запас кухни полный, сытость 40 — блюдо видно
                // прибавкой; тыковка в коллекции (суп готов), банки желудей нет (печенье просит вещь).
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 75 }
                f.pet.needs[.food] = 40
                f.pet.home[.kitchen] = 3
                f.pet.pantry = 60
                f.econ.items["pumpkin_small"] = 1
                f.econ.wallet.coins = 500
                // Любимая еда уже открыта: бонус первого блюда — монеты, и на снимке видна фраза пса, а не карточка вкуса.
                if let love = Tastes.hidden(petId: f.petId, .food, log: f.tastes).love {
                    f.tastes.opened[Tastes.key(.food, love)] = TasteLog.Fact(r: Taste.love.rawValue, t: now - 86400)
                }
                f.seen = f.pet
                f.lastSeenT = now
            default:
                break
            }
        }
    }

    /// Сид charpack: два пака из шибы бандла (ничего не качаем), старые паки стираем. Возвращает id рабочего.
    @MainActor
    private static func seedCharacters() -> String? {
        guard let model = Bundle.main.url(forResource: "shiba", withExtension: "usdz"),
              let clips = Bundle.main.url(forResource: "shiba.clips", withExtension: "json"),
              let data = try? Data(contentsOf: clips),
              let timeline = try? JSONDecoder().decode(CharacterPack.Timeline.self, from: data) else { return nil }
        let store = CharacterStore.standard
        try? FileManager.default.removeItem(at: store.root)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        func put(_ c: CharacterConfig) -> String? {
            try? store.place(id: CharacterStore.id(for: c.name)) { dir in
                try FileManager.default.copyItem(at: model, to: dir.appendingPathComponent(CharacterPack.defaultModel))
                try enc.encode(c).write(to: dir.appendingPathComponent(CharacterPack.configName))
            }.id
        }
        _ = put(CharacterPack.sample(timeline, name: "Без стойки", without: ["idle", "happy_wag", "yawn"]))
        return put(CharacterPack.sample(timeline))
    }

    /// Сид memories. Открытки за прошлые дни не всплывают: catchUp — до того, как createdT уходит в прошлое
    /// (doneDay уже вчерашний). petId перебираем, пока в момент now пузырь не станет воспоминанием (PetMind).
    @MainActor
    private static func seedMemories(_ f: inout SaveFile, now: Double) {
        let day: Double = 86400
        PetRunner.catchUp(&f, now: now)
        for n in [Need.food, .clean, .energy, .fun, .love, .walk, .look] { f.pet.needs[n] = 90 }
        f.flags.rulesShown = true
        f.createdT = now - 31 * day
        // Прогулки и находки.
        for (find, ago) in [("cone", 20.0), ("stick", 10), ("sock", 4)] {
            f.pet.finds[find, default: 0] += 1
            f.log("ev.back_home.\(find)", t: now - ago * day, key: find)
        }
        // Трюки.
        for (trick, ago) in [(Trick.sit, 25.0), (.lie, 12)] {
            var e = TrickLog.Entry()
            e.n = Tricks.needed
            e.t = now - ago * day
            e.tries = 8
            e.learned = now - ago * day
            f.tricks[trick] = e
        }
        // Первая вещь из автомата и кровать.
        f.econ.capsule.pulls += 1
        f.econ.items["leaf_hat"] = 1
        f.log("capsule", t: now - 15 * day, key: "leaf_hat", value: 1)
        f.pet.home[.bed] = max(f.pet.home[.bed] ?? 0, 1)
        f.log("home.buy", t: now - 8 * day, key: HomeLine.bed.rawValue, value: 1)
        // Неделя ухода: много игр и прогулок — игривый, остальное ровно.
        let tz = f.owner.tzOffsetMin
        let today = Postcards.day(now, tzOffsetMin: tz)
        for ago in 1...6 {
            var t = Postcards.dayStart(today - ago, tzOffsetMin: tz) + 8 * 3600
            for (kind, n) in [("play", 3), ("walk", 2), ("pet", 5), ("bath", 1), ("brush", 1)] {
                for _ in 0..<n {
                    f.log("act.\(kind)", t: t, source: .app, ok: true)
                    t += 3600
                }
            }
        }
        let base = f
        for i in 0..<128 {
            var g = base
            g.petId = "\(base.petId)-\(i)"
            if let love = Tastes.hidden(petId: g.petId, .food, log: g.tastes).love {
                g.tastes.opened[Tastes.key(.food, love)] = TasteLog.Fact(r: Taste.love.rawValue, t: now - 18 * day)
            }
            // Книга с нуля: рекорд «Лови мячик» побит три дня назад, после начала книги.
            g.memories = MemoryBook()
            g.care = CareTally()
            Memories.update(&g)
            let petT = g.pet.t
            g.pet.t = now - 3 * day
            g.catchBest = max(g.catchBest, 27)
            Memories.update(&g)
            g.pet.t = petT
            Traits.update(&g)
            f = g
            if case .memory? = PetMind.pick(g, at: now, tzOffsetMin: tz),
               let line = PetMind.line(g, at: now, tzOffsetMin: tz),
               Presenter.make(g, at: now).line == line { break }
        }
        f.seen = f.pet
        f.lastSeenT = now
    }
}
