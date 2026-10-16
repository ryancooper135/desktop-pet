// Локальные уведомления по прогнозу ядра (NotificationPlanner → notificationPlan, тексты из lines.json).
// После каждого изменения стейта план пересчитывается: снимаем все pending с префиксом pet. и ставим заново.
// Разрешение спрашиваем один раз, после первой кормёжки (flags.notifAsked).

import Foundation
@preconcurrency import PetCore
@preconcurrency import UserNotifications

@MainActor
enum NotificationScheduler {
    nonisolated static let feedAction = "pet.feed"
    nonisolated static let petAction = "pet.pet"

    /// Кнопки в уведомлении «просит»: покормить и погладить, не открывая приложение.
    static func registerCategories() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        let feed = UNNotificationAction(identifier: feedAction, title: "Покормить", options: [])
        let pet = UNNotificationAction(identifier: petAction, title: "Погладить", options: [])
        let need = UNNotificationCategory(identifier: "pet.need", actions: [feed, pet], intentIdentifiers: [], options: [])
        let miss = UNNotificationCategory(identifier: "pet.miss", actions: [pet], intentIdentifiers: [], options: [])
        center.setNotificationCategories([need, miss])
    }

    static func requestOnce() async {
        // Под UI-тестами системный запрос закрывал питомца на всех кадрах анимаций.
        guard !Env.isTesting else { return }
        guard !PetStore.load().flags.notifAsked else { return }
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in f.flags.notifAsked = true }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { await reschedule() }
    }

    static func reschedule() async {
        guard !Env.isUnitTest else { return }
        guard await allowed() else { return }
        let now = Clock.now()
        let f = PetStore.load()
        let notes = f.pet.alive ? NotificationPlanner.plan(f, now: now) : NotificationPlanner.buildNotes(f, now: now)
        let scheduled = await install(notes, offset: Clock.offset)
        // Что уже успело уйти — помним, от этого планировщик держит паузу между уведомлениями.
        _ = try? PetStore.shared.mutate { (g: inout SaveFile) -> Void in
            if let sent = g.notif.scheduled.filter({ $0 <= now }).max() {
                g.notif.lastSentT = Swift.max(g.notif.lastSentT ?? 0, sent)
            }
            g.notif.scheduled = scheduled
        }
    }

    // Объекты UserNotifications не Sendable: работаем с ними вне MainActor, наружу — только простые значения.

    nonisolated static func allowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// Снять старый план (все pending с префиксом pet.) и поставить новый. Возвращает поставленные моменты (часы приложения).
    nonisolated static func install(_ notes: [PlannedNote], offset: Double) async -> [Double] {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old = pending.map { $0.identifier }.filter { $0.hasPrefix(NotificationPlanner.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        var scheduled: [Double] = []
        let realNow = Date().timeIntervalSince1970
        for n in notes {
            let fireIn = n.date.timeIntervalSince1970 - offset - realNow
            guard fireIn > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.categoryIdentifier = n.category
            content.threadIdentifier = "pet"
            content.sound = .default
            content.relevanceScore = Double(n.priority) / 6
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: trigger))
                scheduled.append(n.date.timeIntervalSince1970)
            } catch {
                continue
            }
        }
        return scheduled
    }
}

/// Ответы на уведомления. Кнопки выполняются в фоне, тап по самому уведомлению просто открывает приложение.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let id = response.actionIdentifier
        let action: PetAction?
        switch id {
        case NotificationScheduler.feedAction: action = .feed(Catalog.mainFood)
        case NotificationScheduler.petAction: action = .pet
        default: action = nil
        }
        guard let action else { return }
        _ = await AppActions.shared.perform(action, source: .notification)
    }

    /// Пока приложение на экране, уведомления не показываем: питомец и так перед глазами.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }
}
