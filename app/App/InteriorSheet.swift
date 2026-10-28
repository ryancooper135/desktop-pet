// Волна 41 G: лист «Интерьер» из «Дома» — обои, пол и ковёр в комнате щенка. Первый вариант каждой части —
// бесплатный и прежний, остальные за монеты, по одному-два эксклюзива за клочки ✂️. Только для красоты:
// доход и экономику не трогает. Логика, цены и тексты — Interior (Shared/Interior.swift), тут только вид.
// Как в Мастерской: без денег кнопка не гаснет — пишет «Не хватает N», нажатие объясняет отказ строкой сверху.

import SwiftUI
@preconcurrency import PetCore

struct InteriorSheet: View {
    @Environment(AppModel.self) private var model

    @State private var refusal: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                if let refusal {
                    Text(refusal)
                        .petFont(14, .semibold)
                        .foregroundStyle(PetPalette.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                        .accessibilityIdentifier("interior.refusal")
                }
                ForEach(InteriorPart.allCases, id: \.self) { part in
                    section(part)
                }
                Text(InteriorText.ui("interior_note"))
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
        .accessibilityIdentifier("interior.screen")
    }

    // MARK: части

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                SheetCloseButton(id: "interior.close")
            }
            Text(InteriorText.ui("interior_title"))
                .petFont(22, .bold)
                .foregroundStyle(PetPalette.ink)
                .accessibilityAddTraits(.isHeader)
            if let w = model.file?.econ.wallet {
                Text("🪙 \(w.coins)   ✂️ \(w.shards)")
                    .petFont(15, .semibold)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
                    .accessibilityLabel(Text("\(EconText.coins(w.coins)), \(EconText.shards(w.shards))"))
                    .accessibilityIdentifier("interior.wallet")
            }
        }
    }

    private func section(_ part: InteriorPart) -> some View {
        let offers = model.file.map { Interior.offers($0, part) } ?? []
        return VStack(spacing: 8) {
            Text(InteriorText.partName(part))
                .petFont(17, .bold)
                .foregroundStyle(PetPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            ForEach(offers) { card($0) }
        }
        .padding(.top, 6)
    }

    private func card(_ o: InteriorOffer) -> some View {
        let chosen = o.state == .chosen
        return AXRow {
            HStack(spacing: 12) {
                InteriorSwatch(look: o.style.look)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(chosen ? PetPalette.accent : PetPalette.soft.opacity(0.25),
                                      lineWidth: chosen ? 2 : 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.style.name)
                        .petFont(16, .semibold)
                        .foregroundStyle(PetPalette.ink)
                        .axLines(2)
                        .minimumScaleFactor(0.8)
                    if o.style.isExclusive {
                        Text(InteriorText.ui("interior_exclusive"))
                            .petFont(12, .bold)
                            .foregroundStyle(PetPalette.accent)
                    } else if o.style.isFree {
                        Text(InteriorText.ui("interior_free"))
                            .petFont(12, .bold)
                            .foregroundStyle(PetPalette.green)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("interior.offer.\(o.id)")
            takeButton(o)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
    }

    /// «Поставить» и «N 🪙» — залитые акцентом; «Не хватает N» — обводка; «Стоит» — серая надпись.
    private func takeButton(_ o: InteriorOffer) -> some View {
        let done = o.state == .chosen
        let canTake: Bool = {
            switch o.state {
            case .chosen: return false
            case .owned: return true
            case .buy(let need): return need == 0
            }
        }()
        return Button {
            guard !done else { return }
            switch o.state {
            case .buy: refusal = model.buyInterior(o.id)
            case .owned: refusal = model.chooseInterior(o.id)
            case .chosen: break
            }
        } label: {
            Text(InteriorText.button(o))
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
        .accessibilityLabel(Text(label(o)))
        .accessibilityIdentifier("interior.take.\(o.id)")
    }

    private func label(_ o: InteriorOffer) -> String {
        switch o.state {
        case .chosen, .owned: return "\(InteriorText.button(o)): \(o.style.name)"
        case .buy(let need):
            if need > 0 { return InteriorText.button(o) }
            let price = o.style.currency == .shards ? EconText.shards(o.price) : EconText.coins(o.price)
            return "Купить «\(o.style.name)» за \(price)"
        }
    }
}

/// Образец варианта — тот же узор, что ляжет в комнату (InteriorArt), в квадратике: кусок стены 0,6 м,
/// кусок пола 1,2 м, ковёр сверху целиком. Плоские цвета, без картинок.
struct InteriorSwatch: View {
    let look: InteriorLook

    var body: some View {
        Canvas { ctx, size in
            switch look {
            case .walls(let w): drawWall(w, ctx, size)
            case .floor(let f): drawFloor(f, ctx, size)
            case .rug(let r): drawRug(r, ctx, size)
            }
        }
    }

    private func drawWall(_ w: WallLook, _ ctx: GraphicsContext, _ size: CGSize) {
        let span: Float = 0.6
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: w.base)))
        let k = size.width / CGFloat(span)
        // Низ стены — внизу образца: панель и рейка видны там же, где в комнате.
        for s in InteriorArt.wallShapes(w, width: span, height: span) {
            var p = Path()
            for (i, v) in s.rim.enumerated() {
                let pt = CGPoint(x: CGFloat(v.x) * k, y: size.height - CGFloat(v.y) * k)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            ctx.fill(p, with: .color(Color(hex: s.color)))
        }
    }

    private func drawFloor(_ f: FloorLook, _ ctx: GraphicsContext, _ size: CGSize) {
        let span: Float = 1.2, n = 48
        let cell = size.width / CGFloat(n)
        for row in 0..<n {
            for col in 0..<n {
                let u = (Float(col) + 0.5) / Float(n) * span
                let v = (Float(row) + 0.5) / Float(n) * span
                let r = CGRect(x: CGFloat(col) * cell, y: size.height - CGFloat(row + 1) * cell,
                               width: cell + 0.5, height: cell + 0.5)
                ctx.fill(Path(r), with: .color(Color(hex: InteriorArt.floorColor(f, u: u, v: v))))
            }
        }
    }

    private func drawRug(_ r: RugLook, _ ctx: GraphicsContext, _ size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: RoomColors.checkerLight)))
        let k = size.width / 1.0          // метр в образце: ковёр 0,9 м по кругу
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        for p in InteriorArt.rugPieces(r).sorted(by: { $0.top < $1.top }) {
            let c = CGPoint(x: mid.x + CGFloat(p.x) * k, y: mid.y + CGFloat(p.z) * k)
            let hx = CGFloat(p.halfX) * k, hz = CGFloat(p.halfZ) * k
            let rect = CGRect(x: c.x - hx, y: c.y - hz, width: hx * 2, height: hz * 2)
            let path: Path
            switch p.shape {
            case .box: path = Path(rect)
            case .disc, .ellipse: path = Path(ellipseIn: rect)
            }
            ctx.fill(path, with: .color(Color(hex: p.color)))
        }
    }
}

/// «Обои, пол и ковёр» вверху «Дома» — вход в лист InteriorSheet (тот же вид, что вход в Кухню).
struct InteriorEntry: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "paintbrush.fill")
                    .accessibilityHidden(true)
                Text(InteriorText.ui("interior_open"))
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
        .accessibilityIdentifier("house.interior.open")
    }
}
