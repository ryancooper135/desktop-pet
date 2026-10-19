// Кто и когда показывает знакомство, подсказки «Правила» и «Виджет и остров». Решения — в Guides и Onboarding (Shared).
// Знакомство (волна 19) — первым и один раз: засчитывается в момент показа, смахнул — не вернётся (его можно
// открыть снова в настройках).
// Правила считаются прочитанными только по «Понятно»; гайд виджета засчитывается в момент показа.
// В тестах молчит; PET_GUIDE=intro|rules|widget показывает нужную подсказку один раз — для скриншотов.

import Foundation
import Observation
@preconcurrency import WidgetKit
@preconcurrency import PetCore

@MainActor @Observable
final class GuideCenter {
    static let shared = GuideCenter()

    /// Что сейчас на экране (RootView держит .sheet(item:) на этом поле).
    var sheet: GuideKind?

    /// После кормёжки гайд ждёт, пока экран освободится (шкалы, настройки, «Пока тебя не было»).
    @ObservationIgnored private var widgetDue = false
    @ObservationIgnored private var forcedShown = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Когда сработает отложенная проверка: более ранняя не перебивает позднюю (паузу после кормёжки).
    @ObservationIgnored private var dueAt: ContinuousClock.Instant?
    /// В фоне ничего не показываем: иначе подсказка встанет поверх «Пока тебя не было» при возвращении.
    @ObservationIgnored private var active = true

    static let forced: GuideKind? = Env.value("PET_GUIDE").flatMap { GuideKind(rawValue: $0) }

    private init() {}

    /// Проверить, не пора ли что-то показать. Пауза — чтобы не столкнуться с другими экранами при активации.
    func check(after delay: Double = 0.8) {
        guard active, !Env.isTesting || Self.forced != nil else { return }
        let soon = ContinuousClock.now + .seconds(delay)
        let at = dueAt.map { max($0, soon) } ?? soon
        dueAt = at
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(until: at, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.dueAt = nil
            await self?.evaluate()
        }
    }

    /// Приложение снова на экране (scenePhase .active).
    func becameActive() {
        active = true
        check()
    }

    /// Удачная кормёжка в приложении (из AppActions.perform).
    func fedOK() {
        guard !Env.isTesting else { return }
        widgetDue = true
        check(after: Guides.widgetDelayS)
    }

    /// «Понятно» на экране правил.
    func ackRules() {
        if Self.forced == nil {
            _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in f.flags.rulesShown = true }
            AppModel.shared.refresh()
        }
        sheet = nil
    }

    func close() { sheet = nil }

    /// Ушли в фон: подсказку убираем, чтобы по возвращении не мешать «Пока тебя не было» и ссылкам из виджета.
    /// Непрочитанные правила покажутся снова при следующем входе.
    func wentBackground() {
        active = false
        pending?.cancel()
        dueAt = nil
        sheet = nil
    }

    private func screenFree(_ model: AppModel) -> Bool {
        active && sheet == nil && model.away == nil && !model.showNeeds && !model.showSettings && !model.showAlbum && model.storeError == nil
    }

    private func evaluate() async {
        let model = AppModel.shared
        guard screenFree(model) else { return }
        if let forced = Self.forced {
            if !forcedShown { forcedShown = true; sheet = forced }
            return
        }
        guard let f = model.file else { return }
        let now = Clock.now()
        let snap = model.snap

        if Onboarding.shouldShowIntro(tips: f.tips, alive: snap.alive) {
            _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in Tips.markSeen(&f.tips, Onboarding.introKey) }
            model.refresh()
            widgetDue = false
            sheet = .intro
            return
        }

        if Guides.shouldShowRules(flags: f.flags, createdT: f.createdT, now: now, tzOffsetMin: f.owner.tzOffsetMin,
                                  level: snap.level, alive: snap.alive) {
            // Одна подсказка за раз: гайд виджета подождёт следующей кормёжки.
            widgetDue = false
            sheet = .rules
            return
        }

        guard widgetDue else { return }
        let has = await Self.hasWidget()
        guard screenFree(model) else { return }
        widgetDue = false
        let latest = PetStore.load()
        let islandOn = latest.island.enabled && LiveActivityController.systemEnabled
        guard Guides.shouldShowWidgetGuide(flags: latest.flags, now: now, alive: model.snap.alive,
                                           hasWidget: has, islandOn: islandOn) else { return }
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in
            f.flags.widgetHintCount += 1
            f.flags.widgetHintT = now
        }
        model.refresh()
        sheet = .widget
    }

    /// Стоит ли хоть один виджет (на экране «Домой» или блокировки). Ошибка — считаем, что нет.
    nonisolated private static func hasWidget() async -> Bool {
        do {
            let list = try await WidgetCenter.shared.currentConfigurations()
            return !list.isEmpty
        } catch {
            return false
        }
    }
}
