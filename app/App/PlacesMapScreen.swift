// Волна 34 H: экран «Карта» — бумажная карта мест вокруг двора. Без картинок: бумага, заломы и пунктир рисует Canvas.
// Тап по месту — карточка (что там, сколько идти, находки, «Пойти»). Пока пёс в походе, его точка ползёт по пунктиру.
// Логика и тексты — Shared/Places.swift, запись — AppModel+Places.swift. Id: map.screen, map.place.<id>, map.card, map.go,
// map.well, map.walk, map.dog, map.trip.

import SwiftUI
@preconcurrency import PetCore

struct PlacesMapScreen: View {
    @Environment(AppModel.self) private var model
    /// Открытая карточка места (свой лист: домашний занят картой).
    @State private var picked: PickedPlace?

    var body: some View {
        let lvl = model.placeLevel
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(lvl)
                if let f = model.file {
                    // Секундный тик нужен, только пока пёс в походе: точка идёт, часы «вернётся» верны.
                    TimelineView(.periodic(from: .now, by: model.placeTrip == nil ? 60 : 1)) { _ in
                        let now = Clock.now()
                        let cards = Places.cards(f, dogLevel: lvl, growthX: model.placeTimeX, now: now)
                        let trip = Places.walking(f, now: now)
                        VStack(alignment: .leading, spacing: 12) {
                            if let trip { tripLine(trip, f, now: now) }
                            PaperMap(cards: cards, trip: trip, now: now) { id in picked = PickedPlace(id: id) }
                        }
                    }
                    plainWalk(f)
                    if let r = f.trip.last { lastTrip(r) }
                }
            }
            .padding(20)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.screen")
        .sheet(item: $picked) { p in
            PlaceSheet(id: p.id) { go(p.id) }
                .environment(model)
                .presentationDetents([.large])
        }
    }

    private func header(_ lvl: Int) -> some View {
        let all = PlacesConfig.shared.places.count
        let open = Places.unlocked(dogLevel: lvl).count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text("Карта")
                    .petFont(22, .bold)
                    .foregroundStyle(PetPalette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                SheetCloseButton(id: "map.close")
            }
            Text("Уровень \(lvl) · открыто мест: \(open) из \(all). Выбери, куда сходить.")
                .petFont(13, .medium)
                .foregroundStyle(PetPalette.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// «🗼 Маяк · вернётся в 14:20» над картой, пока пёс в походе.
    private func tripLine(_ a: ActiveTrip, _ f: SaveFile, now: Double) -> some View {
        let p = Places.place(a.place)
        let text = "\(p?.emoji ?? "🐾") \(p?.name ?? a.place) · \(Places.backText(a, tzOffsetMin: f.owner.tzOffsetMin, now: now))"
        return HStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PetPalette.accent)
                .accessibilityHidden(true)
            Text(text)
                .petFont(15, .semibold)
                .foregroundStyle(PetPalette.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("В походе: \(text)"))
        .accessibilityIdentifier("map.trip")
    }

    /// «Просто погулять» — обычная прогулка ядра, без места. Нельзя — тост с причиной, как у «Гулять».
    private func plainWalk(_ f: SaveFile) -> some View {
        let gate = WalkPlan.gate(f, at: model.snap.t)
        return Button {
            if gate.ok {
                model.walkPlain()
            } else {
                model.refuse(gate.toast.isEmpty ? (gate.hint.isEmpty ? "Сейчас нельзя" : gate.hint) : gate.toast)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Просто погулять")
                        .petFont(16, .bold)
                    Text(gate.hint.isEmpty ? "Рядом с домом, с находкой" : gate.hint)
                        .petFont(12, .medium)
                        .foregroundStyle(PetPalette.soft)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PetPalette.soft)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(PetPalette.ink.opacity(gate.ok ? 1 : 0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Просто погулять"))
        .accessibilityValue(Text(gate.ok ? gate.hint : gate.toast))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("map.walk")
    }

    /// Записка последнего похода: место, что было, что принёс.
    private func lastTrip(_ r: TripResult) -> some View {
        let lines = Places.noteLines(r)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Последний поход")
                .petFont(13, .bold)
                .foregroundStyle(PetPalette.soft)
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text(line)
                    .petFont(i == 0 ? 16 : 14, i == 0 ? .bold : .medium)
                    .foregroundStyle(PetPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xfff6d8)))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("map.last")
    }

    /// «Пойти»: сначала уезжает карточка, потом поход (он же закроет карту) — два листа разом SwiftUI не снимает.
    private func go(_ id: String) {
        picked = nil
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            model.goPlace(id)
        }
    }
}

