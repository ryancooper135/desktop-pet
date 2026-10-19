// Волна 12: лист «Кухня» поверх «Дома» (кнопка в карточке кухни, pet://kitchen). Логика — Cooking (Shared/Cooking.swift),
// тут только вид. Сверху запас кухни, ниже «Приготовить» (блюда кухни шефа) и «Угостить» (еда за монеты со скидкой
// дома: старая цена зачёркнута, рядом новая и плашка «−10%»).
// Решения (Вадим может поменять): без кухни шефа «Приготовить» показывает блюда бледно и пишет, что нужна L3;
// «Угостить» работает на любой кухне, скидка — только где бафф. Нельзя (откат, мало запаса, нет монет) — кнопка
// не гаснет, нажатие объясняет отказ строкой под карточкой. Вышло — листы закрываются, пёс ест в комнате.

import SwiftUI
@preconcurrency import PetCore

struct KitchenSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Строка под карточкой: почему нельзя. id — рецепт или еда.
    struct Note: Equatable {
        let id: String
        let text: String
    }

    @State private var note: Note?
    @State private var noteTask: Task<Void, Never>?
    @State private var shakes: [String: Int] = [:]

    var body: some View {
        let now = Clock.now()
        let cfg = CookConfig.shared
        ScrollView {
            VStack(spacing: 14) {
                header(now)
                if let f = model.file {
                    let s = PetRunner.peek(f, at: now)
                    section("Приготовить", Cooking.canCook(s) ? Cooking.statusText(f, now: now, cfg)
                                                              : "Готовить можно на «Кухне шефа» — третий уровень кухни")
                    ForEach(cfg.recipes) { recipeCard($0, f, now: now, cfg) }
                    section("Угостить", Cooking.discountText(Cooking.priceX(s))
                        .map { "Кухня шефа: \($0) на всю еду" } ?? "Купить и сразу дать")
                    ForEach(cfg.foods) { foodCard($0, f, now: now) }
                }
                Text("«Покормить» хрустиками — бесплатно, как всегда.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .animation(.snappy, value: note)
        .onDisappear { noteTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kitchen.screen")
    }

    // MARK: части

    private func header(_ now: Double) -> some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PetPalette.soft)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(PetPalette.card))
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel(Text("Закрыть"))
                .accessibilityIdentifier("kitchen.close")
            }
            Text("🍳 Кухня")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
            if let f = model.file {
                Text("🪙 \(f.econ.wallet.coins)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text(EconText.coins(f.econ.wallet.coins)))
                    .accessibilityIdentifier("kitchen.wallet")
                let s = PetRunner.peek(f, at: now)
                let cap = Cooking.pantryCap(s)
                Text("Запас на кухне: \(Int(s.pantry.rounded(.down))) из \(cap)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
                    .accessibilityIdentifier("kitchen.pantry")
            }
        }
    }

    private func section(_ title: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
            if let sub {
                Text(sub)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: приготовить

    private func recipeCard(_ r: CookRecipe, _ f: SaveFile, now: Double, _ cfg: CookConfig) -> some View {
        let st = Cooking.state(r, f, now: now, cfg)
        let ready = st == .ready
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(r.emoji)
                    .font(.system(size: 30))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(PetPalette.accent.opacity(0.14)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    Text(Cooking.gainsText(r))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.green)
                    Text(Cooking.stateText(st, r, now: now, cfg, name: model.snap.name) ?? "Из запаса кухни: \(Int(r.pantry))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(ready ? PetPalette.soft : PetPalette.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Button {
                    cook(r)
                } label: {
                    Text("Приготовить")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(ready ? Color.white : PetPalette.accent)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 88, minHeight: 36)
                        .background {
                            if ready {
                                Capsule().fill(PetPalette.accent)
                            } else {
                                Capsule().strokeBorder(PetPalette.accent.opacity(0.6), lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel(Text("Приготовить «\(r.name)»"))
                .accessibilityIdentifier("kitchen.cook.\(r.id)")
            }
            noteLine(r.id)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
        .opacity(Cooking.canCook(PetRunner.peek(f, at: now)) ? 1 : 0.6)
        .modifier(Wiggle(shake: shakes[r.id, default: 0]))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kitchen.recipe.\(r.id)")
    }

    private func cook(_ r: CookRecipe) {
        model.haptic(.light)
        guard let out = model.cook(r.id), !out.ok else { return }
        refuse(r.id, out.text)
    }

    // MARK: угостить

    private func foodCard(_ food: FoodPrice, _ f: SaveFile, now: Double) -> some View {
        let x = Cooking.priceX(PetRunner.peek(f, at: now))
        let p = Cooking.price(food.price, x: x)
        let can = Economy.canAfford(f, coins: p)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(Tastes.emoji(.food, food.id))
                    .font(.system(size: 28))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(PetPalette.accent.opacity(0.14)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    HStack(spacing: 6) {
                        if p != food.price {
                            // Старая цена зачёркнута — видно, что скидка честная.
                            Text("🪙 \(food.price)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .strikethrough(true, color: PetPalette.soft)
                                .foregroundStyle(PetPalette.soft)
                                .accessibilityIdentifier("kitchen.old.\(food.id)")
                        }
                        Text("🪙 \(p)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(PetPalette.ink)
                            .accessibilityIdentifier("kitchen.price.\(food.id)")
                        if p != food.price, let d = Cooking.discountText(x) {
                            Text(d)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(PetPalette.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(PetPalette.green.opacity(0.16)))
                        }
                    }
                    .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Button {
                    buy(food)
                } label: {
                    Text(can ? "Угостить" : "Не хватает \(p - f.econ.wallet.coins)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(can ? Color.white : PetPalette.accent)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 88, minHeight: 36)
                        .background {
                            if can {
                                Capsule().fill(PetPalette.accent)
                            } else {
                                Capsule().strokeBorder(PetPalette.accent, lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel(Text("Угостить: \(food.name) за \(EconText.coins(p))"))
                .accessibilityIdentifier("kitchen.buy.\(food.id)")
            }
            noteLine(food.id)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
        .modifier(Wiggle(shake: shakes[food.id, default: 0]))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kitchen.food.\(food.id)")
    }

    private func buy(_ food: FoodPrice) {
        model.haptic(.light)
        guard let r = model.buyFood(food.id) else { return }
        if case .ok = r { return }
        refuse(food.id, Cooking.buyText(r, name: food.name))
    }

    // MARK: отказ

    @ViewBuilder
    private func noteLine(_ id: String) -> some View {
        if let note, note.id == id {
            Text(note.text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.red)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .transition(.opacity)
                .accessibilityIdentifier("kitchen.note.\(id)")
        }
    }

    private func refuse(_ id: String, _ text: String) {
        shakes[id, default: 0] += 1
        let n = Note(id: id, text: text)
        note = n
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: .seconds(HouseScreen.noteFor))
            if Task.isCancelled { return }
            if note == n { note = nil }
        }
    }
}

/// Качнуть карточку на отказ — как карточку линии в «Доме».
private struct Wiggle: ViewModifier {
    let shake: Int
    private static let steps: [CGFloat] = [0, -6, 6, -3, 0]

    func body(content: Content) -> some View {
        content.phaseAnimator(Self.steps, trigger: shake, content: { view, x in
            view.offset(x: x)
        }, animation: { _ in
            .linear(duration: 0.06)
        })
    }
}
