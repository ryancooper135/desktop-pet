// Экран «Дом» (этап 8): шесть линий улучшений за монеты — ванная, лежанка, кухня, будка, уголок, дворик.
// В карточке линии: значок, имя, текущий уровень и точки уровней, что даёт сейчас, что даст следующий и кнопка с ценой.
// Логика — HomeShop и HomeOffer (Shared), тут только вид. Открывается круглой кнопкой с домиком рядом с автоматом
// и по pet://house. Решения (Вадим может поменять): без монет кнопка не гаснет — пишет «Не хватает N», нажатие
// качает карточку и объясняет отказ строкой под кнопкой; на максимуме вместо кнопки плашка «Лучший уровень».
// Волна 12: в карточке кухни — вход в лист «Кухня» (KitchenSheet): угостить едой за монеты, на L3 — готовить.

import SwiftUI
@preconcurrency import PetCore

struct HouseScreen: View {
    @Environment(AppModel.self) private var model

    /// Строка под кнопкой одной линии: отказ или «Готово: Ванна». Гаснет сама.
    struct Note: Equatable {
        let id = UUID()
        let line: HomeLine
        let text: String
        let ok: Bool
    }

    @State private var note: Note?
    @State private var noteTask: Task<Void, Never>?
    @State private var shakes: [HomeLine: Int] = [:]
    @State private var bumps: [HomeLine: Int] = [:]

    static let noteFor: Double = 2.5

    var body: some View {
        @Bindable var model = model
        let rows = model.file.map { HomeOffer.rows($0) } ?? []
        ScrollView {
            VStack(spacing: 14) {
                header
                if rows.isEmpty {
                    Text("Улучшений пока нет")
                        .petFont(15, .medium)
                        .foregroundStyle(PetPalette.soft)
                        .padding(.top, 20)
                }
                ForEach(rows, id: \.id) { r in
                    HomeLineCard(row: r,
                                 note: note?.line == r.id ? note : nil,
                                 shake: shakes[r.id, default: 0],
                                 bump: bumps[r.id, default: 0],
                                 kitchen: r.id == .kitchen ? { openKitchen() } : nil) { buy(r) }
                }
                Text("Дом остаётся, даже если начать заново с новым щенком.")
                    .petFont(12, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .sheet(isPresented: $model.showKitchen) {
            KitchenSheet()
                .environment(model)
                .presentationDetents([.large])
        }
        .animation(.snappy, value: note)
        .onDisappear { noteTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("house.screen")
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                SheetCloseButton(id: "house.close")
            }
            Text("Дом")
                .petFont(22, .bold)
                .foregroundStyle(PetPalette.ink)
                .accessibilityAddTraits(.isHeader)
            if let coins = model.file?.econ.wallet.coins {
                Text("🪙 \(coins)")
                    .petFont(15, .semibold)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
                    .contentTransition(.numericText(value: Double(coins)))
                    .animation(.snappy, value: coins)
                    .accessibilityLabel(Text(EconText.coins(coins)))
                    .accessibilityIdentifier("house.wallet")
            }
        }
    }

    private func buy(_ r: HomeRow) {
        guard let res = model.buyHome(r.id) else { return }
        if let why = HomeOffer.refusal(res) {
            say(Note(line: r.id, text: why, ok: false))
            shakes[r.id, default: 0] += 1
            Feel.denied()
        } else {
            say(Note(line: r.id, text: HomeOffer.bought(res, line: r.id) ?? "Готово", ok: true))
            bumps[r.id, default: 0] += 1
            Feel.success(.hearts)
        }
    }

    private func openKitchen() {
        model.showKitchen = true
    }

    private func say(_ n: Note) {
        note = n
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: .seconds(Self.noteFor))
            if Task.isCancelled { return }
            if note?.id == n.id { note = nil }
        }
    }
}

