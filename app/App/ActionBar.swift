// Нижняя панель действий главного экрана: ActionBar, кнопка ActButton и бейдж ActBadge.
// Перенесено из HomeScreen.swift без изменений (волна 28).
// Волна 53 «B · Стекло», вариант 1: полупрозрачная стеклянная полоса над таб-баром; в ней цветные круги 54 pt,
// под кругом слово и что даёт нажатие («+сытость», HomeLook.actReward), а когда нельзя — причина значком («⏱ 2 мин»).

import SwiftUI
import UIKit
@preconcurrency import PetCore

/// Нижняя панель действий. Кнопка, которая сейчас откажет, бесцветная, но нажимается и объясняет причину тостом.
/// Волна 18: активные — цветные, неактивные — бесцветные с причиной. Волна 53: причина — строкой под словом.
/// Все кнопки одной ширины, подписи одним кеглем: кегль подбирается по самой длинной подписи, а не каждой отдельно.
struct ActionBar: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot

    static let spacing: CGFloat = 8
    /// На узком ряду (6 кнопок на iPhone SE) зазор ужимается, чтобы подписи не падали ниже читаемого.
    static let tightSpacing: CGFloat = 4
    /// Ниже этого кегля при обычном зазоре переходим на узкий.
    static let comfortLabel: CGFloat = 10
    /// Поля стеклянной полосы вокруг ряда кругов.
    static let stripInset: CGFloat = 8
    /// Базовый кегль подписи, растёт вместе с Dynamic Type; сверху его ограничивает ширина ячейки.
    @ScaledMetric(relativeTo: .caption) private var baseLabel: CGFloat = 13
    @State private var width: CGFloat = 0

    private var bathing: Bool { snap.main == .none }
    /// Гуляет: дома никого, ядро откажет всем кнопкам («Гуляет, скоро вернётся»).
    private var away: Bool { snap.pose == .away }

    var body: some View {
        let nap = snap.pose == .nap
        let lamp = Self.lampTime(Clock.now())
        let titles = Self.titles(nap: nap, lamp: lamp)
        let fit = Self.fit(titles: titles, total: width, maxSize: baseLabel)
        let cell = fit.cell
        let label = fit.label
        // Волна 18: почему кнопка сейчас не сработает — «3 мин», «спит», «моется» прямо под кнопкой.
        let g = model.file.map { NeedHints.gates($0, at: snap.t) } ?? [:]
        HStack(spacing: fit.spacing) {
            if nap {
                ActButton(title: "Разбудить", icon: "sun.max.fill", kind: "wake", dim: false, labelSize: label) { model.act(.wake) }
                    .frame(width: cell > 0 ? cell : nil)
            }
            ActButton(title: "Покормить", icon: "fork.knife", kind: "feed", dim: bathing || away, gate: g["feed"] ?? .open, labelSize: label) { model.act(.feed(Catalog.mainFood)) }
                .frame(width: cell > 0 ? cell : nil)
            ActButton(title: "Погладить", icon: "hand.raised.fill", kind: "pet", dim: bathing || away, gate: g["pet"] ?? .open, labelSize: label) { model.act(.pet) }
                .frame(width: cell > 0 ? cell : nil)
            ActButton(title: "Поиграть", icon: "tennisball.fill", kind: "play", dim: bathing || away || snap.pose == .sleep, gate: g["play"] ?? .open, labelSize: label) { model.act(.play) }
                .frame(width: cell > 0 ? cell : nil)
            ActButton(title: "Помыть", icon: "bathtub.fill", kind: "bath", dim: bathing || away, gate: g["bath"] ?? .open, labelSize: label) { model.act(.bath) }
                .frame(width: cell > 0 ? cell : nil)
            if lamp {
                ActButton(title: "Отбой", icon: "lamp.desk.fill", kind: "bed", dim: false, labelSize: label) {
                    Feel.tap()
                    model.setBedtime(minute: Self.minuteNow(Clock.now()))
                }
                .frame(width: cell > 0 ? cell : nil)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { g in
                Color.clear.onChange(of: g.size.width, initial: true) { _, w in width = w }
            }
        }
        .padding(.horizontal, Self.stripInset)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .bGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    /// Подписи кнопок в порядке панели. Должны совпадать с ActButton в body.
    static func titles(nap: Bool, lamp: Bool) -> [String] {
        var t: [String] = []
        if nap { t.append("Разбудить") }
        t += ["Покормить", "Погладить", "Поиграть", "Помыть"]
        if lamp { t.append("Отбой") }
        return t
    }

    /// Ширина одной ячейки при равном делении панели; 0, пока ширина не измерена.
    static func cellWidth(total: CGFloat, count: Int, spacing: CGFloat = spacing) -> CGFloat {
        guard total > 0, count > 0 else { return 0 }
        return max(0, (total - spacing * CGFloat(count - 1)) / CGFloat(count))
    }

    /// Раскладка ряда: зазор, ширина ячейки и общий кегль. Обычный зазор, пока кегль не ниже comfortLabel;
    /// иначе узкий зазор и меньшие поля — так 6 кнопок на iPhone SE (375 pt) остаются читаемыми.
    /// Поля в узком ряду 7, а не 3–4: у ячейки ~74×56 скруглённые бока, и на высоте подписи
    /// внутри капсулы остаётся ~60 pt — с полями 4 «Покормить» упиралась в край (ui-63).
    static func fit(titles: [String], total: CGFloat, maxSize: CGFloat) -> (spacing: CGFloat, cell: CGFloat, label: CGFloat) {
        let cell = cellWidth(total: total, count: titles.count)
        let label = labelSize(titles: titles, cellWidth: cell, maxSize: maxSize)
        guard cell > 0, label < comfortLabel, maxSize > comfortLabel else { return (spacing, cell, label) }
        let tight = cellWidth(total: total, count: titles.count, spacing: tightSpacing)
        return (tightSpacing, tight, labelSize(titles: titles, cellWidth: tight, maxSize: maxSize, inset: 7))
    }

    /// Один кегль на все подписи: самый крупный (не больше maxSize), при котором самая длинная влезает в ячейку.
    /// inset — поля внутри капсулы с каждой стороны: 8, а не 5 — у капсулы скруглённые бока,
    /// и «Покормить» с полями 5 визуально упиралась в край на 5 кнопках. Пока ширина не известна, отдаёт maxSize.
    static func labelSize(titles: [String], cellWidth: CGFloat, maxSize: CGFloat,
                          minSize: CGFloat = 8, inset: CGFloat = 8) -> CGFloat {
        guard cellWidth > 0, !titles.isEmpty else { return maxSize }
        let room = cellWidth - inset * 2
        var size = maxSize
        while size > minSize {
            let widest = titles.map { labelWidth($0, size: size) }.max() ?? 0
            if widest <= room { return size }
            size -= 0.5
        }
        return minSize
    }

    /// Ширина подписи шрифтом кнопки (SF Rounded semibold) при данном кегле.
    static func labelWidth(_ text: String, size: CGFloat) -> CGFloat {
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Лампа видна с 20:00 до 02:00 по местному времени.
    static func lampTime(_ t: Double) -> Bool {
        let h = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: t))
        return h >= 20 || h < 2
    }

    static func minuteNow(_ t: Double) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t))
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// Кнопка панели: пружинит, иконка подпрыгивает на нажатие, при отказе ядра кнопка качается.
/// kind — вид действия ядра (PetAction.kind), id для UI-тестов — "act.<kind>".
struct ActButton: View {
    @Environment(AppModel.self) private var model
    let title: String
    let icon: String
    let kind: String
    let dim: Bool
    /// Волна 18: что скажет ядро (NeedHints.gate). Не ok — кнопка бесцветная, в углу бейдж причины.
    let gate: ActGate
    /// Кегль подписи: панель задаёт один на все кнопки.
    let labelSize: CGFloat
    let action: () -> Void

