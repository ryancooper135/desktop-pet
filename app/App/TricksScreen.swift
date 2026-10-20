// Лист «Трюки» (волна 8): шесть команд в духе Nintendogs — «Сидеть», «Лежать», «Поклон», «Прыжок», «Отряхнись», «Голос».
// Карточка в строку: значок слева, справа команда, точки засчитанных удач (из 5), «Выучен» или замок «Сначала «…»».
// Нажал команду — лист уезжает, пёс пробует в комнате (AppModel.doTrick → сцена: клипы трюка или «Не понял…»).
// Логика — Tricks (Shared), тут только вид. Открывается круглой кнопкой с лапой в ряду над панелью и по pet://tricks.
// Решения (Вадим может поменять): сетка в два столбца из низких карточек — все шесть влезают в лист на пол-экрана;
// когда трюки нельзя (спит, гуляет…), лист всё равно открывается — с плашкой-причиной и серыми карточками.

import SwiftUI
@preconcurrency import PetCore

struct TricksScreen: View {
    @Environment(AppModel.self) private var model

    private static let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let rows = model.file.map { Tricks.rows($0) } ?? []
        let gate = model.file.map { Tricks.gate($0, at: model.snap.t) } ?? Tricks.loadingReason
        ScrollView {
            VStack(spacing: 14) {
                header(learned: rows.filter(\.learned).count, total: rows.count)
                if let gate {
                    GateBanner(reason: gate)
                }
                LazyVGrid(columns: Self.columns, spacing: 12) {
                    ForEach(rows) { r in
                        TrickCard(row: r, enabled: gate == nil && !r.locked) {
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

    private func header(learned: Int, total: Int) -> some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                SheetCloseButton(id: "tricks.close")
            }
            Text("Трюки")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
            Text("Выучено \(learned) из \(total) · повторяй, и запомнит")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalette.soft)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("tricks.count")
        }
    }
}

/// Плашка «почему сейчас нельзя» над карточками.
private struct GateBanner: View {
    let reason: String

    private var icon: String {
        switch reason {
        case "asleep": return "moon.zzz.fill"
        case "away": return "figure.walk"
        case "bathing": return "bubbles.and.sparkles.fill"
        default: return "exclamationmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            Text(Tricks.reasonText(reason))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(PetPalette.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.soft.opacity(0.14)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tricks.gate")
    }
}

/// Карточка одной команды. Вся карточка — кнопка; закрытая или «нельзя сейчас» — серая и не нажимается.
struct TrickCard: View {
    let row: TrickRow
    let enabled: Bool
    let action: () -> Void

    private var status: String {
        if row.learned { return "Выучен" }
        if row.locked, let p = row.trick.previous { return "Сначала «\(p.title)»" }
        return "\(row.progress) из \(Tricks.needed)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: row.locked ? "lock.fill" : row.trick.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(row.locked ? PetPalette.soft : PetPalette.accent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill((row.locked ? PetPalette.soft : PetPalette.accent).opacity(0.16)))
                    if row.learned {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(PetPalette.green)
                            .background(Circle().fill(PetPalette.card))
                            .offset(x: 5, y: -4)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.trick.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    LevelPips(level: row.progress, top: Tricks.needed)
                    Text(status)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(row.learned ? PetPalette.green : PetPalette.soft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(SquishStyle())
        .disabled(!enabled)
        .deniedTap(when: !enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.trick.title))
        .accessibilityValue(Text(row.locked ? Tricks.reasonText(Tricks.lockedReason, for: row.trick) : status))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("trick.\(row.trick.rawValue)")
    }
}

/// Кнопка «Трюки» в ряду над панелью, рядом с «Домом»: только значок. Когда трюки нельзя — серая,
/// но нажимается: тост с причиной, кнопка качается (как «Гулять»). Id — open.tricks.
struct TricksButton: View {
    @Environment(AppModel.self) private var model
    /// Tricks.gate на момент снимка; nil — можно.
    let gate: String?
    @State private var taps = 0
    @State private var refusals = 0

    private static let shake: [CGFloat] = [0, -6, 6, -3, 0]

    var body: some View {
        Button {
            taps += 1
            if let gate {
                refusals += 1
                model.refuse(Tricks.reasonText(gate))
            } else {
                model.showTricks = true
            }
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
        .phaseAnimator(Self.shake, trigger: refusals, content: { view, x in
            view.offset(x: x)
        }, animation: { _ in
            .linear(duration: 0.06)
        })
        .accessibilityLabel(Text("Трюки"))
        .accessibilityValue(Text(gate.map { Tricks.reasonText($0) } ?? ""))
        .accessibilityHint(Text("Команды и чему научился"))
        .accessibilityIdentifier("open.tricks")
    }
}
