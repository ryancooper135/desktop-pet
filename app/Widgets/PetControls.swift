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

/// Что сейчас с псом — из сейва на «сейчас». Сейва не видно — «Открой приложение» (волна 59).
struct PetStatusControlProvider: ControlValueProvider {
    var previewValue: PetStatus { .fine }

    func currentValue() async throws -> PetStatus {
        WidgetFallback.status(PetStore.loadIfAny(), now: Clock.now())
    }
}

struct PetFeedControl: ControlWidget {
    static let kind = "pet.control.feed"

    /// Действие на кнопке — только то, что ядро примет сейчас (PetStatusLogic уже проверил); иначе nil.
    static func act(_ st: PetStatus) -> IslandAct? {
        guard let a = st.act, a.action != nil else { return nil }
        return a
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: PetStatusControlProvider()) { st in
            // Шаблон без if/else (ControlWidgetTemplateBuilder): одна кнопка, разница — в данных.
            // Действие доступно — нажатие делает его без открытия приложения; нет — открывает Шибу.
            ControlWidgetButton(action: ShibaNowIntent(Self.act(st) ?? .open)) {
                Label {
                    Text(st.title)
                    Text(Self.act(st)?.title ?? st.detail ?? "Открыть")
                } icon: {
                    Image(systemName: Self.act(st)?.icon ?? st.symbol)
                }
            }
        }
        .displayName("Шиба сейчас")
        .description("Что делает Шиба и что ему нужно.")
    }
}
