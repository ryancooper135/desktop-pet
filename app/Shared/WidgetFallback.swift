// Волна 59: виджет и контрол без сохранения.
// Так бывает при первом запуске (щенка ещё нет) и под чужой подписью (SideStore, свой Apple ID у друга),
// если общая папка (App Group) не подключилась: тогда у расширения своя пустая папка, а сейв у приложения.
// Раньше виджет рисовал выдуманного свежего щенка (PetStore.load() → SaveFile.fresh); теперь — заглушка.

import Foundation

enum WidgetFallback {
    static let openAppCaption = "Открой приложение"
    static let noLinkCaption = "Нет связи с игрой"

    /// Подпись заглушки: папка общая — просто ещё нет щенка; не общая — виджет его и не увидит.
    static func caption(shared: Bool) -> String { shared ? openAppCaption : noLinkCaption }

    /// Кадры виджета: есть сейв — как всегда; нет — один кадр-заглушка.
    static func looks(_ file: SaveFile?, now: Double, shared: Bool = Paths.isShared) -> [WidgetLook] {
        guard let file else { return [placeholder(t: now, shared: shared)] }
        return WidgetLook.looks(file, now: now)
    }

    /// Сидящий пёс без шкал, копилки и кнопок — ничего не выдумываем.
    static func placeholder(t: Double, shared: Bool) -> WidgetLook {
        WidgetLook(t: t, pose: .sit, alive: true, caption: caption(shared: shared), main: nil, bars: [], ring: nil,
                   coins: nil, coinsFull: nil, bankLine: nil, bankFull: false, tripFrom: nil, tripUntil: nil,
                   sky: .day, tier: 0, tierName: "", lock: .pose, dogScale: 1, status: status(shared: shared))
    }

    /// Статус для контрола «Шиба сейчас»: без действия, кнопка откроет приложение.
    static func status(shared: Bool) -> PetStatus {
        PetStatus(kind: .fine, title: caption(shared: shared), detail: nil, timerFrom: nil, timerEnd: nil,
                  progress: nil, need: nil, act: nil, symbol: "pawprint", pose: .sit)
    }

    /// Статус контрола: есть сейв — по логике; нет — заглушка.
    static func status(_ file: SaveFile?, now: Double, shared: Bool = Paths.isShared) -> PetStatus {
        guard let file else { return status(shared: shared) }
        return PetStatusLogic.of(file, now: now)
    }
}