/// Обёртка для .sheet(item:): id места.
struct PickedPlace: Identifiable, Hashable {
    let id: String
}

// MARK: - Бумага

/// Где место на карте (доли ширины и высоты). Двор — в центре; незнакомые места встают по кругу.
enum MapSpots {
    static let yard = CGPoint(x: 0.5, y: 0.55)

    static let table: [String: CGPoint] = [
        "bus_stop": CGPoint(x: 0.24, y: 0.76),
        "laundry": CGPoint(x: 0.76, y: 0.78),
        "cat_hill": CGPoint(x: 0.17, y: 0.47),
        "arcade": CGPoint(x: 0.83, y: 0.50),
        "forest_tv": CGPoint(x: 0.24, y: 0.17),
        "lighthouse": CGPoint(x: 0.82, y: 0.17),
        "echo_well": CGPoint(x: 0.50, y: 0.92),
        "rocket": CGPoint(x: 0.53, y: 0.12),
    ]

    static func spot(_ id: String, index: Int, count: Int) -> CGPoint {
        if let p = table[id] { return p }
        let a = Double(index) / Double(max(count, 1)) * 2 * .pi
        return CGPoint(x: 0.5 + 0.34 * cos(a), y: 0.55 + 0.34 * sin(a))
    }

    /// Изгиб тропы: точка-ручка сбоку от прямой, у соседних мест в разные стороны.
    static func bend(_ to: CGPoint, index: Int) -> CGPoint {
        let mid = CGPoint(x: (yard.x + to.x) / 2, y: (yard.y + to.y) / 2)
        let dx = to.x - yard.x, dy = to.y - yard.y
        let s: CGFloat = index.isMultiple(of: 2) ? 0.18 : -0.18
        return CGPoint(x: mid.x - dy * s, y: mid.y + dx * s)
    }

    /// Точка на тропе (квадратичная кривая двор → место), t от 0 до 1.
    static func along(_ to: CGPoint, index: Int, t: Double) -> CGPoint {
        let c = bend(to, index: index)
        let u = 1 - t
        return CGPoint(x: u * u * yard.x + 2 * u * t * c.x + t * t * to.x,
                       y: u * u * yard.y + 2 * u * t * c.y + t * t * to.y)
    }
}

/// Бумажная карта: бумага с заломами, пунктир от двора к каждому месту, точки-кнопки, точка пса в походе.
struct PaperMap: View {
    let cards: [PlaceCard]
    let trip: ActiveTrip?
    let now: Double
    let onTap: (String) -> Void

