// Пункт управления (iOS 18+): включить остров и «Шиба сейчас», не открывая приложение.
// Волна 51: второй контрол — динамический (DECISIONS.md, «Волна 51: контрол»). Подпись — PetStatusLogic на момент
// открытия Пункта управления: «Моется · ещё 3 мин», «Спит · до 07:30», «Хочет есть · Сытость 18 %».
// Кнопка — действие статуса, только если ядро его примет (покормить, помыть…); иначе — открыть приложение.
// Живого таймера у контрола нет: значение пересчитывает система и ControlCenter.reloadAllControls (после действий).
// kind прежний ("pet.control.feed"): уже добавленный контрол не пропадает из Пункта управления.

import AppIntents
import SwiftUI
import WidgetKit

struct PetIslandControl: ControlWidget {
    static let kind = "pet.control.island"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartIslandIntent(.control)) {
                Label("Шиба на острове", systemImage: "pawprint.fill")
            }
        }
        .displayName("Шиба в острове")
        .description("Показать Шибу в Dynamic Island.")
    }
}

/// Что сейчас с псом — из сейва на «сейчас».
struct PetStatusControlProvider: ControlValueProvider {
    var previewValue: PetStatus { .fine }

    func currentValue() async throws -> PetStatus {
        PetStatusLogic.of(PetStore.load(), now: Clock.now())
    }
}

struct PetFeedControl: ControlWidget {
    static let kind = "pet.control.feed"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: PetStatusControlProvider()) { st in
            if let a = st.act, a.action != nil {
                // «Покормить» и т. п.: нажатие — действие без открытия приложения.
                ControlWidgetButton(action: IslandActIntent(a, .control)) {
                    Label {
                        Text(st.title)
                        Text(a.title)
                    } icon: {
                        Image(systemName: a.icon)
                    }
                }
            } else {
                // Занят или всё хорошо: состояние в подписи, нажатие открывает Шибу.
                ControlWidgetButton(action: OpenShibaIntent()) {
                    Label {
                        Text(st.title)
                        Text(st.detail ?? "Открыть")
                    } icon: {
                        Image(systemName: st.symbol)
                    }
                }
            }
        }
        .displayName("Шиба сейчас")
        .description("Что делает Шиба и что ему нужно.")
    }
}
