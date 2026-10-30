// Единая точка для действий из приложения и интентов (IntentBridge под APP_TARGET зовёт сюда).
// После любого изменения: виджеты, остров, уведомления, бэкап. Ошибки стора не роняют приложение — тост.

import Foundation
import WidgetKit
@preconcurrency import PetCore

@MainActor
final class AppActions {
    static let shared = AppActions()

    let backup: any BackupService = NoopBackup()

    /// Действие хозяина. Его зовут кнопки экрана, виджет, остров, контрол, «Команды», уведомления и шаги.
    func perform(_ a: PetAction, source: ActionSource) async -> ActOutcome {
        let now = Clock.now()
        // Снимок до действия: из приложения показываем «+N» по шкалам.
        let before: SaveFile? = source == .app ? (try? PetStore.shared.read()) : nil
        let out: ActOutcome
        do {
            out = try PetRunner.perform(a, source: source, now: now)
        } catch {
            out = .storeFailed
        }
        let model = AppModel.shared
        model.refresh(now: now)
        if source == .app {
            var delta: [String: Int] = [:]
            if out.ok, let before, let after = model.file {
                delta = Self.delta(PetRunner.peek(before, at: now), PetRunner.peek(after, at: now))
            }
            model.settle(a, out, delta: delta)
        }
        // Откат ласки из приложения (волна 18): раньше молча — и хозяин не понимал, почему «не гладится».
        // Теперь один тост на окно отката с минутами (Coach.petRefused), дальше тихо: бейдж на кнопке и так виден.
        let quiet = source == .app && a == .pet && out.reason == "cooldown"
        if quiet { Coach.shared.petRefused(model) }
        if !out.ok && source != .steps && !quiet {
            model.show(Self.refusal(a, out, file: model.file, at: now, name: model.snap.name), ok: false)
        }
        await afterChange()
        // Разрешение на уведомления спрашиваем не на старте, а после первой удачной кормёжки.
        if out.ok, case .feed = a, source == .app {
            await NotificationScheduler.requestOnce()
            GuideCenter.shared.fedOK()
        }
        return out
    }

    /// Текст отказа. Прогулка «не готов» (волна 20) — тот же тост, что у кнопки «Гулять»: какая шкала держит и её
    /// число («Для прогулки сначала покормить: сытость 25, нужно 30»), а не общее «покорми и почисти».
    static func refusal(_ a: PetAction, _ out: ActOutcome, file: SaveFile?, at t: Double, name: String) -> String {
        if a == .walk, out.reason == "not_ready", let f = file {
            let g = WalkPlan.gate(f, at: t)
            if g.reason == "not_ready", !g.toast.isEmpty { return g.toast }
        }
        return RefuseText.text(out.reason, name: name)
    }

    /// Привычка из «Команд» или с экрана «Привычки»: отметка и монеты (Habits.checkIn). Приложение открыто —
    /// пёс радуется (реакция habit) и тост с его фразой; Siri ту же фразу говорит сама (Intents.swift).
    @discardableResult
    func habit(_ h: Habit, times: Int = 1, source: ActionSource) async -> HabitOutcome {
        let now = Clock.now()
        let out: HabitOutcome
        do {
            out = try PetStore.shared.mutate { Habits.checkIn(h, times: times, in: &$0, now: now) }
        } catch {
            out = Habits.failed(h)
        }
        let model = AppModel.shared
        model.refresh(now: now)
        if out.ok {
            model.react(Habits.reactKind)
            Feel.success(source == .app ? .ok : nil)
        } else if source == .app {
            // «Сегодня уже отмечено» — дружелюбный тост, не отказ: мягкий щелчок без «не-а» (волна 29).
            if out.reason == Habits.enoughReason { Feel.nudge() } else { Feel.denied() }
        }
        model.show(Habits.reply(out), ok: out.ok || out.reason == Habits.enoughReason, emoji: out.ok ? "🐾" : nil)
        await afterChange()
        return out
    }

    /// Изменение видимых шкал в целых, без нулей: ["food": 12, "love": 8].
    static func delta(_ a: PetState, _ b: PetState) -> [String: Int] {
        var d: [String: Int] = [:]
        for n in VisibleNeeds.all {
            let v = Int(((b.needs[n] ?? 0) - (a.needs[n] ?? 0)).rounded())
            if v != 0 { d[n.rawValue] = v }
        }
        return d
    }

