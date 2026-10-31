// Лист «Команды» (волна 57, вариант A из design/wave57): сетка 4×2 круглых иконок — «Сидеть», «Лапу», «Лежать»,
// «Голос», «Кружись», «Дай пять», «Притворись», «Ползи». Кольцо вокруг иконки — засчитанные удачи (3–5 до выучки),
// звёздочка — выучено, замок с цифрой — откроется с уровня пса. Без текста-простыни: иконка, кружок, значок.
// Нажал — лист уезжает, пёс пробует в комнате (AppModel.doTrick → сцена: клипы команды или «Не понял…»).
// Нельзя сейчас (спит, моется, гуляет) — лист всё равно открывается: иконки серые со значком причины.
// Голодный или грустный — значок миски/сердца: слушается хуже (Tricks.distracted).
// Логика — Tricks (Shared), тут только вид. Открывается круглой кнопкой с лапой над панелью и по pet://tricks.

import SwiftUI
@preconcurrency import PetCore

struct TricksScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var type

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: type.isAccessibilitySize ? 2 : 4)
    }

    var body: some View {
        let rows = model.file.map { Tricks.rows($0) } ?? []
        let gate = model.file.map { Tricks.gate($0, at: model.snap.t) } ?? Tricks.loadingReason
        let distracted = gate == nil ? model.file.flatMap { Tricks.distracted($0, at: model.snap.t) } : nil
        ScrollView {
            VStack(spacing: 18) {
                header(learned: rows.filter(\.learned).count, total: rows.count, gate: gate, distracted: distracted)
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(rows) { r in
                        TrickDisc(row: r, gate: gate, distracted: distracted) {
                            Feel.tap(.button)
                            model.doTrick(r.trick)
                        }
                    }
                }
                // Уход (волна 9): расчесать — тут же, под командами.
                BrushCard()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tricks.screen")
    }

    private func header(learned: Int, total: Int, gate: String?, distracted: Need?) -> some View {
        HStack(spacing: 8) {
            Text("Команды")
                .petFont(22, .bold)
                .foregroundStyle(PetPalette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let gate, let symbol = Tricks.gateSymbol(gate) {
                Chip(symbol: symbol, tint: PetPalette.soft, text: nil)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(Tricks.reasonText(gate)))
                    .accessibilityIdentifier("tricks.gate")
            } else if let distracted {
                Chip(symbol: TrickDisc.distractedSymbol(distracted), tint: PetPalette.accent, text: nil)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TrickDisc.distractedText(distracted)))
                    .accessibilityIdentifier("tricks.distracted")
            }
            Chip(symbol: "star.fill", tint: PetPalette.yellow, text: "\(learned)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Выучено \(learned) из \(total)"))
                .accessibilityIdentifier("tricks.count")
            SheetCloseButton(id: "tricks.close")
        }
    }
}

/// Плашка в шапке: значок и, если есть, число.
private struct Chip: View {
    let symbol: String
    let tint: Color
    let text: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            if let text {
                Text(text)
                    .foregroundStyle(PetPalette.ink)
            }
        }
        .petFont(15, .bold)
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Capsule().fill(PetPalette.card))
    }
}

/// Одна команда: круглая иконка с кольцом прогресса и значком в углу, под ней — слово.
/// Нельзя (замок, щенку рано, спит…) — серая и не нажимается; тап по серой — «не-а» (deniedTap).
struct TrickDisc: View {
    let row: TrickRow
    let gate: String?
    let distracted: Need?
    let action: () -> Void

    static let size: CGFloat = 64
    static let ring: CGFloat = 4

    static func distractedSymbol(_ n: Need) -> String { n == .food ? "fork.knife" : "heart.slash.fill" }
    static func distractedText(_ n: Need) -> String {
        n == .food ? "Голодный — слушается хуже" : "Грустит — слушается хуже"
    }

    private var enabled: Bool { gate == nil && !row.locked && !row.young }
    private var grey: Bool { !enabled }

    /// Что сказать VoiceOver: выучена, сколько из скольких или почему нельзя.
    private var status: String {
        if let gate { return Tricks.reasonText(gate) }
        if row.young { return Tricks.growText }
        if row.locked { return Tricks.reasonText(Tricks.lockedReason, for: row.trick) }
        if row.learned { return "Выучена" }
        return "\(row.progress) из \(row.needed)"
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                disc
                Text(row.trick.short)
                    .petFont(12, .bold)
                    .foregroundStyle(grey ? PetPalette.soft : PetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle())
        .disabled(!enabled)
        .deniedTap(when: !enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.trick.title))
        .accessibilityValue(Text(status))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("trick.\(row.trick.rawValue)")
    }

    private var disc: some View {
        let tint = grey ? PetPalette.soft : PetPalette.accent
        return ZStack {
            Circle()
                .stroke(PetPalette.soft.opacity(0.18), lineWidth: Self.ring)
            if !row.locked, !row.young {
                Circle()
                    .trim(from: 0, to: row.fraction)
                    .stroke(row.learned ? PetPalette.yellow : tint,
                            style: StrokeStyle(lineWidth: Self.ring, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: row.fraction)
            }
            Circle()
                .fill(row.learned && !grey ? PetPalette.accent.opacity(0.18) : PetPalette.card)
                .padding(Self.ring + 3)
            Image(systemName: row.trick.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: Self.size + 2 * Self.ring, height: Self.size + 2 * Self.ring)
        .opacity(grey ? 0.6 : 1)
        .overlay(alignment: .topTrailing) { badge.offset(x: 4, y: -2) }
    }

    /// Значок в углу: причина «нельзя» важнее всего, потом замок/«подрастёт», потом звезда или «рассеян».
    @ViewBuilder private var badge: some View {
        if let gate, let symbol = Tricks.gateSymbol(gate) {
            Badge(symbol: symbol, tint: PetPalette.soft)
        } else if row.young {
            Badge(symbol: "hourglass", tint: PetPalette.soft)
        } else if row.locked {
            Badge(symbol: "lock.fill", tint: PetPalette.soft, number: row.trick.level)
        } else if row.learned {
            Badge(symbol: "star.fill", tint: PetPalette.yellow)
        } else if let distracted {
            Badge(symbol: Self.distractedSymbol(distracted), tint: PetPalette.accent)
        }
    }
}

/// Маленький круглый значок (или капсула с цифрой уровня) поверх иконки команды.
private struct Badge: View {
    let symbol: String
    let tint: Color
    var number: Int?

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            if let number {
                Text("\(number)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, number == nil ? 0 : 5)
        .frame(minWidth: 22, minHeight: 22)
        .background(Capsule().fill(PetPalette.card).shadow(color: .black.opacity(0.12), radius: 2, y: 1))
        .accessibilityHidden(true)
    }
}

/// Кнопка «Команды» в ряду над панелью, рядом с «Домом»: только значок. Лист открывается всегда (волна 57):
/// когда нельзя (спит, гуляет…), там серые иконки со значком причины; сама кнопка тогда бледнее. Id — open.tricks.
struct TricksButton: View {
    @Environment(AppModel.self) private var model
    /// Tricks.gate на момент снимка; nil — можно.
    let gate: String?
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            model.showTricks = true
        } label: {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolEffect(.bounce, value: taps)
                .foregroundStyle(PetPalette.ink)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(SquishStyle())
        .opacity(gate == nil ? 1 : 0.55)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(Text("Команды"))
        .accessibilityValue(Text(gate.map { Tricks.reasonText($0) } ?? ""))
        .accessibilityHint(Text("Научить пса командам"))
        .accessibilityIdentifier("open.tricks")
    }
}
