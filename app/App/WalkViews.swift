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
// • волна 12: та же кнопка стала «Мини-игры» — меню «Лови мячик» / «Блок Дуо» (pet://blockduo, BlockDuoScreen.swift):
//   седьмой кружок в ряд на iPhone Air не влезает.
// • волна 32: под кругами мелкие подписи (RoundCaption.swift), ряд оставляет под ними RoundCaption.room.
// Можно ли гулять, решает ядро (WalkPlan.gate → PetEngine.act на копии), здесь только вид.

import SwiftUI
@preconcurrency import PetCore

// MARK: - Ряд «Альбом · Автомат · Дом · Трюки · Игры · Гулять»

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
            // Волна 32: подписи под кругами (у «Альбома» с текстом — только когда он сжат до значка).
            HStack(spacing: spacing) {
                AlbumButton(total: total, compact: compact)
                    .roundCaption(compact ? RoundCaption.album : nil)
                MachineButton()
                    .roundCaption(RoundCaption.machine)
                HouseButton()
                    .roundCaption(RoundCaption.house)
                TricksButton(gate: tricks)
                    .roundCaption(RoundCaption.tricks)
                GamesButton(t: snap.t)
                    .roundCaption(RoundCaption.games)
            }
            Spacer(minLength: spacing)
            if let gate {
                WalkButton(gate: gate, brief: brief)
            }
        }
        .padding(.bottom, RoundCaption.room)
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
/// Волна 18: активная — цветное стекло (ActTint walk). Неактивная — замок и значок того, чего не хватает (миска, ванна),
/// виден и в тесном ряду без строчки; по тапу подсвечивается кнопка панели, что это исправит (WalkGate.fix).
struct WalkButton: View {
    @Environment(AppModel.self) private var model
    let gate: WalkGate
    /// Тесный ряд: только «Гулять», без строчки-причины (она в тосте по нажатию и в accessibilityValue).
    var brief = false
    /// Волна 53: круг 66 pt справа от таб-бара (HomeTabBar) — только значок, причина в бейдже и в VoiceOver.
    var circle = false
    @State private var taps = 0
    @State private var refusals = 0

    private var away: Bool { gate.reason == "away" }
    /// Волна 34 H: с уровня 2 «Гулять» открывает карту мест (там и «Просто погулять»). До того — как раньше.
    private var map: Bool { model.hasPlaces }
    /// Пока пёс в походе — где он: «🗼 Маяк · вернётся в 14:20».
    private var tripHint: String? {
        guard let a = model.placeTrip, let f = model.file else { return nil }
        let p = Places.place(a.place)
        return "\(p?.emoji ?? "🐾") \(p?.name ?? a.place) · \(Places.backText(a, tzOffsetMin: f.owner.tzOffsetMin, now: model.snap.t))"
    }
    private var hint: String { tripHint ?? gate.hint }

    private var circleLabel: some View {
        Image(systemName: away ? "figure.walk.motion" : "figure.walk")
            .font(.system(size: 24, weight: .semibold))
            .symbolEffect(.bounce, value: taps)
            .foregroundStyle(gate.ok || away ? PetPalette.vio : PetPalette.ink.opacity(0.45))
            .frame(width: BMetrics.tabBar, height: BMetrics.tabBar)
            .contentShape(Circle())
            .accessibilityHidden(true)
    }

