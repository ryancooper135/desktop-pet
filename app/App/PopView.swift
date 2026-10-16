// Всплывашки «+N ❤» над сценой и пружинящий стиль кнопок.
// Pop живёт в AppModel.pops 0,9 с; слой рисует их поверх сцены в её координатах.

import SwiftUI

struct Pop: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let point: CGPoint

    init(text: String, point: CGPoint) {
        id = UUID()
        self.text = text
        self.point = point
    }
}

/// Одна всплывашка: поднимается на rise и гаснет за life секунд.
struct PopView: View {
    static let rise: CGFloat = 60
    static let life: Double = 0.9

    let pop: Pop
    @State private var up = false
    @State private var gone = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(pop.text)
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundStyle(PetPalette.red)
            .shadow(color: .white.opacity(0.8), radius: 2)
            .fixedSize()
            .scaleEffect(up || reduceMotion ? 1 : 0.6)
            .offset(y: up && !reduceMotion ? -Self.rise : 0)
            .opacity(gone ? 0 : 1)
            .position(pop.point)
            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            .onAppear {
                // Подъём быстрый в начале, угасание — к концу, чтобы цифру успели прочитать.
                withAnimation(.easeOut(duration: Self.life)) { up = true }
                withAnimation(.easeIn(duration: Self.life)) { gone = true }
            }
            .accessibilityHidden(true)
    }
}

/// Все всплывашки модели поверх сцены. Касаний не ловит.
struct PopLayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            ForEach(model.pops) { p in
                PopView(pop: p)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: model.pops)
        .allowsHitTesting(false)
    }
}

/// Кнопка пружинит при нажатии.
struct SquishStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}