    /// Остров включён/выключен (контрол, «Команды», настройки).
    func setIsland(enabled: Bool) async {
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in
            f.island.enabled = enabled
            if !enabled {
                f.island.startedT = nil
                f.island.activityId = nil
            }
        }
        AppModel.shared.refresh()
        if enabled {
            await LiveActivityController.sync(PetStore.load(), allowStart: true, force: true)
        } else {
            await LiveActivityController.endAll()
        }
    }

    /// Стейт изменился: перерисовать всё, что показывает питомца вне приложения.
    func afterChange() async {
        WidgetCenter.shared.reloadAllTimelines()
        // Волна 51: контрол «Шиба сейчас» в Пункте управления — пересчитать подпись.
        ControlCenter.shared.reloadAllControls()
        let f = PetStore.load()
        await LiveActivityController.sync(f, allowStart: false)
        await NotificationScheduler.reschedule()
        await backup.backup(f)
    }

    /// Приложение открыли: остров (если включён и его нет — запустить), уведомления, шаги.
    func afterActivation() async {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        await LiveActivityController.sync(PetStore.load(), allowStart: true)
        await NotificationScheduler.reschedule()
        await syncSteps()
    }

    /// Ушли в фон: уведомления по свежему lastSeenT (от него считается «скучаю»).
    func afterBackground() async {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        await LiveActivityController.sync(PetStore.load(), allowStart: false)
        await NotificationScheduler.reschedule()
    }

    /// Шаги с прошлого засчитанного раза (но не раньше начала дня) — одно действие steps.
    /// Волна 23: вход в приложение бывает два раза подряд (.active → .inactive → .active под шторкой), и два
    /// syncSteps читали одну метку lastStepsT, пока ждали шагомер, — шаги засчитывались дважды. Теперь один
    /// за раз, а после ожидания метку перечитываем: кто-то успел засчитать — молчим.
    private var stepsBusy = false

    func syncSteps() async {
        guard !Env.isUnitTest, !stepsBusy else { return }
        stepsBusy = true
        defer { stepsBusy = false }
        let f = PetStore.load()
        guard f.pet.alive else { await syncRunawaySteps(f); return }
        let now = Clock.now()
        let dayStart = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: now)).timeIntervalSince1970
        guard let from = PetRunner.stepsFrom(lastStepsT: f.lastStepsT, createdT: f.createdT,
                                             dayStart: dayStart, now: now) else { return }
        // Шагомер живёт в настоящем времени, стор — в часах приложения (PET_NOW в тестах).
        let realFrom = Date(timeIntervalSince1970: from - Clock.offset)
        let realTo = Date(timeIntervalSince1970: now - Clock.offset)
        guard let n = await StepsSync.count(from: realFrom, to: realTo), n >= StepsSync.minSteps else { return }
        guard PetStore.load().lastStepsT == f.lastStepsT else { return }
        _ = await perform(.steps(n), source: .steps)
    }

    /// Волна 32: пёс убежал — шаги хозяина идут в поиски (Runaway.addSteps), монет за них нет.
    private func syncRunawaySteps(_ f: SaveFile) async {
        let now = Clock.now()
        guard let from = Runaway.stepsFrom(f, at: now) else { return }
        let realFrom = Date(timeIntervalSince1970: from - Clock.offset)
        let realTo = Date(timeIntervalSince1970: now - Clock.offset)
        guard let n = await StepsSync.count(from: realFrom, to: realTo), n >= StepsSync.minSteps else { return }
        // Пока ждали шагомер, другой заход мог уже засчитать это окно — тогда молчим.
        let mark = f.runaway.stepsT
        let outcome = try? PetStore.shared.mutate { (g: inout SaveFile) -> Runaway.Outcome? in
            guard g.runaway.stepsT == mark else { return nil }
            return Runaway.addSteps(n, &g, now: now)
        }
        guard let outcome = outcome ?? nil else { return }
        AppModel.shared.refresh()
        if outcome == .found {
            AppModel.shared.show(Runaway.toast(.found), emoji: "🐾")
            Feel.success()
        }
        await afterChange()
    }
}
