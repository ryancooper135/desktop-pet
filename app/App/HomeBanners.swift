// Плашки главного экрана: спокойный таймер, спасение на уровне 3, баннер и тост.
// Перенесено из HomeScreen.swift без изменений (волна 28).

import SwiftUI
import UIKit
@preconcurrency import PetCore

/// Таймер под репликой без секунд: «Испачкается через 2 ч 51 мин», «Заскучает через 40 мин», «меньше чем через минуту».
/// Обновляется только когда меняется текст (раз в минуту, ровно на границе минуты остатка), а не каждую секунду.
/// Виджеты и остров по-прежнему на NeedTimerView: там TimelineView не тикает, нужен системный отсчёт.
struct CalmTimerView: View {
    var timer: NeedTimer
    @Environment(\.petFrozenNow) private var frozenNow

    var body: some View {
        if let frozen = frozenNow {
            line(at: frozen)
        } else {
            TimelineView(MinuteBoundarySchedule(end: timer.end)) { ctx in
                // Часы приложения (PET_NOW в UI-тестах сдвигает их), а не голая дата расписания.
                line(at: ctx.date.timeIntervalSince1970 + Clock.offset)
            }
        }
    }

    private func line(at t: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: NeedTimerView.icon(timer.kind))
                .accessibilityHidden(true)
            Text(HomeText.calmTimer(kind: timer.kind, title: timer.title, remaining: timer.end - t))
                .contentTransition(.numericText(countsDown: true))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(PetPalette.soft)
        // Подложка: без неё серый текст тонет в розовой сцене, вечерней стене и ламбрекене окна.
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(PetPalette.card.opacity(0.75)))
        .animation(.snappy, value: Int((timer.end - t) / 60))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pet.timer")
    }
}

/// Моменты, когда у таймера меняется текст: остаток пересекает целую минуту (HomeText.nextChange).
/// end — в часах приложения (Clock), даты расписания — настоящие.
struct MinuteBoundarySchedule: TimelineSchedule {
    let end: Double

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        let offset = Clock.offset
        let end = end
        let ticks = sequence(first: startDate.timeIntervalSince1970 + offset) { HomeText.nextChange(after: $0, end: end) }
        return AnySequence(ticks.lazy.map { Date(timeIntervalSince1970: $0 - offset) })
    }
}

/// Уровень 3: красно-тёмная виньетка поверх сцены и одна большая пульсирующая кнопка над панелью.
/// Тап по питомцу делает то же. Красный тон отличает «спасай» от простого «голоден» (там виньетки нет).
struct RescueVignette: View {
    static let tint = Color(hex: 0x5a1414)

    var body: some View {
        RadialGradient(colors: [.clear, Self.tint.opacity(0.35), Self.tint.opacity(0.7)],
                       center: .center, startRadius: 110, endRadius: 560)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct RescueButton: View {
    let main: MainAct
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: main.icon)
                Text("Спасти: \(main.title.lowercased())")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(PetPalette.red).shadow(color: PetPalette.red.opacity(0.5), radius: 10, y: 2))
        }
        .buttonStyle(SquishStyle())
        // Мягкий пульс, пока кнопка на экране; при «Уменьшении движения» стоит на месте.
        .phaseAnimator(reduceMotion ? [false] : [false, true]) { view, on in
            view.scaleEffect(on ? 1.03 : 1)
        } animation: { _ in
            .easeInOut(duration: 0.8)
        }
        .accessibilityIdentifier("act.rescue")
        .padding(.horizontal, 16)
    }
}

struct Banner: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(PetPalette.yellow)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card))
        .accessibilityElement(children: .combine)
    }
}

/// Тост — с волны 53 чёрная капсула у островка (IslandToast в GlassKit). Имя осталось: его ставят дом и двор.
struct ToastView: View {
    let toast: Toast

    var body: some View { IslandToast(toast: toast) }
}
