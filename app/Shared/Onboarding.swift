// Волна 19, «понятность»: знакомство при первом запуске (три карточки, можно пропустить) и мелкие пояснения —
// что за значки в ряду над панелью, что за 🪙/🎟/✂️, чем помочь шерсти. Здесь только решения и текст, без UI:
// всё проверяется в ClarityTests. Экран — App/IntroScreen.swift, показывает GuideCenter (GuideKind.intro).

import Foundation
@preconcurrency import PetCore

/// Строчка карточки знакомства: значок SF Symbols (или эмодзи), подпись и пояснение.
struct IntroRow: Identifiable, Hashable, Sendable {
    let id: String
    /// Имя SF Symbols; пусто — вместо значка эмодзи.
    let icon: String
    let emoji: String
    let title: String
    let text: String

    init(_ id: String, icon: String = "", emoji: String = "", _ title: String, _ text: String) {
        self.id = id; self.icon = icon; self.emoji = emoji; self.title = title; self.text = text
    }
}

/// Карточка знакомства: заголовок, короткий текст и строчки-пояснения.
struct IntroPage: Identifiable, Hashable, Sendable {
    let id: String
    let icon: String
    let title: String
    let text: String
    let rows: [IntroRow]
}

enum Onboarding {
    // MARK: настройки (вкус — за Вадимом)

    /// Ключ в TipLog.seen: знакомство уже показано. Живёт в tips — переживает «Начать заново».
    static let introKey = "intro"
    /// Больше трёх карточек не делаем: длинное знакомство не читают.
    static let maxPages = 3

    // MARK: когда показывать

    /// Знакомство показываем один раз — и новичку, и тому, кто играл до волны 19 (ряд значков без подписей
    /// непонятен всем). Мёртвому щенку не показываем: там своя кнопка «Начать заново».
    static func shouldShowIntro(tips: TipLog, alive: Bool) -> Bool {
        alive && !tips.seen.contains(introKey)
    }

    // MARK: текст

    /// Три карточки: кто это и как с ним быть, уход, что где в ряду над панелью. name — имя питомца.
    static func pages(name: String) -> [IntroPage] {
        [
            IntroPage(id: "hello", icon: "pawprint.fill", title: "Знакомься: \(name)",
                      text: "Он живёт по твоим часам: ест, пачкается, скучает и спит, даже когда приложение закрыто. Загляни пару раз в день — этого хватит.",
                      rows: [
                        IntroRow("stroke", icon: "hand.draw.fill", "Погладь пальцем", "Веди по спине — ему приятно."),
                        IntroRow("tap", icon: "hand.tap.fill", "Тапни", "\(name) обернётся и ответит."),
                        IntroRow("night", icon: "moon.fill", "Ночью он спит", "Пока ты спишь, беды не копятся."),
                      ]),
            IntroPage(id: "care", icon: "heart.fill", title: "Как ухаживать",
                      text: "Внизу четыре кнопки ухода. Цветная — можно нажать, серая — пока нельзя, и на ней написано почему. С чего начать, подскажет плашка.",
                      rows: [
                        IntroRow("feed", icon: "fork.knife", "Покормить", "Хрустики бесплатно, сколько надо."),
                        IntroRow("pet", icon: "hand.raised.fill", "Погладить", "Когда скучает по тебе."),
                        IntroRow("play", icon: "tennisball.fill", "Поиграть", "Когда скучно. Спящий не играет."),
                        IntroRow("bath", icon: "bathtub.fill", "Помыть", "Когда испачкался."),
                        IntroRow("needs", icon: "chevron.up", "Шкалы", "Потяни ручку вверх — увидишь, как он."),
                      ]),
            IntroPage(id: "row", icon: "square.grid.2x2.fill", title: "Что где",
                      text: "Над кнопками ухода — ряд кружков. Вот что в них.",
                      rows: rowLegend + [
                        IntroRow("money", emoji: "🪙", "Монеты и 🎟 билетики", "Монеты — за уход и игры, билетик — одна крутка автомата."),
                      ]),
        ]
    }

    /// Значки ряда «Альбом · Автомат · Дом · Трюки · Игры · Гулять» — те же имена SF Symbols, что в WalkViews.
    static let rowLegend: [IntroRow] = [
        IntroRow("album", icon: "books.vertical.fill", "Альбом", "Находки с прогулок, открытки, характер."),
        IntroRow("capsule", icon: "gift.fill", "Автомат", "Капсулы с вещами и Лавка дня."),
        IntroRow("house", icon: "house.fill", "Дом", "Улучшения за монеты и кухня."),
        IntroRow("tricks", icon: "pawprint.fill", "Трюки", "Команды и расчёска."),
        IntroRow("games", icon: "gamecontroller.fill", "Мини-игры", "Три игры, за них монеты."),
        IntroRow("walk", icon: "figure.walk", "Гулять", "Уходит на 1–3 часа и приносит находку."),
    ]

    // MARK: пояснения на экранах

    /// Строчка под кошельком в автомате: что за три значка. Неразрывные пробелы — значок не отрывается от слова.
    static let walletLegend = "🪙\u{00A0}монеты — за уход и игры\u{00A0}· 🎟\u{00A0}билетик — одна крутка\u{00A0}· ✂️\u{00A0}клочки — с повторок"

    /// Строчка шерсти в шкалах: «Шерсть: колтуны — расчеши в «Трюках»». Хорошая шерсть — без совета.
    static func coatLine(_ stage: CoatStage) -> String {
        let base = "Шерсть: \(stage.title.lowercased())"
        switch stage {
        case .matted, .shaggy: return base + " — расчеши в «Трюках»"
        case .normal, .sleek: return base
        }
    }
}