    private static let paper = Color(hex: 0xfff6d8)
    private static let ink = Color(hex: 0x7a5b3a)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { ctx, size in draw(&ctx, size) }
                    .accessibilityHidden(true)
                yardMark
                    .position(px(MapSpots.yard, size))
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                    PlacePin(card: c, here: trip?.place == c.id) { onTap(c.id) }
                        .position(px(MapSpots.spot(c.id, index: i, count: cards.count), size))
                }
                if let trip, let i = cards.firstIndex(where: { $0.id == trip.place }) {
                    let to = MapSpots.spot(trip.place, index: i, count: cards.count)
                    let t = Places.trail(trip, now: now)
                    DogDot()
                        .position(px(MapSpots.along(to, index: i, t: t), size))
                        .animation(.linear(duration: 1), value: t)
                }
            }
        }
        .aspectRatio(0.82, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
        // Бумага всегда светлая — и в тёмной теме.
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.paper")
    }

    private func px(_ p: CGPoint, _ size: CGSize) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .color(Self.paper))
        // Заломы: карту складывали втрое по ширине и пополам по высоте — тень с одной стороны, блик с другой.
        for x in [size.width / 3, size.width * 2 / 3] {
            ctx.fill(Path(CGRect(x: x - 10, y: 0, width: 10, height: size.height)),
                     with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.05)]),
                                           startPoint: CGPoint(x: x - 10, y: 0), endPoint: CGPoint(x: x, y: 0)))
            ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                       with: .color(.black.opacity(0.08)), lineWidth: 1)
            ctx.stroke(Path { $0.move(to: CGPoint(x: x + 1, y: 0)); $0.addLine(to: CGPoint(x: x + 1, y: size.height)) },
                       with: .color(.white.opacity(0.6)), lineWidth: 1)
        }
        let y = size.height / 2
        ctx.fill(Path(CGRect(x: 0, y: y - 8, width: size.width, height: 8)),
                 with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.05)]),
                                       startPoint: CGPoint(x: 0, y: y - 8), endPoint: CGPoint(x: 0, y: y)))
        ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                   with: .color(.black.opacity(0.08)), lineWidth: 1)
        // Потёртые края.
        ctx.stroke(Path(rect.insetBy(dx: 3, dy: 3)), with: .color(Self.ink.opacity(0.18)), lineWidth: 1.5)
        // Тропы: пунктир от двора. К закрытым — бледный и тоньше.
        let yard = px(MapSpots.yard, size)
        for (i, c) in cards.enumerated() {
            let to = MapSpots.spot(c.id, index: i, count: cards.count)
            var path = Path()
            path.move(to: yard)
            path.addQuadCurve(to: px(to, size), control: px(MapSpots.bend(to, index: i), size))
            let on = trip?.place == c.id
            ctx.stroke(path, with: .color(Self.ink.opacity(c.open ? (on ? 0.85 : 0.55) : 0.2)),
                       style: StrokeStyle(lineWidth: on ? 3 : (c.open ? 2.2 : 1.5), lineCap: .round, dash: [6, 6]))
        }
        // Роза ветров в углу — для вида карты.
        let r = min(size.width, size.height) * 0.06
        let o = CGPoint(x: size.width - r - 14, y: size.height - r - 14)
        var rose = Path()
        rose.move(to: CGPoint(x: o.x, y: o.y - r)); rose.addLine(to: CGPoint(x: o.x + r * 0.3, y: o.y))
        rose.addLine(to: CGPoint(x: o.x, y: o.y + r)); rose.addLine(to: CGPoint(x: o.x - r * 0.3, y: o.y))
        rose.closeSubpath()
        ctx.fill(rose, with: .color(Self.ink.opacity(0.25)))
        ctx.draw(Text("С").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(Self.ink.opacity(0.5)),
                 at: CGPoint(x: o.x, y: o.y - r - 8))
    }

    /// Двор: домик и подпись.
    private var yardMark: some View {
        VStack(spacing: 2) {
            Image(systemName: "house.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PetPalette.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.85)))
                .overlay(Circle().stroke(Self.ink.opacity(0.5), lineWidth: 1.5))
            Text("Двор")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Self.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Двор, дом"))
    }
}

/// Место на карте: значок в кружке и подпись. Закрытое — серый силуэт, замок и «ур. N». Место дня — ★.
struct PlacePin: View {
    let card: PlaceCard
    /// Пёс сейчас здесь (в походе сюда).
    var here = false
    let onTap: () -> Void

    private static let ink = Color(hex: 0x7a5b3a)

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(card.emoji)
                    .font(.system(size: 24))
                    .grayscale(card.open ? 0 : 1)
                    .opacity(card.open ? 1 : 0.35)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(card.open ? Color.white.opacity(0.9) : Color.black.opacity(0.06)))
                    .overlay(Circle().stroke(here ? PetPalette.accent : Self.ink.opacity(card.open ? 0.55 : 0.2),
                                             lineWidth: here ? 3 : 1.5))
                    .overlay(alignment: .bottomTrailing) {
                        if !card.open {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(Color.gray))
                                .offset(x: 3, y: 3)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if card.star {
                            Text("★")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(PetPalette.yellow)
                                .shadow(color: Self.ink.opacity(0.6), radius: 0.5)
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(card.open ? card.name : "ур. \(Places.place(card.id)?.level ?? 0)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(card.open ? Self.ink : Color.gray)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 84)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(card.open ? card.name : "Закрытое место"))
        .accessibilityValue(Text((card.star ? "Место дня. " : "") + card.line))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("map.place.\(card.id)")
    }
}

/// Пёс на тропе.
struct DogDot: View {
    var body: some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(PetPalette.accent))
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Шиба в пути"))
            .accessibilityIdentifier("map.dog")
    }
}

// MARK: - Карточка места

