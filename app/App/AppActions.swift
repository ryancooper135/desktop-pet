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
        // Кулдаун ласки из приложения уже виден анимацией и иконкой — без тоста.
        let quiet = source == .app && a == .pet && out.reason == "cooldown"
        if !out.ok && source != .steps && !quiet {
            model.show(RefuseText.text(out.reason), ok: false)
        }
        await afterChange()
        // Разрешение на уведомления спрашиваем не на старте, а после первой удачной кормёжки.
        if out.ok, case .feed = a, source == .app {
            await NotificationScheduler.requestOnce()
        }
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
        let f = PetStore.load()
        await LiveActivityController.sync(f, allowStart: false)
        await NotificationScheduler.reschedule()
        await backup.backup(f)
    }

    /// Приложение открыли: остров (если включён и его нет — запустить), уведомления, шаги.
    func afterActivation() async {
        WidgetCenter.shared.reloadAllTimelines()
        await LiveActivityController.sync(PetStore.load(), allowStart: true)
        await NotificationScheduler.reschedule()
        await syncSteps()
    }

    /// Ушли в фон: уведомления по свежему lastSeenT (от него считается «скучаю»).
    func afterBackground() async {
        WidgetCenter.shared.reloadAllTimelines()
        await NotificationScheduler.reschedule()
    }

    /// Шаги с прошлого засчитанного раза (но не раньше начала дня) — одно действие steps.
    func syncSteps() async {
        guard !Env.isUnitTest else { return }
        let f = PetStore.load()
        guard f.pet.alive else { return }
        let now = Clock.now()
        let dayStart = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: now)).timeIntervalSince1970
        let from = Swift.max(dayStart, f.lastStepsT ?? f.createdT)
        guard now - from >= 15 * 60 else { return }
        // Шагомер живёт в настоящем времени, стор — в часах приложения (PET_NOW в тестах).
        let realFrom = Date(timeIntervalSince1970: from - Clock.offset)
        let realTo = Date(timeIntervalSince1970: now - Clock.offset)
        guard let n = await StepsSync.count(from: realFrom, to: realTo), n >= StepsSync.minSteps else { return }
        _ = await perform(.steps(n), source: .steps)
    }
}
