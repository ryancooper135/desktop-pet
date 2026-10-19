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
            .accessibilityIdentifier("pet.stage")
            // Только в UI-тестах: какие уровни дома стоят в комнате (HouseUITests). VoiceOver это не читает.
            .accessibilityValue(Text(Env.isUITest ? model.homeLevels.tag : ""))

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

                if let tip = Coach.shared.gestureTip, snap.alive, model.brush == nil {
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
                        .transition(.opacity)
                }

                if snap.alive {
                    if model.brush == nil {
                        ActionBar(snap: snap)
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
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: model.tasteOpened)
        .animation(.snappy, value: model.pendingCard?.id)
        .animation(.snappy, value: model.brush != nil)
        .animation(.snappy, value: Coach.shared.gestureTip)
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

/// Палец-подсказка ласки (PetTutorOverlay) — отдельный вид: решение читает стор и сцену, а HomeScreen
/// перерисовывается на каждое движение пальца (lookX).
struct PetTutorLayer: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot

    var body: some View {
        let ready = model.file.map { NeedHints.gates($0, at: snap.t)["pet"]?.ok ?? false } ?? false
        let show = Coach.shared.showTutor(file: model.file, snap: snap, petReady: ready, sceneClear: model.sceneClear)
        ZStack {
            if show {
                PetTutorOverlay()
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

/// Нижняя панель действий. Кнопка, которая сейчас откажет, полупрозрачная, но нажимается и объясняет причину тостом.
/// Волна 18: активные — цветное стекло с белой иконкой (ActTint), неактивные — бесцветные с бейджем причины.
/// Все кнопки одной ширины, подписи одним кеглем: кегль подбирается по самой длинной подписи, а не каждой отдельно.
struct ActionBar: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot

    static let spacing: CGFloat = 8
    /// На узком ряду (6 кнопок на iPhone SE) зазор ужимается, чтобы подписи не падали ниже читаемого.
    static let tightSpacing: CGFloat = 4
    /// Ниже этого кегля при обычном зазоре переходим на узкий.
    static let comfortLabel: CGFloat = 10
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
        let fit = Self.fit(titles: titles, total: width, maxSize: baseLabel)
        let cell = fit.cell
        let label = fit.label
        // Волна 18: почему кнопка сейчас не сработает — бейдж «3 мин», «спит», «моется» прямо на кнопке.
        let g = model.file.map { NeedHints.gates($0, at: snap.t) } ?? [:]
        GlassEffectContainer(spacing: fit.spacing) {
            HStack(spacing: fit.spacing) {
                if nap {
                    ActButton(title: "Разбудить", icon: "sun.max.fill", kind: "wake", dim: false, labelSize: label) { model.act(.wake) }
                        .frame(width: cell > 0 ? cell : nil)
                }
                ActButton(title: "Покормить", icon: "fork.knife", kind: "feed", dim: bathing || away, gate: g["feed"] ?? .open, labelSize: label) { model.act(.feed(Catalog.mainFood)) }
                    .frame(width: cell > 0 ? cell : nil)
                ActButton(title: "Погладить", icon: "hand.raised.fill", kind: "pet", dim: bathing || away, gate: g["pet"] ?? .open, labelSize: label) { model.act(.pet) }
                    .frame(width: cell > 0 ? cell : nil)
                ActButton(title: "Поиграть", icon: "tennisball.fill", kind: "play", dim: bathing || away || snap.pose == .sleep, gate: g["play"] ?? .open, labelSize: label) { model.act(.play) }
                    .frame(width: cell > 0 ? cell : nil)
                ActButton(title: "Помыть", icon: "bathtub.fill", kind: "bath", dim: bathing || away, gate: g["bath"] ?? .open, labelSize: label) { model.act(.bath) }
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
    static func cellWidth(total: CGFloat, count: Int, spacing: CGFloat = spacing) -> CGFloat {
        guard total > 0, count > 0 else { return 0 }
        return max(0, (total - spacing * CGFloat(count - 1)) / CGFloat(count))
    }

    /// Раскладка ряда: зазор, ширина ячейки и общий кегль. Обычный зазор, пока кегль не ниже comfortLabel;
    /// иначе узкий зазор и меньшие поля — так 6 кнопок на iPhone SE (375 pt) остаются читаемыми.
    /// Поля в узком ряду 7, а не 3–4: у ячейки ~74×56 скруглённые бока, и на высоте подписи
    /// внутри капсулы остаётся ~60 pt — с полями 4 «Покормить» упиралась в край (ui-63).
    static func fit(titles: [String], total: CGFloat, maxSize: CGFloat) -> (spacing: CGFloat, cell: CGFloat, label: CGFloat) {
        let cell = cellWidth(total: total, count: titles.count)
        let label = labelSize(titles: titles, cellWidth: cell, maxSize: maxSize)
        guard cell > 0, label < comfortLabel, maxSize > comfortLabel else { return (spacing, cell, label) }
        let tight = cellWidth(total: total, count: titles.count, spacing: tightSpacing)
        return (tightSpacing, tight, labelSize(titles: titles, cellWidth: tight, maxSize: maxSize, inset: 7))
    }

    /// Один кегль на все подписи: самый крупный (не больше maxSize), при котором самая длинная влезает в ячейку.
    /// inset — поля внутри капсулы с каждой стороны: 8, а не 5 — у капсулы скруглённые бока,
    /// и «Покормить» с полями 5 визуально упиралась в край на 5 кнопках. Пока ширина не известна, отдаёт maxSize.
    static func labelSize(titles: [String], cellWidth: CGFloat, maxSize: CGFloat,
                          minSize: CGFloat = 8, inset: CGFloat = 8) -> CGFloat {
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
    /// Волна 18: что скажет ядро (NeedHints.gate). Не ok — кнопка бесцветная, в углу бейдж причины.
    let gate: ActGate
    /// Кегль подписи: панель задаёт один на все кнопки.
    let labelSize: CGFloat
    let action: () -> Void

    @State private var taps = 0
    @ScaledMetric(relativeTo: .caption2) private var badgeSize: CGFloat = 10

    init(title: String, icon: String, kind: String, dim: Bool, gate: ActGate = .open, labelSize: CGFloat = 13,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.dim = dim
        self.gate = gate
        self.labelSize = labelSize
        self.action = action
    }

    /// Нажатие сейчас сработает.
    private var live: Bool { !dim && gate.ok }
    /// Бейдж причины: ядро сказало своё («3 мин», «спит») или вся панель погашена ванной/прогулкой.
    private var badge: String? { gate.badge ?? (dim ? "позже" : nil) }

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
                    // Запас на погрешность замера и самый узкий экран: кегль уже подобран рядом,
                    // здесь только страховка от «Покор…», если замер разошёлся с отрисовкой.
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
            }
            // Активная: белое на цветном стекле. Неактивная: приглушённые чернила на бесцветном.
            .foregroundStyle(live ? AnyShapeStyle(Color.white) : AnyShapeStyle(PetPalette.ink.opacity(0.5)))
            .shadow(color: live ? .black.opacity(0.18) : .clear, radius: 1, y: 1)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Capsule())
        }
        .buttonStyle(SquishStyle())
        .glassEffect(live ? .regular.tint(ActTint.color(kind).opacity(0.88)).interactive() : .regular.interactive(),
                     in: Capsule())
        .overlay(alignment: .top) {
            if !live, let badge {
                HStack(spacing: 2) {
                    Image(systemName: gate.reason == "cooldown" ? "clock.fill" : "lock.fill")
                    Text(badge)
                }
                .font(.system(size: min(badgeSize, 13), weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(PetPalette.soft))
                .offset(y: -7)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .coachHighlight(kind)
        .phaseAnimator(Self.shake, trigger: model.refusals[kind, default: 0], content: { view, x in
            view.offset(x: x)
        }, animation: { _ in
            .linear(duration: 0.06)
        })
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(live ? "" : badge.map { "недоступно, \($0)" } ?? "недоступно"))
        .accessibilityIdentifier("act.\(kind)")
    }
}

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
        // Подпись прямо у кнопки: один элемент «150 монет, 1 билетик». Обёртка accessibilityElement(children: .ignore)
        // давала вложенную вторую кнопку «🪙, 150, 🎟, 1», и VoiceOver читал картинки по отдельности.
        .accessibilityLabel(Text(EconText.wallet(coins: coins, tickets: tickets)))
        .accessibilityHint(Text("Кошелёк. Открыть автомат с капсулами"))
        .accessibilityIdentifier("open.wallet")
    }
}

/// «Открытка дня»: маленькая бумажка под верхним рядом, пока есть несохранённая открытка.
struct PostcardChip: View {
    let card: Postcard
    let action: () -> Void

    private var lastDay: Bool { Postcards.isLastDay(card, now: Clock.now()) }
    /// Для UI-тестов: есть ли у открытки снимок и каким способом он снят (ar/metal/window/fallback).
    private var photoValue: String {
        guard card.image != nil else { return "" }
        return "photo:" + (PostcardCamera.lastSource.isEmpty ? "disk" : PostcardCamera.lastSource)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(PetPalette.accent)
                Text("Открытка дня")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                if lastDay {
                    // Мягко: тем же акцентом, что конверт, без красного.
                    Text("· \(Postcards.lastDayChip)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.accent)
                }
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
        .accessibilityLabel(Text(lastDay ? "Открытка дня, \(Postcards.lastDayChip)" : "Открытка дня"))
        .accessibilityValue(Text(photoValue))
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