    private var rowLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.system(size: 20, weight: .semibold))
                .symbolEffect(.bounce, value: taps)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(away ? "Гуляет" : "Гулять")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                if !brief && !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(gate.ok ? Color.white.opacity(0.85) : PetPalette.soft)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .foregroundStyle(gate.ok ? AnyShapeStyle(Color.white) : AnyShapeStyle(PetPalette.ink.opacity(away ? 1 : 0.55)))
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .contentShape(Capsule())
    }

    var body: some View {
        Button {
            taps += 1
            if map {
                model.showMap = true
            } else if gate.ok {
                model.act(.walk)
            } else {
                refusals += 1
                // Нельзя — с «не-а», как у остальных отказов (раньше только вибрация).
                Feel.denied()
                // Волна 25: плашка над кнопкой уже говорит то же самое — второй раз в тосте не повторяем.
                let plate = model.file.flatMap { NeedHints.pick(model.snap, file: $0) }
                if let text = Hush.walkToast(gate: gate, plate: plate) { model.show(text, ok: away) }
                if let fix = gate.fix { Coach.shared.highlightButton(fix) }
            }
        } label: {
            if circle { circleLabel } else { rowLabel }
        }
        .buttonStyle(SquishStyle())
        // Волна 53: круг у таб-бара — белое стекло, как в макете B; капсула (старый ряд) — цветное, когда можно.
        .bGlass(circle ? AnyShape(Circle()) : AnyShape(Capsule()),
                tint: gate.ok && !circle ? ActTint.color("walk").opacity(0.88) : nil, interactive: true)
        .overlay(alignment: .topTrailing) {
            if !gate.ok && !away && !map {
                // Причина видна всегда, даже без строчки: замок и что нужно сначала (миска, ванна, мячик, рука).
                HStack(spacing: 2) {
                    Image(systemName: "lock.fill")
                    if let fix = gate.fix { Image(systemName: NeedHints.icon(fix)) }
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Capsule().fill(gate.fix.map { ActTint.color($0) } ?? PetPalette.soft))
                .offset(x: circle ? -2 : 4, y: circle ? 2 : -6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .coachHighlight("walk")
        .modifier(RefuseShake(trigger: refusals))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(away ? "Гуляет" : "Гулять"))
        .accessibilityValue(Text(tripHint ?? (gate.ok ? gate.hint : (gate.toast.isEmpty ? gate.hint : gate.toast))))
        .accessibilityHint(Text(map ? "Открывает карту мест" : ""))
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
                if total > 0 && !compact {
                    count
                        .background(Capsule().fill(PetPalette.accent.opacity(0.22)))
                }
            }
            .lineLimit(1)
            .foregroundStyle(PetPalette.ink)
            .padding(.horizontal, compact ? 0 : 14)
            .frame(minWidth: 48, minHeight: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(SquishStyle())
        .glassEffect(.regular.interactive(), in: Capsule())
        // В узком ряду кнопка — круг 48×48, счётчик значком в углу: внутри круга он обрезался.
        .overlay(alignment: .topTrailing) {
            if total > 0 && compact {
                count
                    .foregroundStyle(PetPalette.ink)
                    .background(Capsule().fill(PetPalette.accent.opacity(0.85)))
                    .offset(x: 6, y: -4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(Text("Альбом находок"))
        .accessibilityValue(Text(total > 0 ? "Находок: \(total)" : "Пока пусто"))
        .accessibilityIdentifier("open.album")
    }

    private var count: some View {
        Text(total > 99 ? "99+" : "\(total)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
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
    @Environment(AppModel.self) private var model
    let text: String

    /// Волна 34 H: в походе — куда ушёл: «Ушёл: 🗼 Маяк, вернусь в 14:20».
    private var shown: String {
        guard let a = model.placeTrip, let f = model.file else { return text }
        return Places.awayNote(a, tzOffsetMin: f.owner.tzOffsetMin, now: model.snap.t)
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(PetPalette.accent)
            Text(shown)
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
        .accessibilityLabel(Text("Записка: \(shown)"))
        .accessibilityIdentifier("pet.awayNote")
    }
}

// MARK: - Альбом

struct AlbumSheet: View {
    @Environment(AppModel.self) private var model
    /// Открытка из альбома на весь лист (свой sheet: домашний занят альбомом).
    @State private var opened: Postcard?
    @Environment(\.dynamicTypeSize) private var type

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let finds = albumFinds(model.file, at: model.snap.t)
        let rows = Finds.album(finds)
        let total = Finds.total(finds)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center) {
                        Text("Альбом находок")
                            .petFont(22, .bold)
                            .foregroundStyle(PetPalette.ink)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        SheetCloseButton(id: "album.close")
                    }
                    // Без имени: «Отпусти Шиба» не склоняется. Тире не уходит в начало строки.
                    Text(total == 0 ? Presenter.keepDash("Пока пусто. Отпусти на прогулку — принесёт что-нибудь.")
                         : "Принёс \(total) · разных \(Finds.kinds(finds)) из \(Finds.all.count)")
                        .petFont(13, .medium)
                        .foregroundStyle(PetPalette.soft)
                        .accessibilityIdentifier("album.total")
                }
                // Крупный шрифт: две колонки вместо трёх, иначе имя находки режется.
                LazyVGrid(columns: type.isAccessibilitySize ? Array(columns.prefix(2)) : columns, spacing: 10) {
                    ForEach(rows, id: \.find.id) { row in
                        AlbumCell(find: row.find, count: row.count)
                    }
                }
                // Волна 53: «Гулять» — круг справа от таб-бара, а не ряд над панелью.
                Text("Круг «Гулять» — справа от нижней панели. Гуляет 1–3 часа, каждая прогулка — новая находка.")
                    .petFont(12, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
                if let f = model.file {
                    let t = model.snap.t
                    CharacterSection(scores: Traits.scores(f, at: t), summary: Traits.summary(f, at: t),
                                     done: Traits.total(f, at: t))
                    MemoriesSection(rows: Memories.album(f))
                    TastesSection(facts: Tastes.album(f), guesses: TasteGuess.list(f))
                    PlacesSection(f: f, level: model.placeLevel)
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
            HStack(alignment: .center) {
                Text("Вкусы")
                    .petFont(18, .bold)
                    .foregroundStyle(PetPalette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("Открыто \(facts.count)")
                    .petFont(13, .medium)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
            }
            if facts.isEmpty && guesses.isEmpty {
                Text("Пока загадка. Корми и играй — сам покажет, что любит, а что нет.")
                    .petFont(13, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(facts) { fact in
                HStack(spacing: 10) {
                    Text(fact.emoji).font(.system(size: 24))
                        .frame(width: 36)
                    Text(fact.text)
                        .petFont(15, .semibold)
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
                            .petFont(15, .semibold)
                            .foregroundStyle(PetPalette.soft)
                        ProgressView(value: Double(min(g.n, g.needed)), total: Double(max(g.needed, 1)))
                            .tint(PetPalette.accent)
                    }
                    Text("\(min(g.n, g.needed))/\(g.needed)")
                        .petFont(12, .bold)
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
            HStack(alignment: .center) {
                Text("Открытки")
                    .petFont(18, .bold)
                    .foregroundStyle(PetPalette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("\(cards.count)")
                    .petFont(13, .medium)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
            }
            if cards.isEmpty {
                Text("Каждое утро — открытка о вчерашнем дне. Сохраняй, и они будут здесь.")
                    .petFont(13, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(cards) { card in
                        Button {
                            opened = card
                        } label: {
                            PostcardFace(card: card, compact: true)
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
                        // Удаление из контекстного меню — и действием VoiceOver (меню удержанием с ним неудобно).
                        .accessibilityAction(named: Text("Удалить")) { model.removePostcard(card) }
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
                .petFont(14, .semibold)
                .foregroundStyle(seen ? PetPalette.ink : PetPalette.soft)
                .axLines(1)
                .minimumScaleFactor(0.8)
            Text(seen ? "×\(count)" : "не находил")
                .petFont(12, .medium)
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
