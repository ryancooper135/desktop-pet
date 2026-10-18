// Прогулка с находкой на главном экране: кнопка «Гулять», кнопка альбома, записка в пустой комнате и сам альбом.
// Где что стоит (решение, Вадим может поменять):
// • ряд над панелью действий: слева — «Альбом» со счётчиком находок, справа — «Гулять» с подписью-причиной;
//   в беде ряда нет (там большая «Спасти»), после смерти — тоже;
// • записка «Ушёл гулять, вернусь в 14:20» — бумажкой на месте Шибы, пока его нет;
// • альбом — шит, ещё открывается по pet://album;
// • волна 5: круглая кнопка автомата между «Альбомом» и «Гулять» (pet://capsule), в альбоме — «Вкусы» и «Открытки»;
// • этап 8: рядом с автоматом круглая кнопка «Дом» (pet://house, HouseScreen.swift);
// • волна 8: за «Домом» круглая кнопка «Трюки» (pet://tricks, TricksScreen.swift). Ряд тесный (ViewThatFits): если целиком
//   не влезает, сначала прячется строчка под «Гулять» (её дублируют тост, записка и VoiceOver), «Альбом» с подписью
//   остаётся; не влезло и так — «Альбом» сжимается до значка со счётчиком, а «Гулять» снова со строчкой.
// • волна 9: за «Трюками» круглая кнопка «Лови мячик» (pet://catch, CatchGameScreen.swift); на самый тесный ряд —
//   «Альбом» значком и «Гулять» без строчки, зазоры 4 и 2.
// Можно ли гулять, решает ядро (WalkPlan.gate → PetEngine.act на копии), здесь только вид.

import SwiftUI
@preconcurrency import PetCore

// MARK: - Ряд «Альбом · Автомат · Дом · Трюки · Мячик · Гулять»

struct WalkRow: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot

    var body: some View {
        let gate = model.file.map { WalkPlan.gate($0, at: snap.t) }
        let tricks = model.file.map { Tricks.gate($0, at: snap.t) } ?? Tricks.loadingReason
        let total = Finds.total(albumFinds(model.file, at: snap.t))
        // Всё целиком; не влезло — «Гулять» без строчки (iPhone Air, кнопки плотнее); дальше — «Альбом» значком;
        // совсем узко — плотнее. Последний вариант берётся всегда.
        ViewThatFits(in: .horizontal) {
            row(gate: gate, tricks: tricks, total: total, compact: false, brief: false, spacing: 8)
            row(gate: gate, tricks: tricks, total: total, compact: false, brief: true, spacing: 6)
            row(gate: gate, tricks: tricks, total: total, compact: false, brief: true, spacing: 4)
            row(gate: gate, tricks: tricks, total: total, compact: true, brief: false, spacing: 8)
            row(gate: gate, tricks: tricks, total: total, compact: true, brief: false, spacing: 5)
            row(gate: gate, tricks: tricks, total: total, compact: true, brief: true, spacing: 4)
            row(gate: gate, tricks: tricks, total: total, compact: true, brief: true, spacing: 2)
        }
    }

    private func row(gate: WalkGate?, tricks: String?, total: Int, compact: Bool, brief: Bool,
                     spacing: CGFloat) -> some View {
        // Распорка — сама зазор до «Гулять»: у HStack со spacing она добавила бы лишний с обеих сторон.
        HStack(spacing: 0) {
            HStack(spacing: spacing) {
                AlbumButton(total: total, compact: compact)
                MachineButton()
                HouseButton()
                TricksButton(gate: tricks)
                CatchButton(t: snap.t)
            }
            Spacer(minLength: spacing)
            if let gate {
                WalkButton(gate: gate, brief: brief)
            }
        }
    }
}

/// Альбом на момент снимка: находка из прогулки, что только что кончилась, уже в нём (стор допишет при catchUp).
@MainActor
func albumFinds(_ f: SaveFile?, at t: Double) -> [String: Int] {
    guard let f else { return [:] }
    return PetRunner.peek(f, at: t).finds
}

/// «Гулять»: иконка, крупная подпись и строчка «почему нельзя / когда вернётся». Неактивная — полупрозрачная,
/// но нажимается: тост объясняет, что сделать, кнопка качается. Id для UI-тестов — act.walk.
struct WalkButton: View {
    @Environment(AppModel.self) private var model
    let gate: WalkGate
    /// Тесный ряд: только «Гулять», без строчки-причины (она в тосте по нажатию и в accessibilityValue).
    var brief = false
    @State private var taps = 0
    @State private var refusals = 0