/// Карточка одной линии дома.
struct HomeLineCard: View {
    let row: HomeRow
    let note: HouseScreen.Note?
    let shake: Int
    let bump: Int
    /// Только у кухни: открыть лист «Кухня».
    var kitchen: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: Self.icon(row.id))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PetPalette.accent)
                    .symbolEffect(.bounce, value: bump)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(PetPalette.accent.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .petFont(17, .bold)
                        .foregroundStyle(PetPalette.ink)
                    Text(row.levelName)
                        .petFont(14, .medium)
                        .foregroundStyle(PetPalette.soft)
                }
                .axLines(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                LevelPips(level: row.level, top: row.top)
            }
            .accessibilityElement(children: .combine)

            if !row.perks.isEmpty {
                PerkList(perks: row.perks, icon: "checkmark.circle.fill", color: PetPalette.soft)
                    .accessibilityLabel(Text("Сейчас: \(row.perks.joined(separator: ", "))"))
            }

            if let n = row.next {
                Rectangle()
                    .fill(PetPalette.soft.opacity(0.2))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Дальше: \(n.name)")
                        .petFont(14, .bold)
                        .foregroundStyle(PetPalette.ink)
                    PerkList(perks: n.perks, icon: "plus.circle.fill", color: PetPalette.green)
                }
                .accessibilityElement(children: .combine)
                BuyButton(row: row, next: n, action: action)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                    Text(HomeOffer.buttonTitle(row))
                }
                .petFont(14, .bold)
                .foregroundStyle(PetPalette.yellow)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.yellow.opacity(0.14)))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("house.maxed.\(row.id.rawValue)")
            }

            if let kitchen {
                KitchenEntry(cooking: row.level >= 3, action: kitchen)
            }

            if let note {
                Text(note.text)
                    .petFont(13, .semibold)
                    .foregroundStyle(note.ok ? PetPalette.green : PetPalette.red)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .accessibilityIdentifier("house.note.\(row.id.rawValue)")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
        .modifier(RefuseShake(trigger: shake))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("house.line.\(row.id.rawValue)")
    }

    /// Значок линии (SF Symbols, все есть с iOS 16).
    static func icon(_ id: HomeLine) -> String {
        switch id {
        case .bath: return "bathtub.fill"
        case .bed: return "bed.double.fill"
        case .kitchen: return "refrigerator.fill"
        case .kennel: return "house.fill"
        case .play: return "teddybear.fill"
        case .yard: return "tree.fill"
        }
    }
}

/// «Кухня: угостить и приготовить» в карточке кухни. До кухни шефа — только «угостить».
struct KitchenEntry: View {
    let cooking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "frying.pan.fill")
                    .accessibilityHidden(true)
                Text(cooking ? "Кухня: угостить и приготовить" : "Кухня: угостить")
                    .axLines(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .accessibilityHidden(true)
            }
            .petFont(15, .bold)
            .foregroundStyle(PetPalette.accent)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(PetPalette.accent, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(SquishStyle())
        .accessibilityIdentifier("house.kitchen.open")
    }
}

/// Сегменты уровней справа: закрашено столько, сколько куплено.
struct LevelPips: View {
    let level: Int
    let top: Int

    var body: some View {
        // Плоские сегменты шкалы: три серые точки читались как кнопка меню «…»,
        // а пустые капсулы контуром — как звенья цепочки.
        HStack(spacing: 2) {
            ForEach(0..<max(top, 0), id: \.self) { i in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(i < level ? PetPalette.accent : PetPalette.soft.opacity(0.3))
                    .frame(width: 16, height: 5)
            }
        }
        .animation(.snappy, value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Уровень \(level) из \(top)"))
    }
}

/// Столбик баффов со значком в начале строки.
struct PerkList: View {
    let perks: [String]
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(perks, id: \.self) { p in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                    Text(p)
                        .petFont(13, .medium)
                        .foregroundStyle(PetPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// «Купить · 🪙 700». Не по карману — бледная и с «Не хватает N», но нажимается: отказ объясняет строка под ней.
struct BuyButton: View {
    let row: HomeRow
    let next: HomeRow.Next
    let action: () -> Void

    var body: some View {
        let title = HomeOffer.buttonTitle(row)
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .petFont(15, .bold)
                Spacer(minLength: 8)
                Text("🪙 \(next.price)")
                    .petFont(15, .heavy)
                    .monospacedDigit()
            }
            .axLines(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(row.canBuy ? Color.white : PetPalette.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(row.canBuy ? PetPalette.accent : PetPalette.soft.opacity(0.18)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(next.name): купить за \(EconText.coins(next.price))"))
        .accessibilityValue(Text(row.canBuy ? "" : title))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("house.buy.\(row.id.rawValue)")
    }
}

/// Кнопка «Дом» в ряду над панелью, рядом с автоматом: только значок. Id — open.house.
struct HouseButton: View {
    @Environment(AppModel.self) private var model
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            model.showHouse = true
        } label: {
            Image(systemName: "house.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolEffect(.bounce, value: taps)
                .foregroundStyle(PetPalette.ink)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(SquishStyle())
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(Text("Дом"))
        .accessibilityHint(Text("Улучшения дома за монеты"))
        .accessibilityIdentifier("open.house")
    }
}