/// Лист места: описание, сколько идти, находки (известные — цветные, неизвестные — «?»), «Пойти» и почему нельзя.
/// У Колодца эха — «Бросить монетку». Карточку берёт свежую из модели: после монетки и похода всё обновляется.
struct PlaceSheet: View {
    @Environment(AppModel.self) private var model
    let id: String
    let onGo: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            if let f = model.file, let p = Places.place(id) {
                let now = model.snap.t
                let lvl = model.placeLevel
                let card = Places.cards(f, dogLevel: lvl, growthX: model.placeTimeX, now: now).first { $0.id == id }
                content(f, p, card, lvl: lvl, now: now)
                    .padding(20)
            }
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.card")
    }

    @ViewBuilder
    private func content(_ f: SaveFile, _ p: Place, _ card: PlaceCard?, lvl: Int, now: Double) -> some View {
        let open = card?.open ?? false
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(p.emoji)
                    .font(.system(size: 34))
                    .grayscale(open ? 0 : 1)
                    .opacity(open ? 1 : 0.4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(open ? p.name : "Закрытое место")
                        .petFont(22, .bold)
                        .foregroundStyle(PetPalette.ink)
                        .accessibilityAddTraits(.isHeader)
                    if card?.star == true {
                        Text("★ Место дня — редкие находки чаще")
                            .petFont(13, .bold)
                            .foregroundStyle(PetPalette.accent)
                    }
                }
                Spacer()
                SheetCloseButton(id: "map.card.close")
            }
            if open {
                Text(p.about)
                    .petFont(15, .medium)
                    .foregroundStyle(PetPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Places.lockText(p))
                    .petFont(15, .semibold)
                    .foregroundStyle(PetPalette.soft)
            }
            HStack(spacing: 8) {
                chip("clock", "≈ \(Places.durationText(card?.minutes ?? p.minutes))", id: "map.card.time")
                chip("square.grid.3x3.fill", "\(card?.have ?? 0)/\(card?.total ?? p.finds.count)", id: "map.card.count")
                if let v = card?.visits, v > 0 { chip("figure.walk", "был \(v)", id: "map.card.visits") }
            }
            findsGrid(f, p, open: open)
            if open {
                goButton(f, lvl: lvl, now: now)
                if p.id == PlacesConfig.shared.wellPlace { wellButton(f, lvl: lvl, now: now) }
                // Волна 35 L: эксклюзив места за клочки — SinksViews.swift.
                PlaceExclusiveButton(file: f, place: p)
            }
        }
    }

    private func chip(_ icon: String, _ text: String, id: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).accessibilityHidden(true)
            Text(text).petFont(13, .bold).monospacedDigit()
        }
        .foregroundStyle(PetPalette.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(PetPalette.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func findsGrid(_ f: SaveFile, _ p: Place, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Находки")
                .petFont(16, .bold)
                .foregroundStyle(PetPalette.ink)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Places.albumRow(f, p), id: \.find.id) { row in
                    FindCell(find: row.find, count: row.count)
                }
            }
        }
    }

    private func goButton(_ f: SaveFile, lvl: Int, now: Double) -> some View {
        let block = Places.goBlock(id, f, dogLevel: lvl, now: now)
        let walking = Places.walking(f, now: now)
        let reason: String? = block.map { (b: String) -> String in
            guard let a = walking, a.place == id else { return b }
            return "Он сейчас здесь, \(Places.backText(a, tzOffsetMin: f.owner.tzOffsetMin, now: now))"
        }
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if let block { model.refuse(block) } else { onGo() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk").accessibilityHidden(true)
                    Text("Пойти").petFont(17, .bold)
                }
                .foregroundStyle(block == nil ? Color.white : PetPalette.ink.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Capsule())
            }
            .buttonStyle(SquishStyle())
            .glassEffect(block == nil ? .regular.tint(ActTint.color("walk").opacity(0.88)).interactive()
                         : .regular.interactive(), in: Capsule())
            .accessibilityLabel(Text("Пойти"))
            .accessibilityValue(Text(block ?? ""))
            .accessibilityIdentifier("map.go")
            if let reason {
                Text(reason)
                    .petFont(13, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("map.go.reason")
            }
        }
    }

    private func wellButton(_ f: SaveFile, lvl: Int, now: Double) -> some View {
        let why = Places.wishRefusal(f, dogLevel: lvl, now: now).map { Places.refusalText($0) }
        let coins = PlacesConfig.shared.wellCoins
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if let why { model.refuse(why) } else { model.throwCoin() }
            } label: {
                Text("Бросить монетку · \(coins) 🪙")
                    .petFont(16, .bold)
                    .foregroundStyle(PetPalette.ink.opacity(why == nil ? 1 : 0.55))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Capsule())
            }
            .buttonStyle(SquishStyle())
            .glassEffect(.regular.interactive(), in: Capsule())
            .accessibilityValue(Text(why ?? "Раз в сутки"))
            .accessibilityIdentifier("map.well")
            Text(why ?? "Раз в сутки. Эхо иногда отвечает монетами.")
                .petFont(13, .medium)
                .foregroundStyle(PetPalette.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Находка места: известная — значок, имя и редкость на цветном; неизвестная — «?» и только редкость.
struct FindCell: View {
    let find: PlaceFind
    let count: Int

    static func tint(_ t: FindTier) -> Color {
        switch t {
        case .common: return PetPalette.green
        case .rare: return Color(hex: 0x5b9bd5)
        case .veryRare: return Color(hex: 0xa974d6)
        }
    }

    var body: some View {
        let known = count > 0
        VStack(spacing: 3) {
            Text(known ? find.emoji : "?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.soft)
                .frame(height: 32)
            Text(known ? find.name : "???")
                .petFont(11, .bold)
                .foregroundStyle(known ? PetPalette.ink : PetPalette.soft)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            Text(find.tier.title + (count > 1 ? " · ×\(count)" : ""))
                .petFont(10, .medium)
                .foregroundStyle(known ? Self.tint(find.tier) : PetPalette.soft.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(known ? Self.tint(find.tier).opacity(0.18) : PetPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(known ? Self.tint(find.tier).opacity(0.6) : PetPalette.soft.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1.5, dash: known ? [] : [4, 3])))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(known ? "\(find.name), \(find.tier.title)" : "Ещё не найдено, \(find.tier.title)"))
    }
}

// MARK: - «Места» в альбоме

/// Раздел альбома: по месту — значки находок (неизвестные «?»), редкость цветом, счёт «3/6». Закрытые места без
/// находок не показываем — только сколько их ещё. Id — album.places.
struct PlacesSection: View {
    let f: SaveFile
    let level: Int

    var body: some View {
        let places = PlacesConfig.shared.places
        let shown = places.filter { Places.isOpen($0, dogLevel: level) || Places.have(f, $0) > 0 }
        let have = places.reduce(0) { $0 + Places.have(f, $1) }
        let total = places.reduce(0) { $0 + $1.finds.count }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Места")
                    .petFont(18, .bold)
                    .foregroundStyle(PetPalette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("Найдено \(have) из \(total)")
                    .petFont(13, .medium)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
            }
            if shown.isEmpty {
                Text("Места откроются со 2 уровня — тогда «Гулять» откроет карту, и он будет ходить в походы.")
                    .petFont(13, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                legend
            }
            ForEach(shown) { p in row(p) }
            if shown.count < places.count && !shown.isEmpty {
                Text("Ещё закрыто мест: \(places.count - shown.count). Растёт уровень — открываются новые.")
                    .petFont(12, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("album.places")
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(FindTier.allCases, id: \.self) { t in
                HStack(spacing: 4) {
                    Circle().fill(FindCell.tint(t)).frame(width: 8, height: 8)
                    Text(t.title).petFont(11, .medium).foregroundStyle(PetPalette.soft)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func row(_ p: Place) -> some View {
        let finds = Places.albumRow(f, p)
        let have = finds.filter { $0.count > 0 }.count
        let known = finds.filter { $0.count > 0 }.map { "\($0.find.name), \($0.find.tier.title)" }
        return HStack(spacing: 10) {
            Text(p.emoji).font(.system(size: 24)).frame(width: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(p.name)
                    .petFont(15, .semibold)
                    .foregroundStyle(PetPalette.ink)
                HStack(spacing: 4) {
                    ForEach(finds, id: \.find.id) { x in
                        FindDot(find: x.find, known: x.count > 0)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("\(have)/\(finds.count)")
                .petFont(13, .bold)
                .monospacedDigit()
                .foregroundStyle(have >= finds.count ? PetPalette.green : PetPalette.soft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(p.name): найдено \(have) из \(finds.count)"))
        .accessibilityValue(Text(known.joined(separator: "; ")))
    }
}

/// Кружок находки в строке места: известная — значок на цвете редкости, неизвестная — «?».
struct FindDot: View {
    let find: PlaceFind
    let known: Bool

    var body: some View {
        let tint = FindCell.tint(find.tier)
        Text(known ? find.emoji : "?")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(PetPalette.soft)
            .frame(width: 24, height: 24)
            .background(Circle().fill(known ? tint.opacity(0.25) : PetPalette.bg))
            .overlay(Circle().stroke(tint.opacity(known ? 0.8 : 0.35), lineWidth: 1.2))
    }
}
