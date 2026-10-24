// Главный экран v0.1: сцена с Шибой на весь экран, сверху карточка имени, мысль и реплика, снизу тост и стеклянная панель действий.
// Шкал на главном нет: долгое нажатие на карточку или свайп вверх по питомцу открывает NeedsSheet.
// Стекло (Liquid Glass) только на панели действий, остальное — непрозрачные «бумажные» плашки.
// Прогулка (WalkViews.swift): над панелью ряд «Альбом · Автомат · Гулять», пока гуляет — записка на месте Шибы.
// Волна 5: кошелёк у шестерёнки (тап — автомат), «Открытка дня» под верхним рядом, карточка «Вкус открыт!».
// Волна 18 (HintViews.swift): плашка «что нужно сейчас» над рядом «Гулять», ручка «Шкалы» под панелью,
// палец-подсказка ласки поверх Шибы, пузырь-мысль нажимается (ведёт туда же, куда плашка).

import SwiftUI
import UIKit
@preconcurrency import PetCore

struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    /// Кегль реплики растёт с Dynamic Type (волна 15), но не выше lineMax: над сценой места мало,
    /// а крупнее 22 pt реплика закрывает пса. Остальной главный экран — фиксированные кегли (макеты).
    @ScaledMetric(relativeTo: .subheadline) private var lineSize: CGFloat = 15
    static let lineMax: CGFloat = 22
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
            .accessibilityLabel(Text(HomeText.stageLabel(name: snap.name, pose: snap.pose)))
            .accessibilityHint(Text("Проведи пальцем по спине, чтобы погладить"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.act(.pet) }
            .accessibilityAction(named: Text("Шкалы")) { model.showNeeds = true }
            // Волна 18: жесты без пальца — щекотка и «что нужно сейчас» (как тап по плашке или пузырю).
            .accessibilityAction(named: Text("Пощекотать")) { model.tickle() }
            .accessibilityAction(named: Text("Что нужно сейчас")) { Coach.shared.tapThought(model) }
            // Волна 31: уход прямо со сцены, теми же словами, что кнопки панели. Нельзя — ядро откажет тостом,
            // а тост VoiceOver проговорит (onChange ниже).
            .accessibilityActions {
                ForEach(A11y.stageActs(pose: snap.pose, alive: snap.alive), id: \.self) { a in
                    Button(a.title) { stageAct(a) }
                }
            }
            .accessibilityIdentifier("pet.stage")
            // Волна 31: VoiceOver слышит сводку «хочет играть; сытость 70 %, …» (A11y.stageValue).
            // В UI-тестах вместо неё — какие уровни дома стоят в комнате (HouseUITests) и проход стекла
            // (GlassSettle): «glass=1» — кнопки уже пересмотрели готовую комнату.
            .accessibilityValue(Text(Env.isUITest
                ? GlassSettle.stageValue(levels: model.homeLevels.tag, pass: model.glassPass, uiTest: true)
                : A11y.stageValue(snap, order: VisibleNeeds.all)))

            // Часы и батарейка следуют теме: где стена того же тона — подложка под статус-бар.
            StatusScrim(schedule: model.roomSchedule, dark: colorScheme == .dark)

            // Обучение ласке: палец по спине. Касаний не ловит — гладят сквозь него.
            PetTutorLayer(snap: snap)

            if model.brush != nil && snap.alive {
                // Расчёсывание (BrushViews): жест по спине вместо обычных касаний. Пёс умер посреди сеанса —
                // слой убираем вместе с полосой (её и так нет), иначе он перехватывал касания сцены.
                BrushLayer()
                    .ignoresSafeArea()
            }

            if snap.pose == .away, !noteHeld, let note = awayNote {
                // Записка на месте Шибы, чуть ниже середины сцены: там он обычно стоит.
                GeometryReader { geo in
                    AwayNoteCard(text: note)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.52)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(Motion.pop(.scale(scale: 0.6).combined(with: .opacity)))
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
                        .accessibilityAction(named: Text("Шкалы")) { model.showNeeds = true }
                    Spacer(minLength: 0)
                    if let w = model.file?.econ.wallet {
                        WalletChip(coins: w.coins, tickets: w.tickets, shards: w.shards) { model.showCapsule = true }
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
                               : "Подпись кончится через \(days)\u{00A0}дн. Переустанови приложение заранее.")
                }
                if !snap.shared {
                    Banner(icon: "square.stack.3d.up.slash",
                           text: "Виджеты не видят сохранение: общая с ними папка не подключилась.")
                }
                if let card = model.pendingCard, snap.alive {
                    PostcardChip(card: card) { model.postcard = card }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Мысль и реплика — сверху, на стене над питомцем: там иначе пусто, а низ остаётся кнопкам.
                VStack(spacing: 6) {
                    if let icon = snap.wantIcon, snap.alive {
                        // Волна 18: «Погладь меня» нажимается — покажет, как гладить; «Хочу есть» — покормит.
                        Button {
                            Coach.shared.tapThought(model)
                        } label: {
                            ThoughtBubble(icon: icon, text: snap.wantText, urgent: snap.urgent)
                                .frame(minHeight: 32)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(SquishStyle())
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text(snap.want == "pet" ? "Покажет, как погладить" : "Покажет, что сделать"))
                        .accessibilityIdentifier("pet.thought")
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    Text(model.sayLine ?? snap.line)
                        .font(.system(size: min(lineSize, Self.lineMax), weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(lineSize > 17 ? 3 : 2)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
                        .accessibilityIdentifier("pet.line")
                    if let t = snap.timer { CalmTimerView(timer: t) }
                    if let fact = model.tasteOpened {
                        TasteOpenedCard(fact: fact)
                            .onTapGesture { model.tasteOpened = nil }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(Text("Скрыть"))
                            .accessibilityAction { model.tasteOpened = nil }
                            .transition(Motion.pop(.scale(scale: 0.6).combined(with: .opacity)))
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

                // Волна 22 (Hush): тост главнее — подсказка жеста под ним молчит, после него возвращается.
                if let tip = Coach.shared.gestureTip, Coach.shared.gestureTipShown(model) {
                    GestureTipChip(tip: tip)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if rescue {
                    RescueButton(main: snap.main) { model.doMain() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if model.brush != nil && snap.alive {
                    BrushPanel()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if snap.alive && !rescue {
                    NeedHintPlate(snap: snap)
                    WalkRow(snap: snap)
                        .id(model.glassPass)
                        .transition(.opacity)
                }

                if snap.alive {
                    if model.brush == nil {
                        ActionBar(snap: snap)
                            .id(model.glassPass)
                        NeedsHandle()
                    }
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
        .animation(Motion.calm(.spring(response: 0.4, dampingFraction: 0.6)), value: model.tasteOpened)
        .animation(.snappy, value: model.pendingCard?.id)
        .animation(.snappy, value: model.brush != nil)
        .animation(.snappy, value: Coach.shared.gestureTip)
        // Волна 31: тост VoiceOver проговаривает сам — «Монет мало», «+5 🪙» — фокус на него не прыгает.
        .onChange(of: model.toast?.id) { _, id in
            guard id != nil, let t = model.toast else { return }
            UIAccessibility.post(notification: .announcement, argument: t.text)
        }
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
            SoundLayer()
        }
        .sheet(isPresented: $model.showNeeds) {
            NeedsSheet()
                .environment(model)
        }
        // Закрыли настройки — «Свой персонаж» (pet://characters) в следующий раз не открывается сам.
        .sheet(isPresented: $model.showSettings, onDismiss: { model.showCharacters = false }) {
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
        .sheet(isPresented: $model.showHabits) {
            HabitsSheet()
                .environment(model)
                .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $model.showCatch) {
            // На весь экран: лист тянулся бы вниз вместе с миской.
            CatchGameScreen()
                .environment(model)
        }
        .fullScreenCover(isPresented: $model.showBlockDuo) {
            // Как мячик — на весь экран: перетаскивание фигур дралось бы со свайпом листа.
            BlockDuoScreen()
                .environment(model)
        }
        .fullScreenCover(isPresented: $model.showZombie) {
            // Как мячик — на весь экран: палец ведёт Шибу по всему полю.
            ZombieRunScreen()
                .environment(model)
                // Экран ночной: без этого часы и значки сверху чёрные на тёмном.
                .preferredColorScheme(.dark)
        }
        .sheet(item: $model.postcard) { card in
            PostcardSheet(card: card)
                .environment(model)
                // Выше половины: под открыткой ещё кнопки и срок — в .medium и 0.56 низ карточки уходил под них.
                .presentationDetents([.fraction(0.6), .large])
        }
        .confirmationDialog("Начать заново с новым щенком?", isPresented: $confirmStartOver, titleVisibility: .visible) {
            Button("Начать заново", role: .destructive) { model.startOver() }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// Действие ухода со сцены (VoiceOver): те же вызовы, что у кнопок ActionBar.
    private func stageAct(_ a: A11y.StageAct) {
        switch a {
        case .wake: model.act(.wake)
        case .feed: model.act(.feed(Catalog.mainFood))
        case .pet: model.act(.pet)
        case .play: model.act(.play)
        case .bath: model.act(.bath)
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
            Feel.prepare(.soft)
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
                Feel.soft(.petTick(n))
                model.pop("", at: p, symbol: "heart.fill")
            case .stroke:
                // Coach засчитает ласку в обучение (палец уйдёт) и отдаст .pet ядру.
                Coach.shared.stroked(model)
            case .tap:
                model.tapPet()
            case .tickle:
                model.tickle()
                Coach.shared.performed("tickle")
            case .swipeUp:
                Coach.shared.performed("swipe")
                model.showNeeds = true
            }
        }
    }
}

/// Подложка под статус-бар цвета фона: в тёмной теме днём (стена светлая, часы белые)
/// и в светлой ночью (стена тёмная, часы чёрные). Фазу сверяет раз в полминуты, появляется плавно.
private struct StatusScrim: View {
    var schedule: RoomSchedule
    var dark: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let on = RoomClock.needsStatusScrim(phase: schedule.phaseNow(dark: dark), dark: dark)
            GeometryReader { geo in
                LinearGradient(stops: [.init(color: PetPalette.bg.opacity(0.92), location: 0),
                                       .init(color: PetPalette.bg.opacity(0.92), location: 0.55),
                                       .init(color: PetPalette.bg.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.safeAreaInsets.top + 18)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .opacity(on ? 1 : 0)
                    .animation(.easeInOut(duration: 1.4), value: on)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
