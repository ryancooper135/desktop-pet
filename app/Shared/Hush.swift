// Волна 22: «одно сообщение за раз». На главном экране есть короткоживущие голоса — тост над кнопками,
// разовая подсказка жеста (tip.gesture), палец-учитель «Проведи пальцем по Шибе» (tip.pet). Раньше каждый
// показывался сам по себе, и после ласки кнопкой висели два тоста подряд (ui-94-10), а палец ходил по жующему псу.
// Здесь чистое правило, кто говорит: старший голос перекрывает младших, младший ждёт или выбрасывается за давностью.
// Плашка «что нужно сейчас» — не голос, а постоянная кнопка: она не прячется, но её подпись уступает пальцу.
// Решения — DECISIONS.md, «Волна 22: одно сообщение за раз». Только Foundation: гоняется на Linux.

import Foundation

enum Hush {
    /// Кто говорит. Больше rawValue — главнее.
    enum Voice: Int, Comparable, CaseIterable, Sendable {
        /// Палец по Шибе — учит, но подождёт.
        case tutor
        /// Разовая подсказка жеста (щекотка, свайп).
        case tip
        /// Тост — ответ на то, что хозяин только что сделал.
        case toast

        static func < (a: Voice, b: Voice) -> Bool { a.rawValue < b.rawValue }
    }

    /// Кто из желающих говорит сейчас: один, самый главный.
    static func speaker(_ wanting: Set<Voice>) -> Voice? { wanting.max() }

    // MARK: подсказка жеста

    /// Подсказка жеста ждёт тишины не дольше этого: потом она уже не про только что сделанную ласку.
    static let tipStaleS: Double = 20
    /// Как часто ждущая подсказка проверяет, не стало ли тихо.
    static let tipPollS: Double = 0.5

    enum TipStep: Equatable, Sendable { case show, wait, drop }

    /// Что делать с предложенной подсказкой жеста в момент now.
    /// offeredAt — когда её пора было показать; toastUp — тост на экране; sceneClear — нет листов и сна/прогулки.
    static func tipStep(offeredAt: Double, now: Double, toastUp: Bool, sceneClear: Bool) -> TipStep {
        if now - offeredAt > tipStaleS { return .drop }
        if toastUp || !sceneClear { return .wait }
        return .show
    }

    /// Видна ли подсказка жеста, что уже показана: пока говорит тост, она молчит (таймер её идёт дальше).
    static func tipVisible(hasTip: Bool, toastUp: Bool) -> Bool {
        hasTip && speaker(toastUp ? [.tip, .toast] : [.tip]) == .tip
    }

    // MARK: палец-учитель

    /// Сколько секунд после удачного действия пёс «занят» (ест, радуется, бежит за мячом). = AppModel.reactionWindow.
    static let busyS: Double = 12
    /// Позы, в которых пальцем по Шибе не водят: он ест, моется, ушёл, спит.
    static let busyPoses: Set<Pose> = [.eating, .bath, .away, .sleep, .nap]
    /// Действия, после которых идёт анимация (PetEngine.actionType и кухня Cooking.reactKind). Шаги — фоновые, не в счёт.
    static let busyKinds: Set<String> = ["feed", "item", "cook", "pet", "play", "wake", "bath", "walk", "brush"]

    /// Идёт ли сейчас анимация действия: поза занятости или свежее удачное действие.
    static func busy(pose: Pose, lastAction: SaveFile.LastAction?, now: Double) -> Bool {
        if busyPoses.contains(pose) { return true }
        guard let la = lastAction, la.ok, busyKinds.contains(la.kind) else { return false }
        let age = now - la.t
        return age >= 0 && age < busyS
    }

    /// Показывать ли палец. wants — Coach.showTutor (новичок, просит, тап по плашке); forced — по тапу хозяина.
    /// Пока пёс занят действием — прячется (вернётся сам, когда анимация кончится), кроме тапа: хозяин сам попросил.
    /// Тост и подсказка жеста главнее пальца всегда.
    static func tutorVisible(wants: Bool, forced: Bool, busy: Bool, toastUp: Bool, tipUp: Bool) -> Bool {
        guard wants, forced || !busy else { return false }
        var voices: Set<Voice> = [.tutor]
        if toastUp { voices.insert(.toast) }
        if tipUp { voices.insert(.tip) }
        return speaker(voices) == .tutor
    }

    // MARK: плашка

    /// Подпись плашки под заголовком. Когда палец на экране говорит «Проведи пальцем по Шибе», плашка про ласку
    /// показывает только заголовок — одна фраза не звучит дважды.
    static func plateDetail(_ hint: NeedHint, tutorShown: Bool, tutorText: String) -> String? {
        if tutorShown, hint.go == .pet || hint.detail == tutorText { return nil }
        return hint.detail.isEmpty ? nil : hint.detail
    }
}
