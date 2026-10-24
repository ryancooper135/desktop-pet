// Волна 11: «Лавка дня» — лист из автомата с капсулами. Три карточки витрины (ShopDaily, Shared/ShopDaily.swift):
// иконка, имя, редкость, что с вещью делать и цена в монетах. Только монеты — реальных денег в игре нет.
// Открыли лист — витрина суток закрепляется в сейве (model.openShop), завтра другая.
// Решения (Вадим может поменять): без монет кнопка не гаснет — пишет «Не хватает N», нажатие объясняет отказ;
// купленное остаётся на витрине до полуночи с пометкой «Куплено».

import SwiftUI
@preconcurrency import PetCore

struct ShopSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var refusal: String?

    var body: some View {
        let now = Clock.now()
        let offers = model.file.map { ShopDaily.offers($0, now: now) } ?? []
        ScrollView {
            VStack(spacing: 14) {
                header
                ForEach(offers) { card($0) }
                if let refusal {
                    Text(refusal)
                        .petFont(14, .semibold)
                        .foregroundStyle(PetPalette.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                        .accessibilityIdentifier("shop.refusal")
                }
                Text("Только за монеты. Легендарное бывает лишь в капсулах.")
                    .petFont(12, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .animation(.snappy, value: refusal)
        .onAppear { model.openShop() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shop.screen")
    }

    // MARK: части

    private var header: some View {
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
                        .modifier(HitPad())
                }
                .buttonStyle(SquishStyle())
                .padding(-HitPad.pad)
                .accessibilityLabel(Text("Закрыть"))
                .accessibilityIdentifier("shop.close")
            }
            Text("🛍 Лавка дня")
                .petFont(22, .bold)
                .foregroundStyle(PetPalette.ink)
                .accessibilityLabel(Text("Лавка дня"))
                .accessibilityAddTraits(.isHeader)
            if let w = model.file?.econ.wallet {
                Text("🪙 \(w.coins)")
                    .petFont(15, .semibold)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text(EconText.coins(w.coins)))
                    .accessibilityIdentifier("shop.wallet")
            }
            // Отсчёт до новой витрины — раз в минуту, точнее не нужно.
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                Text("Новая витрина через \(Self.left(ShopDaily.secondsToNext(now: ctx.date.timeIntervalSince1970)))")
                    .petFont(13, .medium)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
            }
            .accessibilityIdentifier("shop.next")
        }
    }

    /// «5 ч 12 мин» / «12 мин».
    static func left(_ s: Double) -> String {
        let m = max(1, Int((s / 60).rounded(.up)))
        return m >= 60 ? "\(m / 60) ч \(m % 60) мин" : "\(m) мин"
    }

    /// Куда пойдёт вещь — теми же словами, что в коллекции (CapsuleScreen.use): «на шею», «на полку в комнате».
    /// Раньше лавка писала «надеть»/«на полку», а коллекция — место, и одна вещь звалась по-разному.
    static func roleNote(_ o: ShopOffer) -> String? {
        switch o.role {
        case .wear: return Wear.info(o.id)?.slot.place ?? ItemRole.wear.title
        case .decor: return "на полку в комнате"
        case .toy: return "мячик для «Поиграть»"
        case nil: return nil
        }
    }

    private func card(_ o: ShopOffer) -> some View {
        let done = o.state == .sold || o.state == .owned
        return AXRow {
            HStack(spacing: 12) {
                ItemTile(id: o.id, rarity: o.item.rarity, size: 64)
                    .opacity(done ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.item.name)
                        .petFont(16, .semibold)
                        .foregroundStyle(PetPalette.ink)
                        .axLines(2)
                        .minimumScaleFactor(0.8)
                    Text(EconText.rarityName(o.item.rarity))
                        .petFont(12, .bold)
                        .foregroundStyle(rarityColor(o.item.rarity))
                    if let note = Self.roleNote(o) {
                        Text(note)
                            .petFont(12, .medium)
                            .foregroundStyle(PetPalette.soft)
                    }
                    // Волна 32: маленькая польза вещи одной строкой.
                    if let perk = ItemPerks.line(o.id) {
                        Text(perk)
                            .petFont(12, .medium)
                            .foregroundStyle(PetPalette.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("🪙 \(o.price)")
                        .petFont(14, .heavy)
                        .monospacedDigit()
                        .foregroundStyle(done ? PetPalette.soft : PetPalette.ink)
                        .strikethrough(o.state == .sold)
                        .accessibilityLabel(Text(EconText.coins(o.price)))
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("shop.offer.\(o.id)")
            buyButton(o)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
    }

    /// «Купить» — залитая акцентом; «Не хватает N» — обводка; «Куплено / Уже есть» — серая надпись.
    private func buyButton(_ o: ShopOffer) -> some View {
        let canBuy: Bool = { if case .buy(let need) = o.state { return need == 0 } else { return false } }()
        let done = o.state == .sold || o.state == .owned
        return Button {
            guard !done else { return }
            if let r = model.buyShop(o.id) { refusal = ShopDaily.refusal(r) }
        } label: {
            Text(ShopDaily.buttonTitle(o))
                .petFont(13, .bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(canBuy ? Color.white : (done ? PetPalette.soft : PetPalette.accent))
                .padding(.horizontal, 12)
                .frame(minWidth: 88, minHeight: 36)
                .background {
                    if canBuy {
                        Capsule().fill(PetPalette.accent)
                    } else if !done {
                        Capsule().strokeBorder(PetPalette.accent, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(SquishStyle())
        .disabled(done)
        .deniedTap(when: done)
        .accessibilityLabel(Text(done ? ShopDaily.buttonTitle(o) : "Купить «\(o.item.name)» за \(EconText.coins(o.price))"))
        .accessibilityIdentifier("shop.buy.\(o.id)")
    }
}