    private static let shake: [CGFloat] = [0, -6, 6, -3, 0]

    private var away: Bool { gate.reason == "away" }

    var body: some View {
        Button {
            taps += 1
            if gate.ok {
                model.act(.walk)
            } else {
                refusals += 1
                model.haptic(.warning)
                model.show(gate.toast, ok: away)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.bounce, value: taps)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(away ? "Гуляет" : "Гулять")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    if !brief && !gate.hint.isEmpty {
                        Text(gate.hint)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PetPalette.soft)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .foregroundStyle(PetPalette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(SquishStyle())
        .opacity(gate.ok || away ? 1 : 0.55)
        .glassEffect(.regular.interactive(), in: Capsule())
        .phaseAnimator(Self.shake, trigger: refusals, content: { view, x in
            view.offset(x: x)
        }, animation: { _ in
            .linear(duration: 0.06)
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(away ? "Гуляет" : "Гулять"))
        .accessibilityValue(Text(gate.ok ? gate.hint : (gate.toast.isEmpty ? gate.hint : gate.toast)))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("act.walk")
    }
}

/// Кнопка альбома: книжка и сколько всего принёс. Id — open.album.
struct AlbumButton: View {
    @Environment(AppModel.self) private var model
    let total: Int
    /// Узкий ряд: без подписи, только книжки и счётчик.
    var compact = false

    var body: some View {
        Button {
            model.showAlbum = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
                if !compact {
                    Text("Альбом")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                if total > 0 {
                    Text("\(total)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(PetPalette.accent.opacity(0.22)))
                }
            }
            .lineLimit(1)
            .foregroundStyle(PetPalette.ink)
            .padding(.horizontal, compact && total == 0 ? 0 : 14)
            .frame(minWidth: 48, minHeight: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(SquishStyle())
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel(Text("Альбом находок"))
        .accessibilityValue(Text(total > 0 ? "Находок: \(total)" : "Пока пусто"))
        .accessibilityIdentifier("open.album")
    }
}

/// Автомат с капсулами: только значок, ряд и так тесный. Id — act.capsule.
struct MachineButton: View {
    @Environment(AppModel.self) private var model
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            model.showCapsule = true
        } label: {
            Image(systemName: "gift.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolEffect(.bounce, value: taps)
                .foregroundStyle(PetPalette.ink)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(SquishStyle())
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(Text("Автомат"))
        .accessibilityHint(Text("Капсулы за билетики и монеты"))
        .accessibilityIdentifier("act.capsule")
    }
}

// MARK: - Записка в пустой комнате

/// Бумажка на месте Шибы, пока он гуляет: «Ушёл гулять, вернусь в 14:20». Чуть набок, с кнопкой-булавкой.
struct AwayNoteCard: View {
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(PetPalette.accent)
            Text(text)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 240)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: 0xfff6d8))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        )
        .overlay(alignment: .top) {
            Circle().fill(PetPalette.red).frame(width: 12, height: 12).offset(y: -5)
        }
        // Бумага всегда светлая, текст на ней — тёмный и в тёмной теме.
        .environment(\.colorScheme, .light)
        .rotationEffect(.degrees(-3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Записка: \(text)"))
        .accessibilityIdentifier("pet.awayNote")
    }
}

// MARK: - Альбом

struct AlbumSheet: View {
    @Environment(AppModel.self) private var model
    /// Открытка из альбома на весь лист (свой sheet: домашний занят альбомом).
    @State private var opened: Postcard?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let finds = albumFinds(model.file, at: model.snap.t)
        let rows = Finds.album(finds)
        let total = Finds.total(finds)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Альбом находок")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    // Без имени: «Отпусти Шиба» не склоняется. Тире не уходит в начало строки.
                    Text(total == 0 ? Presenter.keepDash("Пока пусто. Отпусти на прогулку — принесёт что-нибудь.")
                         : "Принёс \(total) · разных \(Finds.kinds(finds)) из \(Finds.all.count)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                        .accessibilityIdentifier("album.total")
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(rows, id: \.find.id) { row in
                        AlbumCell(find: row.find, count: row.count)
                    }
                }
                Text("Кнопка «Гулять» — над панелью действий. Гуляет 1–3 часа, каждая прогулка — новая находка.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
                if let f = model.file {
                    TastesSection(facts: Tastes.album(f), guesses: TasteGuess.list(f))
                    PostcardsSection(cards: Postcards.album(f), opened: $opened)
                }
            }
            .padding(20)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("album.sheet")
        .sheet(item: $opened) { card in
            PostcardSheet(card: card, fromAlbum: true)
                .environment(model)
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Вкусы в альбоме

/// Вкус в процессе: набрано n согласных наблюдений из needed. Что за вещь и любит ли — не говорим.
struct TasteGuess: Identifiable, Hashable {
    let id: String
    let category: TasteCategory
    let n: Int
    let needed: Int

    /// Только любимое и нелюбимое: «нормально» не откроется никогда, полоска к нему врала бы.
    static func list(_ f: SaveFile) -> [TasteGuess] {
        f.tastes.seen.compactMap { e -> TasteGuess? in
            let (k, v) = (e.key, e.value)
            guard v.r == Taste.love.rawValue || v.r == Taste.dislike.rawValue, f.tastes.opened[k] == nil,
                  let c = TasteCategory(rawValue: String(k.split(separator: ".").first ?? "")) else { return nil }
            return TasteGuess(id: k, category: c, n: v.n, needed: Tastes.needed(c))
        }
        .sorted { ($1.n, $0.id) < ($0.n, $1.id) }
    }

    static func title(_ c: TasteCategory) -> String {
        switch c {
        case .food: return "Еда"
        case .toy: return "Игрушка"
        case .find: return "Находка"
        }
    }
}

/// «Вкусы»: открытые — значок и фраза, в процессе — «???» с полоской. Id — album.tastes.
struct TastesSection: View {
    let facts: [TasteFact]
    let guesses: [TasteGuess]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Вкусы")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                Spacer(minLength: 0)
                Text("Открыто \(facts.count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
            }
            if facts.isEmpty && guesses.isEmpty {
                Text("Пока загадка. Корми и играй — сам покажет, что любит, а что нет.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(facts) { fact in
                HStack(spacing: 10) {
                    Text(fact.emoji).font(.system(size: 24))
                        .frame(width: 36)
                    Text(fact.text)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: fact.taste == .dislike ? "hand.thumbsdown.fill" : "heart.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(fact.taste == .dislike ? PetPalette.soft : PetPalette.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(fact.text))
            }
            ForEach(guesses) { g in
                HStack(spacing: 10) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(PetPalette.soft.opacity(0.7))
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(TasteGuess.title(g.category)): ???")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(PetPalette.soft)
                        ProgressView(value: Double(min(g.n, g.needed)), total: Double(max(g.needed, 1)))
                            .tint(PetPalette.accent)
                    }
                    Text("\(min(g.n, g.needed))/\(g.needed)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PetPalette.soft)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card.opacity(0.6)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(TasteGuess.title(g.category)): ещё не ясно"))
                .accessibilityValue(Text("\(min(g.n, g.needed)) из \(g.needed)"))
            }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("album.tastes")
    }
}

// MARK: - Открытки в альбоме

/// «Открытки»: сохранённые, по две в ряд. Тап — на весь лист, удержание — «Удалить». Id — album.postcards.
struct PostcardsSection: View {
    @Environment(AppModel.self) private var model
    let cards: [Postcard]
    @Binding var opened: Postcard?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Открытки")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                Spacer(minLength: 0)
                Text("\(cards.count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
            }
            if cards.isEmpty {
                Text("Каждое утро — открытка о вчерашнем дне. Сохраняй, и они будут здесь.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(cards) { card in
                        Button {
                            opened = card
                        } label: {
                            PostcardFace(frame: card.frame, compact: true)
                        }
                        .buttonStyle(SquishStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                model.removePostcard(card)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        .accessibilityLabel(Text("Открытка: \(card.caption), \(card.frame.date)"))
                        .accessibilityIdentifier("album.postcard.\(card.id)")
                    }
                }
            }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("album.postcards")
    }
}

/// Клетка альбома: значок, имя и «×2». Ещё не находил — серый вопрос и «???».
struct AlbumCell: View {
    let find: Find
    let count: Int

    var body: some View {
        let seen = count > 0
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(seen ? Color(hex: find.color).opacity(0.22) : PetPalette.soft.opacity(0.12))
                if seen {
                    Text(find.emoji).font(.system(size: 30))
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PetPalette.soft.opacity(0.6))
                }
            }
            .frame(width: 56, height: 56)
            Text(seen ? find.title : "???")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(seen ? PetPalette.ink : PetPalette.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(seen ? "×\(count)" : "не находил")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PetPalette.soft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(seen ? "\(find.title): \(count)" : "Ещё не находил"))
        .accessibilityIdentifier("album.\(find.id)")
    }
}
