// Волна 41 G: интерьер — обои, пол и ковёр (лист InteriorSheet из «Дома»).
// Логика — Shared/Interior.swift; здесь только запись в стор, тосты и отклик. Косметика: доход не трогает.

import Foundation
@preconcurrency import PetCore

extension AppModel {
    /// Купить вариант и сразу поставить. Вернёт текст отказа для строки листа; nil — купили
    /// (тост покажет модель) или стор не записался (тогда уже показан отказ стора).
    func buyInterior(_ id: String) -> String? {
        let r: Result<InteriorStyle, InteriorRefusal>
        do {
            r = try Interior.perform(buy: id)
        } catch {
            refuse(RefuseText.text("store"))
            return nil
        }
        switch r {
        case .failure(let why):
            Feel.denied()
            return InteriorText.refusal(why)
        case .success(let st):
            refresh()
            Feel.success(st.isExclusive ? .hearts : .ok)
            show(InteriorText.ui("interior_bought", ["item": st.name]), emoji: st.isExclusive ? "✂️" : "🏠")
            Task { await AppActions.shared.afterChange() }
            return nil
        }
    }

    /// Поставить своё (купленное или бесплатное). Вернёт текст отказа; nil — поставили.
    func chooseInterior(_ id: String) -> String? {
        let r: Result<InteriorStyle, InteriorRefusal>
        do {
            r = try Interior.perform(choose: id)
        } catch {
            refuse(RefuseText.text("store"))
            return nil
        }
        switch r {
        case .failure(let why):
            Feel.denied()
            return InteriorText.refusal(why)
        case .success:
            refresh()
            Feel.success(.ok)
            Task { await AppActions.shared.afterChange() }
            return nil
        }
    }
}
