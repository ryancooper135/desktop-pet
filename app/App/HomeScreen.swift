// Главный экран v0.1: сцена с Шибой на весь экран, сверху карточка имени и мысль, снизу стеклянная панель действий.
// Шкал на главном нет: долгое нажатие на карточку или свайп вверх по питомцу открывает NeedsSheet.
// Стекло (Liquid Glass) только на панели действий, остальное — непрозрачные «бумажные» плашки.

import SwiftUI
@preconcurrency import PetCore

struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmStartOver = false
    /// Состояние жеста по сцене. В коробке: точки пальца не перерисовывают экран.
    @State private var touch = TouchBox()

    var body: some View {
        @Bindable var model = model
        let snap = model.snap
        let rescue = snap.level >= 3 && snap.alive
        ZStack {
            PetPalette.bg.ignoresSafeArea()

            GeometryReader { geo in
                PetStage(pose: snap.pose,
                         reactionId: model.reaction.id,
                         reactionKind: model.reaction.kind,
                         reactionOk: model.reaction.ok,
                         lookX: model.lookX)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(stageGesture)
                    .overlay { PopLayer() }
                    .onChange(of: geo.size, initial: true) { _, s in model.stageSize = s }
            }
            .ignoresSafeArea()
            .accessibilityElement()
            .accessibilityLabel(Text("\(snap.name): \(PetFaceView.accessibilityText(snap.pose))"))
            .accessibilityHint(Text("Проведи пальцем по спине, чтобы погладить"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.act(.pet) }
            .accessibilityAction(named: Text("Шкалы")) { model.showNeeds = true }
            .accessibilityIdentifier("pet.stage")

            if rescue {
                RescueVignette()
                    .transition(.opacity)
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
                        .accessibilityIdentifier("pet.thought")
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                Spacer()

                VStack(spacing: 6) {
                    if let t = snap.timer { NeedTimerView(timer: t) }
                    Text(snap.line)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
                        .accessibilityIdentifier("pet.line")
                }

                if rescue {
                    RescueButton(main: snap.main) { model.doMain() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .animation(.snappy, value: rescue)
        .animation(.snappy, value: snap.wantIcon)
        .background { HapticsLayer() }
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

    // MARK: касания по сцене

    /// Один жест на всё: тап, ласка (провести пальцем), щекотка, свайп вверх. Разбор — в StrokeTracker.
    private var stageGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in stageMoved(g) }
            .onEnded { g in stageEnded(g) }
    }

    private func stageMoved(_ g: DragGesture.Value) {
        let t = g.time.timeIntervalSinceReferenceDate
        // Новый жест (или прошлый оборвался без onEnded) — начать заново.
        if !touch.tracker.active || touch.start != g.startLocation {
            touch.tracker.begin(at: g.startLocation, time: t)
            touch.start = g.startLocation
        }
        handle(touch.tracker.move(to: g.location, time: t), at: g.location)
        model.touch(at: g.location)
    }

    private func stageEnded(_ g: DragGesture.Value) {
        let t = g.time.timeIntervalSinceReferenceDate
        let events = touch.tracker.end(at: g.location, time: t)
        touch.start = nil
        handle(events, at: g.location)
        model.touchEnded()
    }

    private func handle(_ events: [StrokeEvent], at p: CGPoint) {
        for e in events {
            switch e {
            case .tick:
                // Каждые 50 pt пути — лёгкий тик и сердечко под пальцем.
                guard model.snap.alive else { continue }
                model.haptic(.light)
                model.pop("❤", at: p)
            case .stroke:
                model.act(.pet)
            case .tap:
                model.tapPet()
            case .tickle:
                model.tickle()
            case .swipeUp:
                model.showNeeds = true
            }
        }
    }
}

/// Изменяемое состояние жеста по сцене (не @Observable: экран его не читает).
final class TouchBox {
    var tracker = StrokeTracker()
    var start: CGPoint? = nil
}

/// Хаптика по счётчикам модели: каждый вид — свой trigger.
struct HapticsLayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Color.clear
            .sensoryFeedback(.impact(weight: .light), trigger: model.buzzes.light)
            .sensoryFeedback(.impact(weight: .medium), trigger: model.buzzes.medium)
            .sensoryFeedback(.success, trigger: model.buzzes.success)
            .sensoryFeedback(.warning, trigger: model.buzzes.warning)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
                    ActButton(title: "Разбудить", icon: "sun.max.fill", kind: "wake", dim: false) { model.act(.wake) }
                }
                ActButton(title: "Покормить", icon: "fork.knife", kind: "feed", dim: bathing) { model.act(.feed(Catalog.mainFood)) }
                ActButton(title: "Погладить", icon: "hand.raised.fill", kind: "pet", dim: bathing) { model.act(.pet) }
                ActButton(title: "Поиграть", icon: "tennisball.fill", kind: "play", dim: bathing || snap.pose == .sleep) { model.act(.play) }
                ActButton(title: "Помыть", icon: "bathtub.fill", kind: "bath", dim: bathing) { model.act(.bath) }
                if Self.lampTime(Clock.now()) {
                    ActButton(title: "Отбой", icon: "lamp.desk.fill", kind: "bed", dim: false) {
                        model.setBedtime(minute: Self.minuteNow(Clock.now()))
                    }
                }
            }
        }
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

/// Кнопка панели: пружинит, иконка подпрыгивает на нажатие, при отказе ядра кнопка качается.
/// kind — вид действия ядра (PetAction.kind), id для UI-тестов — "act.<kind>".
struct ActButton: View {
    @Environment(AppModel.self) private var model
    let title: String
    let icon: String
    let kind: String
    let dim: Bool
    let action: () -> Void

    @State private var taps = 0

    init(title: String, icon: String, kind: String, dim: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.dim = dim
        self.action = action
    }

    /// Смещения по x за одно покачивание.
    private static let shake: [CGFloat] = [0, -6, 6, -3, 0]

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.bounce, value: taps)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(PetPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Capsule())
        }
        .buttonStyle(SquishStyle())
        .opacity(dim ? 0.45 : 1)
        .glassEffect(.regular.interactive(), in: Capsule())
        .phaseAnimator(Self.shake, trigger: model.refusals[kind, default: 0], content: { view, x in
            view.offset(x: x)
        }, animation: { _ in
            .linear(duration: 0.06)
        })
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("act.\(kind)")
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
        .buttonStyle(SquishStyle())
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
