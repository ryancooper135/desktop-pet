// Волна 34 G: вход во «Двор» с главного экрана. Шестой круг в ряд «Альбом · Автомат · Дом · Трюки · Игры»
// на iPhone Air (388 pt) не влезает рядом с «Гулять», поэтому двор — отдельный круг справа над рядом.
// Бейдж-точка: копилка полная или следующая плита по карману (YardText.badge).

import SwiftUI
@preconcurrency import PetCore

struct YardButton: View {
    @Environment(AppModel.self) private var model
    @State private var taps = 0

    var body: some View {
        let badge = model.yardBadge(now: model.snap.t)
        Button {
            taps += 1
            model.showYard = true
        } label: {
            Image(systemName: "tree.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolEffect(.bounce, value: taps)
                .foregroundStyle(PetPalette.ink)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(SquishStyle())
        .glassEffect(.regular.interactive(), in: Circle())
        .overlay(alignment: .topTrailing) {
            if badge {
                Circle()
                    .fill(PetPalette.accent)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(PetPalette.bg, lineWidth: 2))
                    .offset(x: 2, y: -2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(Text("Двор"))
        .accessibilityValue(Text(badge ? "есть что собрать или купить" : ""))
        .accessibilityHint(Text("Станции, копилка, ярусы"))
        .accessibilityIdentifier("open.yard")
    }
}

/// Круг «Двор» справа, с подписью — как у кругов ряда.
struct YardCorner: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            YardButton()
                .roundCaption(RoundCaption.yard)
        }
        .padding(.bottom, RoundCaption.room)
    }
}

/// Строка в карточке «Участок» на экране «Дом»: туда, где стоят станции и копится свинка. Вид — как у входа на кухню.
struct YardEntryLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "tree.fill")
                    .accessibilityHidden(true)
                Text("Двор: станции и копилка")
                    .axLines(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .accessibilityHidden(true)
            }
            .petFont(15, .bold)
            .foregroundStyle(PetPalette.accent)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(PetPalette.accent, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(SquishStyle())
        .accessibilityIdentifier("house.yard.open")
    }
}
