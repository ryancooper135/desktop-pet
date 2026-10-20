// Слои главного экрана поверх сцены: палец-подсказка ласки, состояние жеста и карточка имени.
// Хаптика с волны 29 — Feel (App/FeelKit.swift), без слоя.
// Перенесено из HomeScreen.swift без изменений (волна 28).

import SwiftUI
import UIKit
@preconcurrency import PetCore

/// Палец-подсказка ласки (PetTutorOverlay) — отдельный вид: решение читает стор и сцену, а HomeScreen
/// перерисовывается на каждое движение пальца (lookX).
struct PetTutorLayer: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot

    var body: some View {
        // Волна 22: палец молчит под тостом и подсказкой жеста и пока идёт анимация действия (Hush).
        let show = Coach.shared.tutorShown(model, snap: snap)
        ZStack {
            if show {
                PetTutorOverlay(name: snap.name)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: show)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Изменяемое состояние жеста по сцене (не @Observable: экран его не читает).
final class TouchBox {
    var tracker = StrokeTracker()
    var start: CGPoint? = nil
}

/// Аватар, имя, сердечки и уровень. Непрозрачная плашка.
/// Критично (уровень 3+): красная обводка и значок тревоги у подписи — видно сразу, не путается с «голоден».
struct NameCard: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot
    /// Аватар своего персонажа (волна 14): avatar.png из пака или снимок морды. nil — мордочка Шибы.
    @State private var avatar: UIImage?
    @State private var avatarFor: String?

    private var critical: Bool { snap.alive && snap.level >= 3 }
    /// С меткой установки: пак переставили в ту же папку — ключ другой, старая картинка не показывается,
    /// аватар снимается заново без перезапуска (волна 15).
    private var avatarKey: String? { model.characterEntry.map { "\($0.id)|\($0.stamp)|\($0.folder.path)" } }
    private var shownAvatar: UIImage? { avatarKey != nil && avatarFor == avatarKey ? avatar : nil }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let img = shownAvatar {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(PetPalette.soft.opacity(0.18)))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(PetPalette.ink.opacity(0.12), lineWidth: 1))
                } else {
                    PetFaceView(pose: snap.pose)
                }
            }
            .frame(width: 40, height: 40)
            // Настроение читает сцена («Шиба спокоен»); здесь оно дало бы «Шиба спокоен, Шиба, …».
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(snap.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 13)
                HStack(spacing: 4) {
                    if critical {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                    }
                    Text(snap.levelTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(.system(size: 12, weight: critical ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(critical ? PetPalette.red : PetPalette.level(snap.level))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
        .overlay {
            if critical {
                RoundedRectangle(cornerRadius: 18).strokeBorder(PetPalette.red, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Долгое нажатие — шкалы"))
        // Снимок видно по идентификатору (ui-86): «name.card.avatar» — в шапке картинка своего персонажа.
        .accessibilityIdentifier(shownAvatar != nil ? "name.card.avatar" : "name.card")
        .task(id: avatarKey) {
            guard let entry = model.characterEntry, entry.ok, let key = avatarKey else { return }
            let img = await CharacterAvatar.image(for: entry)
            guard key == avatarKey else { return }
            avatar = img
            avatarFor = key
        }
    }
}