    @State private var taps = 0

    init(title: String, icon: String, kind: String, dim: Bool, gate: ActGate = .open, labelSize: CGFloat = 13,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.dim = dim
        self.gate = gate
        self.labelSize = labelSize
        self.action = action
    }

    /// Нажатие сейчас сработает.
    private var live: Bool { !dim && gate.ok }
    /// Бейдж причины: ядро сказало своё («3 мин», «спит») или вся панель погашена ванной/прогулкой.
    private var badge: String? { gate.badge ?? (dim ? "позже" : nil) }

    var body: some View {
        let tint = ActTint.color(kind)
        let note = live ? HomeLook.actReward(kind) : badge
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 4) {
                // Круг 54 pt: активный — цветной с белым значком, неактивный — бесцветный с приглушённым.
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolEffect(.bounce, value: taps)
                    .foregroundStyle(live ? AnyShapeStyle(Color.white) : AnyShapeStyle(PetPalette.ink.opacity(0.45)))
                    .frame(width: BMetrics.actCircle, height: BMetrics.actCircle)
                    .background {
                        Circle().fill(live
                            ? AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(PetPalette.ink.opacity(0.08)))
                    }
                    .shadow(color: live ? tint.opacity(0.35) : .clear, radius: 6, y: 3)
                    .frame(maxWidth: .infinity)
                Text(title)
                    .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.ink.opacity(live ? 1 : 0.55))
                    .lineLimit(1)
                    // Запас на погрешность замера и самый узкий экран: кегль уже подобран рядом,
                    // здесь только страховка от «Покор…», если замер разошёлся с отрисовкой.
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                // Что даёт нажатие или почему сейчас нельзя (значок часов/замка вместо фразы).
                HStack(spacing: 2) {
                    if !live, note != nil {
                        Image(systemName: gate.reason == "cooldown" ? "clock.fill" : "lock.fill")
                    }
                    Text(note ?? " ")
                }
                .font(.system(size: max(8, labelSize - 3), weight: .bold, design: .rounded))
                .foregroundStyle(live ? tint : PetPalette.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle())
        .coachHighlight(kind)
        .modifier(RefuseShake(trigger: model.refusals[kind, default: 0]))
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(live ? "" : badge.map { "недоступно, \($0)" } ?? "недоступно"))
        .accessibilityHint(Text(live ? (HomeLook.actReward(kind) ?? "") : ""))
        .accessibilityIdentifier("act.\(kind)")
    }
}

/// Бейдж причины над кнопкой панели: «⏱ 2 мин», «🔒 спит». Пусто, когда кнопка сработает.
struct ActBadge: View {
    let gate: ActGate
    let dim: Bool
    @ScaledMetric(relativeTo: .caption2) private var badgeSize: CGFloat = 10

    /// Что показать: ядро сказало своё («3 мин», «спит») или вся панель погашена ванной/прогулкой.
    static func text(_ gate: ActGate, dim: Bool) -> String? {
        guard dim || !gate.ok else { return nil }
        return gate.badge ?? (dim ? "позже" : nil)
    }

    var body: some View {
        if let badge = Self.text(gate, dim: dim) {
            HStack(spacing: 2) {
                Image(systemName: gate.reason == "cooldown" ? "clock.fill" : "lock.fill")
                Text(badge)
            }
            .font(.system(size: min(badgeSize, 13), weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(PetPalette.soft))
            .offset(y: -7)
            .accessibilityHidden(true)
        }
    }
}
