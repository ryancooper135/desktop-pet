// Волна 19: знакомство при первом запуске. Три карточки листаются пальцем или «Дальше», «Пропустить» —
// в любой момент. Текст — Onboarding (Shared), когда показывать — GuideCenter. Снова открыть — в настройках.

import SwiftUI
@preconcurrency import PetCore

struct IntroScreen: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void
    @State private var page = 0

    var body: some View {
        let pages = Onboarding.pages(name: model.snap.name)
        let last = page >= pages.count - 1
        VStack(spacing: 12) {
            HStack {
                Spacer()
                if !last {
                    Button("Пропустить") { onDone() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .tint(PetPalette.soft)
                        .accessibilityIdentifier("intro.skip")
                }
            }
            .frame(minHeight: 44)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, p in
                    IntroPageView(page: p).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { i in
                    Circle()
                        .fill(i == page ? PetPalette.accent : PetPalette.soft.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Карточка \(page + 1) из \(pages.count)"))

            Button {
                if last { onDone() } else { withAnimation(.snappy) { page += 1 } }
            } label: {
                Text(last ? "Понятно, поехали" : "Дальше").frame(maxWidth: .infinity, minHeight: 50)
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .buttonStyle(.borderedProminent)
            .tint(PetPalette.accent)
            .accessibilityIdentifier(last ? "intro.done" : "intro.next")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("intro.screen")
    }
}

/// Одна карточка: значок, заголовок, текст и строчки «значок — что это».
private struct IntroPageView: View {
    let page: IntroPage

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ThoughtBubble.symbol(page.icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(PetPalette.accent)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(PetPalette.card))
                    .padding(.top, 8)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(page.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(Presenter.typeset(page.text))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(page.rows) { row in
                        IntroRowView(row: row)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20).fill(PetPalette.card))
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("intro.page.\(page.id)")
    }
}

private struct IntroRowView: View {
    let row: IntroRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if row.icon.isEmpty {
                    Text(row.emoji).font(.system(size: 18))
                } else {
                    ThoughtBubble.symbol(row.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PetPalette.ink)
                }
            }
            .frame(width: 36, height: 36)
            .background(Circle().fill(PetPalette.soft.opacity(0.14)))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                Text(Presenter.typeset(row.text))
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
