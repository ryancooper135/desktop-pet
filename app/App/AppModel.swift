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
    /// Экран «Дом»: улучшения за монеты.
    var showHouse = false
    /// Лист «Трюки».
    var showTricks = false

    // MARK: волна 5: монеты, вкусы, шерсть, открытки

    /// Реплика поверх snap.line («Моё любимое!» после вкусной еды), гаснет сама.
    private(set) var sayLine: String? = nil
    /// Только что открытый вкус: карточка «Вкус открыт!» поверх экрана.
    var tasteOpened: TasteFact? = nil
    /// Вид шерсти для сцены. Меняется только при заметной разнице: перекраска материалов не бесплатна.
    private(set) var coat: CoatLook? = nil
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

    init() {
        LaunchSeed.applyOnce()
        let now = Clock.now()
        do {
            // mutate сам заведёт щенка, если файла ещё нет (первый запуск).
            let f = try PetStore.shared.mutate { (f: inout SaveFile) -> SaveFile in f }
            // Сначала snap (без значения по умолчанию), потом остальное: у @Observable init-аксессоры.
            snap = Presenter.make(f, at: now, reactionWindow: Self.reactionWindow)
            file = f
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
                return (report, paused)
            }
            if let report = result.report, away == nil { away = report }
            if result.paused { show("Пока подпись не работала, время для \(snap.name) стояло") }
        } catch {
            storeError = error.localizedDescription
        }
        refresh(now: now)
        startTicker()
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
            let card = f.pet.alive ? Postcards.active(f, now: now).first(where: { !$0.isSaved }) : nil
            if card != pendingCard { pendingCard = card }
        } catch {
            storeError = error.localizedDescription
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

    /// Шерсть: перекрашивать сцену только при смене стадии или заметной разнице грязи и блеска.
    private func noteCoat(_ c: CoatLook) {
        if let old = coat, old.stage == c.stage, abs(old.dirt - c.dirt) < 0.02, abs(old.shine - c.shine) < 0.02 { return }
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
            react("tap")
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

    /// pet://home, pet://needs, pet://settings, pet://album, pet://capsule, pet://house, pet://tricks
    func open(_ url: URL) {
        guard url.scheme == "pet" else { return }
        switch url.host {
        case "needs": showNeeds = true
        case "settings": showSettings = true
        case "album": showAlbum = true
        case "capsule": showCapsule = true
        case "house": showHouse = true
        case "tricks": showTricks = true
        default:
            showNeeds = false
            showSettings = false
            showAlbum = false
            showCapsule = false
            showHouse = false
            showTricks = false
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
        // «Голос» тявкает сам на прыжке (PetChoreo.begin).
        if t != .speak { SoundKit.shared.play(.ok) }
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
/// tricks — «Сидеть» выучен, «Лежать» 3 из 5, дальше замки).
/// Срабатывает один раз за запуск.
enum LaunchSeed {
    @MainActor private static var done = false

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
                for n in [Need.food, .clean, .energy, .fun, .love] { f.pet.needs[n] = 80 }
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
            case "postcard":
                // Открытка «первый день» за вчера, ещё не разобрана: карточка на главной.
                PetRunner.catchUp(&f, now: now)
                let tz = f.owner.tzOffsetMin
                let day = Postcards.day(now, tzOffsetMin: tz) - 1
                let card = Postcards.make(Moment(kind: .firstDay, t: now - 86400, score: 100),
                                          day: day, petId: f.petId, tzOffsetMin: tz)
                if f.cards.card(card.id) == nil { f.cards.pending.append(card) }
            case "tricks":
                PetRunner.catchUp(&f, now: now)
                for n in [Need.food, .clean, .energy, .fun, .love] { f.pet.needs[n] = 80 }
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
            default:
                break
            }
        }
    }
}
