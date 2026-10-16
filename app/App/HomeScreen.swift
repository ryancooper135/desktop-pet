// Главный экран v0.1: сцена с Шибой на весь экран, сверху карточка имени и мысль, снизу стеклянная панель действий.
// Шкал на главном нет: долгое нажатие на карточку или свайп вверх по питомцу открывает NeedsSheet.
// Стекло (Liquid Glass) только на панели действий, остальное — непрозрачные «бумажные» плашки.

import SwiftUI
@preconcurrency import PetCore

struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmStartOver = false

    var body: some View {
        @Bindable var model = model
        let snap = model.snap
        ZStack {
            PetPalette.bg.ignoresSafeArea()

            PetStage(pose: snap.pose)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.tapPet() }
                .gesture(
                    DragGesture(minimumDistance: 20).onEnded { g in
                        let dx = g.translation.width, dy = g.translation.height
                        if dy < -80 && abs(dx) < 80 {
                            model.showNeeds = true
                        } else if abs(dx) > 150 {
                            // Провёл пальцем по спине — погладил.
                            model.act(.pet)
                        }
                    }
                )
                .accessibilityElement()
                .accessibilityLabel(Text("\(snap.name): \(PetFaceView.accessibilityText(snap.pose))"))
                .accessibilityHint(Text("Нажми, чтобы погладить"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("Шкалы")) { model.showNeeds = true }

            if snap.level >= 3 && snap.alive {
                RescueVignette()
            }

            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    NameCard(snap: snap)
                        .onLongPressGesture { model.showNeeds = true }
                    Spacer(minLength: 0)
                    Button {
                        model.showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PetPalette.ink)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(PetPalette.card))
                    }
                    .accessibilityLabel(Text("Настройки"))
                    .accessibilityIdentifier("open.settings")
                }

                if let days = snap.buildDaysLeft, days <= 3 {
                    Banner(icon: "exclamationmark.triangle.fill",
                           text: days <= 0 ? "Подпись кончилась сегодня. Переустанови приложение, время питомца стоит."
                               : "Подпись кончится через \(days) дн. Переустанови приложение заранее.")
                }
                if !snap.shared {
                    Banner(icon: "square.stack.3d.up.slash",
                           text: "Виджеты не видят сохранение: общая папка App Group не подключилась.")
                }

                if let icon = snap.wantIcon, snap.alive {
                    ThoughtBubble(icon: icon, text: snap.wantText, urgent: snap.urgent)
                        .padding(.top, 6)
                }

                Spacer()

                VStack(spacing: 6) {
                    if let t = snap.timer { NeedTimerView(timer: t) }
                    Text(snap.line)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
                }

                if snap.level >= 3 && snap.alive {
                    RescueButton(main: snap.main) { model.doMain() }
                }

                if snap.alive {
                    ActionBar(snap: snap)
                } else {
                    Button {
                        confirmStartOver = true
                    } label: {
                        Text("Начать заново")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PetPalette.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if let toast = model.toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: model.toast)
        .sheet(isPresented: $model.showNeeds) {
            NeedsSheet()
                .environment(model)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsScreen()
                .environment(model)
        }
        .confirmationDialog("Начать заново с новым щенком?", isPresented: $confirmStartOver, titleVisibility: .visible) {
            Button("Начать заново", role: .destructive) { model.startOver() }
            Button("Отмена", role: .cancel) {}
        }
    }
}

/// Аватар, имя, сердечки и уровень. Непрозрачная плашка.
struct NameCard: View {
    let snap: PetSnapshot

    var body: some View {
        HStack(spacing: 10) {
            PetFaceView(pose: snap.pose)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(snap.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 13)
                Text(snap.levelTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.level(snap.level))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Долгое нажатие — шкалы"))
    }
}

/// Нижняя панель действий. Кнопка, которая сейчас откажет, полупрозрачная, но нажимается и объясняет причину тостом.
struct ActionBar: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot

    private var bathing: Bool { snap.main == .none }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if snap.pose == .nap {
                    item("Разбудить", "sun.max.fill", dim: false) { model.act(.wake) }
                }
                item("Покормить", "fork.knife", dim: bathing) { model.act(.feed(Catalog.mainFood)) }
                item("Погладить", "hand.raised.fill", dim: bathing) { model.act(.pet) }
                item("Поиграть", "tennisball.fill", dim: bathing || snap.pose == .sleep) { model.act(.play) }
                item("Помыть", "bathtub.fill", dim: bathing) { model.act(.bath) }
                if Self.lampTime(Clock.now()) {
                    item("Отбой", "lamp.desk.fill", dim: false) { model.setBedtime(minute: Self.minuteNow(Clock.now())) }
                }
            }
        }
    }

    private func item(_ title: String, _ icon: String, dim: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(PetPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(dim ? 0.45 : 1)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel(Text(title))
    }

    /// Лампа видна с 20:00 до 02:00 по местному времени.
    static func lampTime(_ t: Double) -> Bool {
        let h = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: t))
        return h >= 20 || h < 2
    }

    static func minuteNow(_ t: Double) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t))
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// Уровень 3: тёмная виньетка поверх сцены и одна большая кнопка над панелью. Тап по питомцу делает то же.
struct RescueVignette: View {
    var body: some View {
        RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 120, endRadius: 520)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct RescueButton: View {
    let main: MainAct
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: main.icon)
                Text("Спасти: \(main.title.lowercased())")
            }
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(PetPalette.red))
        }
        .buttonStyle(.plain)
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

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: toast.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(toast.ok ? PetPalette.green : PetPalette.red)
            Text(toast.text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(PetPalette.card).shadow(color: .black.opacity(0.12), radius: 8, y: 3))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
