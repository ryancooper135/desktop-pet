// Волна 35 L: карточка золотого шарика (экран автомата) и кнопка эксклюзива места (карточка места на карте).
// Логика и тексты — Shared/ScrapSinks.swift.

import SwiftUI
@preconcurrency import PetCore

/// «Золотой шарик» под кнопками крутки: 50 ✂️, только редкое и выше, без повторов.
/// Нажимается и без клочков — отказ объяснит экран автомата, как у обычной крутки.
struct GoldenBallCard: View {
    @Environment(AppModel.self) private var model
    let busy: Bool
    let action: () -> Void

    var body: some View {
        let f = model.file
        let shards = f?.econ.wallet.shards ?? 0
        let open = f.map { ScrapSinks.goldenOpen($0) } ?? true
        let price = ScrapSinks.goldenPrice
        let can = open && shards >= price
        let gold = rarityColor(.legendary)
        return Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(gold.gradient)
                    Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2).padding(4)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Золотой шарик")
                        .petFont(16, .bold)
                        .foregroundStyle(PetPalette.ink)
                    Text(f.map { ScrapSinks.goldenNote($0) } ?? "Только редкое и выше, без повторов")
                        .petFont(12, .medium)
                        .foregroundStyle(PetPalette.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("✂️ \(price)")
                    .petFont(14, .heavy)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.ink.opacity(can ? 1 : 0.5))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(gold.opacity(can ? 0.7 : 0.3), lineWidth: 1.5) }
        }
        .buttonStyle(SquishStyle())
        .disabled(busy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Золотой шарик, \(EconText.shards(price))"))
        .accessibilityValue(Text(open ? "У тебя \(EconText.shards(shards))" : "Все редкие вещи уже у тебя"))
        .accessibilityHint(Text("Только редкое и выше, без повторов"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sinks.golden")
    }
}

/// Эксклюзив места на карточке места: одна вещь в стиле места за 120 ✂️, открывается с половиной находок.
/// Без клочков или находок кнопка не гаснет: нажатие объясняет, чего не хватает.
struct PlaceExclusiveButton: View {
    @Environment(AppModel.self) private var model
    let file: SaveFile
    let place: Place

    var body: some View {
        if let it = ScrapSinks.exclusive(place.id), let state = ScrapSinks.placeState(file, place) {
            let shards = file.econ.wallet.shards
            let ready = state == .buy(price: ScrapSinks.placePrice, canAfford: true)
            let owned = state == .owned
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    switch state {
                    case .owned: model.refuse(ScrapSinks.refusalText(.owned))
                    case .locked(let left): model.refuse(ScrapSinks.refusalText(.fewFinds(left: left)))
                    case .buy: model.buyPlaceExclusive(place.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        ItemIcon(id: it.id, size: 26)
                            .accessibilityHidden(true)
                        Text(ScrapSinks.placeButton(state, it))
                            .petFont(16, .bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(PetPalette.ink.opacity(ready || owned ? 1 : 0.55))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .padding(.horizontal, 12)
                    .contentShape(Capsule())
                }
                .buttonStyle(SquishStyle())
                .glassEffect(ready ? .regular.tint(rarityColor(.epic).opacity(0.35)).interactive() : .regular.interactive(),
                             in: Capsule())
                .accessibilityLabel(Text(owned ? "\(it.name), уже у тебя" : "\(it.name), купить за \(EconText.shards(ScrapSinks.placePrice))"))
                .accessibilityValue(Text(ScrapSinks.placeNote(state, have: shards)))
                .accessibilityIdentifier("sinks.exclusive")
                Text(ScrapSinks.placeNote(state, have: shards))
                    .petFont(13, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sinks.exclusive.note")
            }
        }
    }
}
