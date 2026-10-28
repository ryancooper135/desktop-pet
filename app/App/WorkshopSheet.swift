// Волна 32: «Мастерская ✂️» — лист из автомата с капсулами. Клочки ✂️ редкие (дефицит — решение владельца),
// тратятся тут: «Ателье» — новая вещь выбранной редкости без повторок, и лоскутные вещи, которых нет
// ни в капсуле, ни в лавке. Ещё за клочки возвращают пса (это экран смерти, не здесь). Всё только игровое —
// реальных денег в игре нет. Логика и тексты — Shards (Shared/Premium.swift), тут только вид.
// Решения (Вадим может поменять): без клочков кнопка не гаснет — пишет «Не хватает N», нажатие объясняет отказ.

import SwiftUI
@preconcurrency import PetCore

struct WorkshopSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var refusal: String?

    var body: some View {
        let offers = model.file.map { Shards.offers($0) } ?? []
        // Волна 40 F: сезонные вещи — свой раздел, только в свой сезон (под тестами осень).
        let season = Seasons.now()
        let seasonal = model.file.map { Seasons.offers($0, season: season) } ?? []
        ScrollView {
            VStack(spacing: 12) {
                header
                if let refusal {
                    Text(refusal)
                        .petFont(14, .semibold)
                        .foregroundStyle(PetPalette.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                        .accessibilityIdentifier("workshop.refusal")
                }
                ForEach(offers) { card($0) }
                if !seasonal.isEmpty {
                    seasonHeader(season)
                    ForEach(seasonal) { card($0) }
                }
                Text("Клочки — за дни заботы, сундук недели, рекорды, находки на прогулке и повторки из капсул.")
                    .petFont(12, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .animation(.snappy, value: refusal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workshop.screen")
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
                .accessibilityIdentifier("workshop.close")
            }
            Text("✂️ Мастерская")
                .petFont(22, .bold)
                .foregroundStyle(PetPalette.ink)
                .accessibilityLabel(Text("Мастерская"))
                .accessibilityAddTraits(.isHeader)
            if let f = model.file {
                Text("✂️ \(f.econ.wallet.shards)")
                    .petFont(15, .semibold)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text(EconText.shards(f.econ.wallet.shards)))
                    .accessibilityIdentifier("workshop.wallet")
                // Как клочки копятся: дела сегодня и дни недели, плюс последняя награда.
                VStack(spacing: 2) {
                    Text(Shards.progress(f, now: Clock.now()))
                    if let g = f.shardLog.last {
                        Text("Последние: \(Shards.gainText(g))")
                    }
                }
                .petFont(13, .medium)
                .monospacedDigit()
                .foregroundStyle(PetPalette.soft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("workshop.progress")
            }
        }
    }

    /// «🍂 Осеннее — только осенью» и строка о том, что купленное остаётся.
    private func seasonHeader(_ s: Season) -> some View {
        VStack(spacing: 2) {
            Text(Seasons.title(s))
                .petFont(17, .bold)
                .foregroundStyle(PetPalette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(Seasons.note(s))
                .petFont(12, .medium)
                .foregroundStyle(PetPalette.soft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workshop.season")
    }

    private func card(_ o: ShardOffer) -> some View {
        let canTake: Bool = { if case .buy(let need) = o.state { return need == 0 } else { return false } }()
        let done: Bool = { if case .buy = o.state { return false } else { return true } }()
        return AXRow {
            HStack(spacing: 12) {
                if let id = o.itemId {
                    ItemTile(id: id, rarity: o.rarity, size: 56)
                        .opacity(done ? 0.55 : 1)
                } else {
                    Text("✂️")
                        .font(.system(size: 26))
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 12).fill(rarityColor(o.rarity).opacity(0.25)))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.title)
                        .petFont(16, .semibold)
                        .foregroundStyle(PetPalette.ink)
                        .axLines(2)
                        .minimumScaleFactor(0.8)
                    Text(EconText.rarityName(o.rarity))
                        .petFont(12, .bold)
                        .foregroundStyle(rarityColor(o.rarity))
                    Text(o.note)
                        .petFont(12, .medium)
                        .foregroundStyle(o.itemId != nil ? PetPalette.accent : PetPalette.soft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("✂️ \(o.price)")
                        .petFont(14, .heavy)
                        .monospacedDigit()
                        .foregroundStyle(done ? PetPalette.soft : PetPalette.ink)
                        .accessibilityLabel(Text(EconText.shards(o.price)))
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workshop.offer.\(o.id)")
            takeButton(o, canTake: canTake, done: done)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
    }

    /// «Взять» — залитая акцентом; «Не хватает N» — обводка; «Уже есть / Всё собрано» — серая надпись.
    private func takeButton(_ o: ShardOffer, canTake: Bool, done: Bool) -> some View {
        Button {
            guard !done else { return }
            refusal = model.takeShardOffer(o)
        } label: {
            Text(Shards.buttonTitle(o))
                .petFont(13, .bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(canTake ? Color.white : (done ? PetPalette.soft : PetPalette.accent))
                .padding(.horizontal, 12)
                .frame(minWidth: 88, minHeight: 36)
                .background {
                    if canTake {
                        Capsule().fill(PetPalette.accent)
                    } else if !done {
                        Capsule().strokeBorder(PetPalette.accent, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(SquishStyle())
        .disabled(done)
        .deniedTap(when: done)
        .accessibilityLabel(Text(done ? Shards.buttonTitle(o) : "Взять «\(o.title)» за \(EconText.shards(o.price))"))
        .accessibilityIdentifier("workshop.take.\(o.id)")
    }
}
