// Всплывашки «+N ❤» над сценой и пружинящий стиль кнопок.
// Pop живёт в AppModel.pops 0,9 с; слой рисует их поверх сцены в её координатах.

import SwiftUI

struct Pop: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let point: CGPoint
    /// SF Symbol вместо (или после) текста: сердечко ласки рисуется символом, а не эмодзи.
    let symbol: String?

    init(text: String, point: CGPoint, symbol: String? = nil) {
        id = UUID()
        self.text = text
        self.point = point
        self.symbol = symbol
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

    /// Текст и символ одной строкой; символ красится тем же цветом, что и цифра.
    private var label: Text {
        guard let symbol = pop.symbol else { return Text(pop.text) }
        let icon = Image(systemName: symbol)
        return pop.text.isEmpty ? Text(icon) : Text("\(pop.text) \(icon)")
    }

    var body: some View {
        label
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundStyle(PetPalette.red)
            .shadow(color: .white.opacity(0.8), radius: 2)
            .fixedSize()
            .scaleEffect(up || reduceMotion ? 1 : 0.6)
            .offset(y: up && !reduceMotion ? -Self.rise : 0)
            .opacity(gone ? 0 : 1)
            .position(pop.point)
            // Только прозрачность: после .position вид во весь слой, .scale тянул бы цифру из центра экрана.
            .transition(.opacity)
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
