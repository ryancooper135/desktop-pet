// Волна 35 L: стоки клочков ✂️ — золотой шарик в автомате и эксклюзив места на карте.
// Логика — Shared/ScrapSinks.swift; здесь только запись в стор, тосты и отклик.

import Foundation
@preconcurrency import PetCore

extension AppModel {
    /// Крутка золотого шарика. Как pullCapsule: снимок не пересчитываем — экран зовёт refresh,
    /// когда капсула открылась. nil — стор не записался (отказ стора уже показан).
    func goldenBall() -> Result<CapsulePull, SinkRefusal>? {
        do {
            let r = try ScrapSinks.performGolden()
            if case .success = r { Task { await AppActions.shared.afterChange() } }
            return r
        } catch {
            refuse(RefuseText.text("store"))
            return nil
        }
    }

    /// «Купить» эксклюзив места. Отказ — тостом, вещь — тостом «Теперь у тебя …».
    func buyPlaceExclusive(_ placeId: String) {
        let r: Result<CapsuleItem, SinkRefusal>
        do {
            r = try ScrapSinks.performPlace(placeId)
        } catch {
            refuse(RefuseText.text("store"))
            return
        }
        switch r {
        case .failure(let why):
            refuse(ScrapSinks.refusalText(why))
        case .success(let it):
            refresh()
            Feel.success(.hearts)
            show("Теперь у тебя «\(it.name)»", emoji: ScrapSinks.item(it.id)?.emoji ?? "✂️")
            Task { await AppActions.shared.afterChange() }
        }
    }
}
