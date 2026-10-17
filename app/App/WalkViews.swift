// Прогулка с находкой на главном экране: кнопка «Гулять», кнопка альбома, записка в пустой комнате и сам альбом.
// Где что стоит (решение, Вадим может поменять):
// • ряд над панелью действий: слева — «Альбом» со счётчиком находок, справа — «Гулять» с подписью-причиной;
//   в беде ряда нет (там большая «Спасти»), после смерти — тоже;
// • записка «Ушёл гулять, вернусь в 14:20» — бумажкой на месте Шибы, пока его нет;
// • альбом — шит, ещё открывается по pet://album.
// Можно ли гулять, решает ядро (WalkPlan.gate → PetEngine.act на копии), здесь только вид.

import SwiftUI
@preconcurrency import PetCore

// MARK: - Ряд «Альбом · Гулять»

struct WalkRow: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot

    var body: some View {
        let gate = model.file.map { WalkPlan.gate($0, at: snap.t) }
        HStack(spacing: 8) {
            AlbumButton(total: Finds.total(albumFinds(model.file, at: snap.t)))
            Spacer(minLength: 0)
            if let gate {
                WalkButton(gate: gate)
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(away ? "Гуляет" : "Гулять")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    if !gate.hint.isEmpty {
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

    var body: some View {
        Button {
            model.showAlbum = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("Альбом")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
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
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(SquishStyle())
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel(Text("Альбом находок"))
        .accessibilityValue(Text(total > 0 ? "Находок: \(total)" : "Пока пусто"))
        .accessibilityIdentifier("open.album")
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
                    Text(total == 0 ? "Пока пусто. Отпусти \(model.snap.name) погулять — принесёт что-нибудь."
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
            }
            .padding(20)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("album.sheet")
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
