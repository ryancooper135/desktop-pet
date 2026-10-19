// Волна 11: плоская иконка предмета стиля A — слои ItemArt (Shared/ItemArt.swift) в Canvas, без ассетов.
// Одна и та же в коллекции, в капсуле и в лавке. Своей иконки нет — эмодзи из ItemCatalog.

import SwiftUI

struct ItemIcon: View {
    let id: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let layers = ItemArt.layers(id) {
                Canvas { ctx, sz in
                    let s = min(sz.width, sz.height)
                    let dx = (sz.width - s) / 2, dy = (sz.height - s) / 2
                    for l in layers {
                        ctx.fill(Self.path(l.shape, scale: s, dx: dx, dy: dy), with: .color(Color(hex: l.color)))
                    }
                }
            } else {
                Text(ItemCatalog.emoji(id))
                    .font(.system(size: size * 0.7))
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Фигура слоя в точках рамки: единичный квадрат → s×s со сдвигом к центру.
    static func path(_ shape: ArtShape, scale s: CGFloat, dx: CGFloat, dy: CGFloat) -> Path {
        func pt(_ v: SIMD2<Double>) -> CGPoint { CGPoint(x: dx + CGFloat(v.x) * s, y: dy + CGFloat(v.y) * s) }
        switch shape {
        case .poly(let pts):
            var p = Path()
            guard let first = pts.first else { return p }
            p.move(to: pt(first))
            for v in pts.dropFirst() { p.addLine(to: pt(v)) }
            p.closeSubpath()
            return p
        case .circle(let c, let r):
            let o = pt(c - r)
            return Path(ellipseIn: CGRect(x: o.x, y: o.y, width: CGFloat(r * 2) * s, height: CGFloat(r * 2) * s))
        case .ellipse(let c, let rx, let ry):
            let o = pt(c - SIMD2(rx, ry))
            return Path(ellipseIn: CGRect(x: o.x, y: o.y, width: CGFloat(rx * 2) * s, height: CGFloat(ry * 2) * s))
        case .rect(let x, let y, let w, let h, let corner):
            let o = pt(SIMD2(x, y))
            let r = CGRect(x: o.x, y: o.y, width: CGFloat(w) * s, height: CGFloat(h) * s)
            return corner > 0 ? Path(roundedRect: r, cornerRadius: CGFloat(corner) * s, style: .continuous) : Path(r)
        }
    }
}

#if DEBUG
#Preview("Иконки предметов") {
    let ids = ItemArt.table.keys.sorted()
    return ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
            ForEach(ids, id: \.self) { id in
                VStack(spacing: 4) {
                    ItemIcon(id: id, size: 52)
                    Text(id).font(.system(size: 9)).lineLimit(1)
                }
            }
        }
        .padding()
    }
}
#endif
