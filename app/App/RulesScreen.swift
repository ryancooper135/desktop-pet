// Экран «Честно о главном»: как уходят сердечки и когда щенок умирает. Один экран, одна кнопка.
// Показывается на 3-й день или при первом «Плохо» (Guides.shouldShowRules). Цифры — из правил ядра.

import SwiftUI
@preconcurrency import PetCore

struct RulesScreen: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void
    /// Считаем один раз: внутри прогноз «если совсем забыть» на неделю вперёд.
    @State private var items: [RuleItem] = []

    var body: some View {
        let name = model.snap.name
        VStack(spacing: 14) {
            ScrollView {
                VStack(spacing: 16) {
                    PetFaceView(pose: model.snap.alive ? .idle : .dead)
                        .frame(width: 80, height: 80)
                        .padding(.top, 20)
                    VStack(spacing: 4) {
                        Text("Честно о главном")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(PetPalette.ink)
                        Text("Коротко и без сюрпризов")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(PetPalette.soft)
                    }
                    .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(items) { item in
                            RuleRow(item: item)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20).fill(PetPalette.card))
                }
            }
            .scrollIndicators(.hidden)

            Button {
                onDone()
            } label: {
                Text("Понятно, буду беречь").frame(maxWidth: .infinity, minHeight: 50)
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .buttonStyle(.borderedProminent)
            .tint(PetPalette.accent)
            .accessibilityIdentifier("rules.ok")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(PetPalette.bg.ignoresSafeArea())
        // Закрыть можно только кнопкой: так правила точно прочитаны.
        .interactiveDismissDisabled()
        .onAppear {
            guard items.isEmpty else { return }
            let owner = model.file?.owner ?? PetEngine.defaultOwner(Catalog.rules)
            items = Guides.rulesItems(name: name, owner: owner)
        }
    }
}

private struct RuleRow: View {
    let item: RuleItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(item.id == "last" || item.id == "hearts" ? PetPalette.red : PetPalette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                Text(item.text)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
