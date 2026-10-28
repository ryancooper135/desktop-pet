// Волна 42 J: «Задания дня» — данные для листа (TasksSheet) и замена задания.
// Вся логика в Shared/DailyTasks.swift; здесь только запись в стор и тосты. Тост выполненного задания —
// AppModel.noteTasks (из refresh).

import Foundation
@preconcurrency import PetCore

extension AppModel {
    /// Задания на сейчас (settle на копии, без записи). nil — задания выключены (UI-тесты без сида tasks*).
    var taskBoard: TaskBoard? {
        guard DailyTasks.enabled, let f = file else { return nil }
        let b = DailyTasks.board(f, now: snap.t)
        return b.items.isEmpty ? nil : b
    }

    /// «Заменить» в листе: раз в сутки, бесплатно. Отказ — тост с причиной.
    func swapTask(_ id: String) {
        let now = Clock.now()
        let r: Result<DailyTask, TaskSwapRefusal>
        do {
            r = try DailyTasks.performSwap(id, now: now)
        } catch {
            refuse(RefuseText.text("store"))
            return
        }
        refresh(now: now)
        switch r {
        case .failure(let why):
            refuse(DailyTaskText.swapRefusal(why))
        case .success(let t):
            Feel.success()
            show("Новое задание: \(DailyTaskText.name(t))", emoji: DailyTaskText.emoji(t.id))
            Task { await AppActions.shared.afterChange() }
        }
    }
}
