// Главный экран v0.1: сцена с Шибой на весь экран, сверху карточка имени, мысль и реплика, снизу тост и стеклянная панель действий.
// Шкал на главном нет: долгое нажатие на карточку или свайп вверх по питомцу открывает NeedsSheet.
// Стекло (Liquid Glass) только на панели действий, остальное — непрозрачные «бумажные» плашки.
// Прогулка (WalkViews.swift): над панелью ряд «Альбом · Автомат · Гулять», пока гуляет — записка на месте Шибы.
// Волна 5: кошелёк у шестерёнки (тап — автомат), «Открытка дня» под верхним рядом, карточка «Вкус открыт!».

import SwiftUI
import UIKit
@preconcurrency import PetCore

struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmStartOver = false
    /// Записка ждёт, пока Шиба уйдёт за край кадра (при открытии во время прогулки — сразу).
    @State private var noteHeld = false
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
                         lookX: model.lookX,
                         walkHomeId: model.walkHome.id,
                         walkHomeFind: model.walkHome.find,
                         coat: model.coat)
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
            // Только в UI-тестах: какие уровни дома стоят в комнате (HouseUITests). VoiceOver это не читает.
            .accessibilityValue(Text(Env.isUITest ? model.homeLevels.tag : ""))

            if snap.pose == .away, !noteHeld, let note = awayNote {
                // Записка на месте Шибы, чуть ниже середины сцены: там он обычно стоит.
                GeometryReader { geo in
                    AwayNoteCard(text: note)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.52)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            if rescue {
                RescueVignette()
                    .transition(.opacity)
            }

            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    // Карточка забирает ширину первой: иначе ряд с кошельком делит место поровну и «Шиба» ломается по буквам.
                    NameCard(snap: snap)
                        .layoutPriority(1)
                        .onLongPressGesture { model.showNeeds = true }
                    Spacer(minLength: 0)
                    if let w = model.file?.econ.wallet {
                        WalletChip(coins: w.coins, tickets: w.tickets) { model.showCapsule = true }
                    }
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
                           text: "Виджеты не видят сохранение: общая с ними папка не подключилась.")
                }
                if let card = model.pendingCard, snap.alive {
                    PostcardChip { model.postcard = card }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Мысль и реплика — сверху, на стене над питомцем: там иначе пусто, а низ остаётся кнопкам.
                VStack(spacing: 6) {
                    if let icon = snap.wantIcon, snap.alive {
                        ThoughtBubble(icon: icon, text: snap.wantText, urgent: snap.urgent)
                            .accessibilityIdentifier("pet.thought")
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    Text(model.sayLine ?? snap.line)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
                        .accessibilityIdentifier("pet.line")
                    if let t = snap.timer { NeedTimerView(timer: t) }
                    if let fact = model.tasteOpened {
                        TasteOpenedCard(fact: fact)
                            .onTapGesture { model.tasteOpened = nil }
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.top, 2)

                Spacer(minLength: 8)

                // Тост — над кнопками, рядом с тем, что его вызвало; карточку имени не закрывает.
                if let toast = model.toast {
                    ToastView(toast: toast)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if rescue {
                    RescueButton(main: snap.main) { model.doMain() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if snap.alive && !rescue {
                    WalkRow(snap: snap)
                        .transition(.opacity)
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
                    .accessibilityIdentifier("act.startOver")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .animation(.snappy, value: model.toast)
        .animation(.snappy, value: rescue)
        .animation(.snappy, value: snap.wantIcon)
        .animation(.snappy, value: snap.pose == .away)
        .animation(.snappy, value: noteHeld)
        .animation(.snappy, value: model.sayLine)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: model.tasteOpened)
        .animation(.snappy, value: model.pendingCard?.id)
        .onChange(of: snap.pose == .away) { was, now in
            guard now, !was else { return }
            noteHeld = true
            Task {
                // Переход в стойку (~0.5 с) + уход; с запасом, чтобы записка не легла на уходящего Шибу.
                try? await Task.sleep(for: .seconds(ChoreoPath.Walk.outLength + 0.8))
                noteHeld = false
            }
        }
        .background {
            HapticsLayer()
            SoundLayer()
        }
        .sheet(isPresented: $model.showNeeds) {
            NeedsSheet()
                .environment(model)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsScreen()
                .environment(model)
        }
        .sheet(isPresented: $model.showAlbum) {
            AlbumSheet()
                .environment(model)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $model.showCapsule) {
            CapsuleScreen()
                .environment(model)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $model.showHouse) {
            HouseScreen()
                .environment(model)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $model.showTricks) {
            // Половина экрана: пёс виден над листом, а выбрал команду — лист уезжает и пёс пробует.
            TricksScreen()
                .environment(model)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $model.postcard) { card in
            PostcardSheet(card: card)
                .environment(model)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Начать заново с новым щенком?", isPresented: $confirmStartOver, titleVisibility: .visible) {
            Button("Начать заново", role: .destructive) { model.startOver() }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// «Ушёл гулять, вернусь в 14:20» по часам хозяина.
    private var awayNote: String? {
        guard let f = model.file else { return nil }
        let t = model.snap.t
        guard let w = PetRunner.peek(f, at: t).outing else { return nil }
        return Finds.awayNote(until: w.until, tzOffsetMin: PetRunner.owner(f, at: t).tzOffsetMin, now: t)
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
            case .tick(let n):
                // Каждые 50 pt пути — лёгкий тик, нотка вверх по ладу и сердечко под пальцем.
                guard model.snap.alive, model.snap.pose != .away else { continue }
                model.haptic(.light)
                SoundKit.shared.strokeTick(n)
                model.pop("", at: p, symbol: "heart.fill")
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
/// Критично (уровень 3+): красная обводка и значок тревоги у подписи — видно сразу, не путается с «голоден».
struct NameCard: View {
    let snap: PetSnapshot

    private var critical: Bool { snap.alive && snap.level >= 3 }

    var body: some View {
        HStack(spacing: 10) {
            PetFaceView(pose: snap.pose)
                .frame(width: 40, height: 40)
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
    }
}

/// Нижняя панель действий. Кнопка, которая сейчас откажет, полупрозрачная, но нажимается и объясняет причину тостом.
/// Все кнопки одной ширины, подписи одним кеглем: кегль подбирается по самой длинной подписи, а не каждой отдельно.
struct ActionBar: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot

    static let spacing: CGFloat = 8
    /// Базовый кегль подписи, растёт вместе с Dynamic Type; сверху его ограничивает ширина ячейки.
    @ScaledMetric(relativeTo: .caption) private var baseLabel: CGFloat = 13
    @State private var width: CGFloat = 0

    private var bathing: Bool { snap.main == .none }
    /// Гуляет: дома никого, ядро откажет всем кнопкам («Гуляет, скоро вернётся»).
    private var away: Bool { snap.pose == .away }

    var body: some View {
        let nap = snap.pose == .nap
        let lamp = Self.lampTime(Clock.now())
        let titles = Self.titles(nap: nap, lamp: lamp)
        let cell = Self.cellWidth(total: width, count: titles.count)
        let label = Self.labelSize(titles: titles, cellWidth: cell, maxSize: baseLabel)
        GlassEffectContainer(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                if nap {
                    ActButton(title: "Разбудить", icon: "sun.max.fill", kind: "wake", dim: false, labelSize: label) { model.act(.wake) }
                        .frame(width: cell > 0 ? cell : nil)
                }
                ActButton(title: "Покормить", icon: "fork.knife", kind: "feed", dim: bathing || away, labelSize: label) { model.act(.feed(Catalog.mainFood)) }
                    .frame(width: cell > 0 ? cell : nil)
                ActButton(title: "Погладить", icon: "hand.raised.fill", kind: "pet", dim: bathing || away, labelSize: label) { model.act(.pet) }
                    .frame(width: cell > 0 ? cell : nil)
                ActButton(title: "Поиграть", icon: "tennisball.fill", kind: "play", dim: bathing || away || snap.pose == .sleep, labelSize: label) { model.act(.play) }
                    .frame(width: cell > 0 ? cell : nil)
                ActButton(title: "Помыть", icon: "bathtub.fill", kind: "bath", dim: bathing || away, labelSize: label) { model.act(.bath) }
                    .frame(width: cell > 0 ? cell : nil)
                if lamp {
                    ActButton(title: "Отбой", icon: "lamp.desk.fill", kind: "bed", dim: false, labelSize: label) {
                        model.setBedtime(minute: Self.minuteNow(Clock.now()))
                    }
                    .frame(width: cell > 0 ? cell : nil)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background {
            GeometryReader { g in
                Color.clear.onChange(of: g.size.width, initial: true) { _, w in width = w }
            }
        }
    }

    /// Подписи кнопок в порядке панели. Должны совпадать с ActButton в body.
    static func titles(nap: Bool, lamp: Bool) -> [String] {
        var t: [String] = []
        if nap { t.append("Разбудить") }
        t += ["Покормить", "Погладить", "Поиграть", "Помыть"]
        if lamp { t.append("Отбой") }
        return t
    }

    /// Ширина одной ячейки при равном делении панели; 0, пока ширина не измерена.
    static func cellWidth(total: CGFloat, count: Int) -> CGFloat {
        guard total > 0, count > 0 else { return 0 }
        return max(0, (total - spacing * CGFloat(count - 1)) / CGFloat(count))
    }

    /// Один кегль на все подписи: самый крупный (не больше maxSize), при котором самая длинная влезает в ячейку.
    /// inset — поля внутри капсулы с каждой стороны. Пока ширина не известна, отдаёт maxSize.
    static func labelSize(titles: [String], cellWidth: CGFloat, maxSize: CGFloat,
                          minSize: CGFloat = 9, inset: CGFloat = 5) -> CGFloat {
        guard cellWidth > 0, !titles.isEmpty else { return maxSize }
        let room = cellWidth - inset * 2
        var size = maxSize
        while size > minSize {
            let widest = titles.map { labelWidth($0, size: size) }.max() ?? 0
            if widest <= room { return size }
            size -= 0.5
        }
        return minSize
    }

    /// Ширина подписи шрифтом кнопки (SF Rounded semibold) при данном кегле.
    static func labelWidth(_ text: String, size: CGFloat) -> CGFloat {
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
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
    /// Кегль подписи: панель задаёт один на все кнопки.
    let labelSize: CGFloat
    let action: () -> Void

    @State private var taps = 0

    init(title: String, icon: String, kind: String, dim: Bool, labelSize: CGFloat = 13, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.dim = dim
        self.labelSize = labelSize
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
                    .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    // Запас на погрешность замера; у всех кнопок одинаковый, так что кегль остаётся общим.
                    .minimumScaleFactor(0.9)
            }
            .foregroundStyle(PetPalette.ink)
            .padding(.horizontal, 2)
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

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 6) {
            if let emoji = toast.emoji {
                Text(emoji).font(.system(size: 15))
            } else {
                Image(systemName: toast.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(toast.ok ? PetPalette.green : PetPalette.red)
            }
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

// MARK: - Волна 5: кошелёк, открытка, открытый вкус

/// Кошелёк у шестерёнки: «🪙 150 · 🎟 1». Тап — автомат с капсулами.
struct WalletChip: View {
    let coins: Int
    let tickets: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("🪙").font(.system(size: 13))
                Text("\(coins)")
                    .contentTransition(.numericText(value: Double(coins)))
                Text("🎟").font(.system(size: 13))
                Text("\(tickets)")
                    .contentTransition(.numericText(value: Double(tickets)))
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(PetPalette.ink)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Capsule().fill(PetPalette.card))
            .animation(.snappy, value: coins)
            .animation(.snappy, value: tickets)
        }
        .fixedSize()
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Кошелёк: \(EconText.coins(coins)), \(EconText.tickets(tickets))"))
        .accessibilityHint(Text("Открыть автомат с капсулами"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("open.wallet")
    }
}

/// «Открытка дня»: маленькая бумажка под верхним рядом, пока есть несохранённая открытка.
struct PostcardChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(PetPalette.accent)
                Text("Открытка дня")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: 0xfff6d8))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            )
            // Бумага всегда светлая.
            .environment(\.colorScheme, .light)
            .rotationEffect(.degrees(-2))
        }
        .buttonStyle(SquishStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text("Открытка дня"))
        .accessibilityIdentifier("postcard.card")
    }
}

/// «Вкус открыт!»: заметная карточка на пару секунд — значок вещи и строка альбома.
struct TasteOpenedCard: View {
    let fact: TasteFact

    var body: some View {
        HStack(spacing: 10) {
            Text(fact.emoji).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text("Вкус открыт!")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(fact.taste == .dislike ? PetPalette.soft : PetPalette.accent)
                Text(fact.text)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(PetPalette.card)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(fact.taste == .dislike ? PetPalette.soft.opacity(0.5) : PetPalette.accent, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("taste.opened")
    }
}
