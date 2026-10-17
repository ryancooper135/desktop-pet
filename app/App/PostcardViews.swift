// «Открытка дня» (волна 5): бумажная карточка в ретро-рамке и лист с решением «В альбом / Не надо».
// Кадр пока — мордочка PetFaceView в позе открытки и значок находки. Снимок 3D (Postcards.setImage) — потом.
// Решение (Вадим может поменять): открытка всегда светлая, как записка «Ушёл гулять», и чуть набок.

import SwiftUI
@preconcurrency import PetCore

/// Сама открытка: рамка, кадр, подпись, «17 октября · 14:20». compact — клетка альбома.
struct PostcardFace: View {
    let frame: PostcardFrame
    var compact: Bool = false

    private var paper: Color { Color(hex: 0xfff6d8) }

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(PetPalette.stageBg)
                PetFaceView(pose: frame.pose)
                    .padding(compact ? 10 : 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let find = frame.find {
                    Text(find.emoji)
                        .font(.system(size: compact ? 20 : 36))
                        .padding(compact ? 4 : 10)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(PetPalette.furDark.opacity(0.35), lineWidth: compact ? 1 : 2)
            }
            Text(frame.caption)
                .font(.system(size: compact ? 12 : 18, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 2 : 3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(frame.date) · \(frame.time)")
                .font(.system(size: compact ? 10 : 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PetPalette.soft)
        }
        .padding(compact ? 8 : 14)
        .padding(.bottom, compact ? 2 : 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(paper)
                .shadow(color: .black.opacity(0.15), radius: compact ? 3 : 8, y: compact ? 2 : 4)
        )
        // Ретро-рамка: двойная обводка по краю бумаги.
        .overlay {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(PetPalette.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .padding(compact ? 3 : 5)
        }
        // Бумага всегда светлая, текст на ней — тёмный и в тёмной теме.
        .environment(\.colorScheme, .light)
        .rotationEffect(.degrees(compact ? 0 : -1.5))
    }
}

/// Лист открытки. С главной — «В альбом» и «Не надо»; из альбома — «Удалить» с подтверждением.
struct PostcardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let card: Postcard
    var fromAlbum: Bool = false
    @State private var askRemove = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(fromAlbum ? "Открытка" : "Открытка дня")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                PostcardFace(frame: card.frame)
                    .padding(.horizontal, 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Открытка: \(card.caption), \(card.frame.date)"))
                if fromAlbum {
                    Button(role: .destructive) {
                        askRemove = true
                    } label: {
                        Label("Удалить", systemImage: "trash")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("postcard.remove")
                    .confirmationDialog("Удалить открытку из альбома?", isPresented: $askRemove, titleVisibility: .visible) {
                        Button("Удалить", role: .destructive) {
                            model.removePostcard(card)
                            dismiss()
                        }
                        Button("Оставить", role: .cancel) {}
                    }
                } else {
                    HStack(spacing: 12) {
                        Button {
                            model.discardPostcard(card)
                            dismiss()
                        } label: {
                            Text("Не надо")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(PetPalette.soft)
                        .accessibilityIdentifier("postcard.discard")
                        Button {
                            model.savePostcard(card)
                            dismiss()
                        } label: {
                            Label("В альбом", systemImage: "books.vertical.fill")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PetPalette.accent)
                        .accessibilityIdentifier("postcard.save")
                    }
                    Text("Не сохранишь — через неделю пропадёт.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                }
            }
            .padding(20)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("postcard.sheet")
    }
}
