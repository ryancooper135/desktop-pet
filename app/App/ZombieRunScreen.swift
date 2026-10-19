// Мини-игра «Щенок против зомби» (волна 13, ROADMAP этап 5, стиль C): на весь экран, открывается из меню кнопки
// «Мини-игры» (GamesButton) и по pet://zombie. Три состояния, как у «Лови мячик» и «Блок Дуо»: карточка «Играть»,
// раунд, карточка итога с монетами. Логика — ZombieRun (Shared), картинка — ZombieArt + RetroRaster (свой
// растеризатор: низкое разрешение, дрожащие вершины, туман, дизеринг). Тут только экран, палец, хаптика и звук.
// Решения (Вадим может поменять):
// • ведёшь пальцем в любом месте поля влево-вправо, относительно (куда бы ни поставил палец — Шиба не прыгает);
//   кидает Шиба сам, кнопка «Гав!» — справа внизу под большой палец, вокруг неё копится кольцо;
// • кадр 176 точек в ширину, растягивается без сглаживания — пиксели видно, как на PS1; рисуется вне главного потока;
// • закрыл посреди раунда — раунд засчитан как есть (монеты по очкам), как в «Блок Дуо»;
// • после раунда, когда экран закрылся, Шиба в комнате подпрыгивает, виляет и говорит фразу (AppModel.cheerZombie).
// UI-тесты: PET_ZOMBIE=play — раунд на 21-й секунде (автопилот, сид 7), кадр стоит; PET_ZOMBIE=done — раунд сыгран
// автопилотом до конца и записан, видна карточка итога.

import SwiftUI
@preconcurrency import PetCore

struct ZombieRunScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    private enum Phase: Equatable {
        case intro
        case playing
        case done(ZombieResult)
    }

    @State private var phase: Phase = .intro
    @State private var round = ZombieRound(seed: 1)
    /// Куда тянется Шиба (мировой x, −lane…lane).
    @State private var target = 0.0
    /// Откуда начался текущий жест: target в момент касания.
    @State private var dragFrom: Double? = nil
    @State private var frame: CGImage? = nil
    @State private var marks: [Int: CGPoint] = [:]
    @State private var pops: [ZombiePop] = []
    @State private var nextPop = 0
    @State private var field: CGSize = .zero
    @State private var runID = 0
    /// Снимок UI-теста: раунд стоит.
    @State private var frozen = false
    /// Приложение активно — зеркало scenePhase для цикла кадров: окружение, взятое задачей, не обновляется.
    @State private var live = true
    @State private var posterIntro: CGImage? = nil
    @State private var posterDone: CGImage? = nil
    @State private var slobber = 0
    @State private var barkPulse = 0

    /// Сид UI-тестов: один и тот же раунд на каждом прогоне.
    static let testSeed: UInt64 = 7
    /// На какой секунде замирает PET_ZOMBIE=play.
    static let testFreeze = 21.0
    /// Фон экрана — небо коридора, чтобы кадр не выглядел вырезанным.
    static let night = Color(hex: 0x1A1228)

    var body: some View {
        VStack(spacing: 0) {
            topBar
            switch phase {
            case .intro:
                Spacer(minLength: 0)
                ZombieIntroCard(poster: posterIntro, gate: gate, best: model.file?.zombieBest ?? 0, left: coinsLeft) { start() }
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            case .playing:
                playArea
            case .done(let r):
                Spacer(minLength: 0)
                ZombieDoneCard(poster: posterDone, result: r, again: gate == nil, start: { start() }, close: { close() })
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            }
        }
        .background(Self.night.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task(id: runID) { await loop() }
        .onChange(of: scenePhase, initial: true) { _, p in live = p == .active }
        .task { await makePosters() }
        .onAppear { uiTestSetup() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zombie.screen")
    }

    private var gate: String? {
        guard let f = model.file else { return Tricks.loadingReason }
        return ZombieRun.gate(f, at: model.snap.t)
    }

    private var coinsLeft: Int {
        model.file.map { ZombieRun.coinsLeft($0, now: model.snap.t) } ?? 0
    }

    // MARK: верх

    private var topBar: some View {
        HStack {
            Text(ZombieConfig.shared.name)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button {
                model.haptic(.light)
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(SquishStyle())
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel(Text("Закрыть"))
            .accessibilityHint(Text(phase == .playing && round.score > 0 ? "Раунд засчитается с текущим счётом" : ""))
            .accessibilityIdentifier("zombie.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: раунд

    private var playArea: some View {
        ZStack {
            view3D
            VStack(spacing: 0) {
                hud
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    hint
                    Spacer(minLength: 12)
                    barkButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
            // Обслюнявили — по краям вспыхивает розовым.
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(PetPalette.tongue, lineWidth: 10)
                .blur(radius: 8)
                .keyframeAnimator(initialValue: 0.0, trigger: slobber) { view, a in
                    view.opacity(a)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(0.9, duration: 0.06)
                        CubicKeyframe(0, duration: 0.5)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    /// Кадр растеризатора на всё поле: пиксели крупные, без сглаживания. Палец в любом месте ведёт Шибу.
    private var view3D: some View {
        ZStack(alignment: .topLeading) {
            Self.night
            if let frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: field.width, height: field.height)
            }
            ForEach(pops) { p in
                if let at = marks[p.id] {
                    ZombiePopView(pop: p)
                        .position(x: at.x * field.width, y: at.y * field.height)
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { s in
            field = s
            if frozen { redraw() }
        }
        .contentShape(Rectangle())
        .gesture(steer)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Коридор: \(ZombieRun.friendsText(round.friends)), сердечек \(round.hearts)"))
        .accessibilityHint(Text("Веди пальцем влево и вправо"))
        .accessibilityIdentifier("zombie.view")
    }

    private var steer: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard !frozen else { return }
                if dragFrom == nil { dragFrom = target }
                // Полкоридора — примерно треть ширины экрана. +x мира — слева на экране.
                let k = 2 * ZombieRound.lane / Double(max(120, field.width) * 0.62)
                target = ZombieRound.clampX((dragFrom ?? target) - Double(v.translation.width) * k)
            }
            .onEnded { _ in dragFrom = nil }
    }

    private var hud: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<round.maxHearts, id: \.self) { i in
                    Image(systemName: i < round.hearts ? "heart.fill" : "heart")
                        .foregroundStyle(i < round.hearts ? PetPalette.red : Color.white.opacity(0.45))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .font(.system(size: 17, weight: .bold))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(.black.opacity(0.42)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Сердечек: \(round.hearts) из \(round.maxHearts)"))
            .accessibilityIdentifier("zombie.hearts")
            ZombieChip(icon: "star.fill", tint: PetPalette.yellow, text: "\(round.score)")
                .accessibilityLabel(Text("Счёт: \(round.score)"))
                .accessibilityIdentifier("zombie.score")
            Spacer(minLength: 0)
            ZombieChip(icon: "timer", tint: Color.white.opacity(0.8), text: "\(Int(round.timeLeft.rounded(.up)))")
                .accessibilityLabel(Text("Осталось секунд: \(Int(round.timeLeft.rounded(.up)))"))
                .accessibilityIdentifier("zombie.time")
        }
    }

    @ViewBuilder
    private var hint: some View {
        let text = round.t < 5 ? PetNames.adapt("Веди пальцем — Шиба сам кидает игрушки", name: model.snap.name)
            : (round.canBark ? "Шкала полная — гавкни!" : ZombieRun.friendsText(round.friends))
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.42)))
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.25), value: text)
            .allowsHitTesting(false)
            .accessibilityIdentifier("zombie.hint")
    }

    /// «Гав!»: кольцо вокруг копится за друзей; полное — кнопка рыжая и качается.
    private var barkButton: some View {
        let fill = Double(round.meter) / Double(ZombieRound.barkNeed)
        let ready = round.canBark
        return Button {
            bark()
        } label: {
            ZStack {
                Circle()
                    .fill(ready ? PetPalette.accent : Color.black.opacity(0.45))
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 6)
                    .padding(3)
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(ready ? Color.white : PetPalette.yellow, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                    .animation(.spring(duration: 0.3), value: fill)
                Text("Гав!")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(ready ? Color.white : Color.white.opacity(0.6))
            }
            .frame(width: 84, height: 84)
            .contentShape(Circle())
        }
        .buttonStyle(SquishStyle())
        .phaseAnimator([1.0, 1.08], trigger: ready ? barkPulse + 1 : 0) { view, s in
            view.scaleEffect(ready ? s : 1)
        } animation: { _ in .spring(duration: 0.25, bounce: 0.5) }
        .accessibilityLabel(Text("Гав"))
        .accessibilityValue(Text(ready ? "Готово" : "Копится: \(round.meter) из \(ZombieRound.barkNeed)"))
        .accessibilityHint(Text(ready ? "Ближние зомби станут друзьями, дальние попятятся"
                                      : "Копится, когда зомби становятся друзьями"))
        .accessibilityIdentifier("zombie.bark")
    }

    // MARK: ход раунда

    private func start() {
        guard gate == nil else {
            model.haptic(.warning)
            SoundKit.shared.play(.refuse)
            return
        }
        model.haptic(.light)
        SoundKit.shared.play(.button)
        begin(ZombieRound(seed: Env.isUITest ? Self.testSeed : UInt64.random(in: 1...UInt64.max)))
        frozen = false
        phase = .playing
        runID += 1
    }

    private func begin(_ r: ZombieRound) {
        round = r
        target = r.puppyX
        dragFrom = nil
        pops = []
        marks = [:]
        frame = nil
    }

    /// Кадры примерно по 1/60 с. Время раунда — сумма шагов, а не часы: в фоне, вне активного состояния
    /// и на подвисании оно стоит (FrameClock), и кадр тогда не рисуется.
    /// Кадр рисуется вне главного потока; пока рисуется, раунд идёт дальше со следующего шага.
    private func loop() async {
        guard phase == .playing, !frozen else { return }
        var clock = FrameClock(now: ProcessInfo.processInfo.systemUptime)
        while !Task.isCancelled, phase == .playing, !round.isOver {
            try? await Task.sleep(for: .milliseconds(FrameClock.waitMs(running: live)))
            let dt = clock.tick(now: ProcessInfo.processInfo.systemUptime, running: live)
            guard dt > 0 else { continue }
            handle(round.advance(to: round.t + dt, target: target))
            pops.removeAll { round.t - $0.t > ZombiePop.life }
            await draw()
        }
        guard !Task.isCancelled, phase == .playing, round.isOver else { return }
        // Последний кадр — секунду посмотреть, чем кончилось.
        model.haptic(round.survived ? .success : .warning)
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        finish()
    }

    private func handle(_ events: [ZombieEvent]) {
        for e in events {
            switch e {
            case .thrown:
                break
            case .hit:
                model.haptic(.light)
            case .friend(_, let kind, let points, let x, let z):
                addPop(ZombiePop(id: nextPop, t: round.t, text: "+\(points)", kind: .friend,
                                 world: RVec(x, 1.25 * kind.size + 0.35, z)))
                model.haptic(kind == .big ? .medium : .light)
                SoundKit.shared.play(kind == .big ? .yip : .boop)
                if round.canBark { barkPulse += 1 }
            case .hug:
                addPop(ZombiePop(id: nextPop, t: round.t, text: "Обслюнявил!", kind: .hug,
                                 world: RVec(round.puppyX, 1.3, 0.2)))
                slobber += 1
                model.haptic(.warning)
                SoundKit.shared.play(.heartLost)
            case .bark, .over:
                break
            }
        }
    }

    private func bark() {
        guard phase == .playing, !frozen else { return }
        guard case .bark(let made, _)? = round.bark() else {
            model.haptic(.warning)
            return
        }
        addPop(ZombiePop(id: nextPop, t: round.t, text: made > 0 ? "ГАВ! +\(ZombieRun.friendsText(made))" : "ГАВ!",
                         kind: .bark, world: RVec(round.puppyX, 1.55, 1.2)))
        model.haptic(.success)
        SoundKit.shared.play(.yip)
    }

    private func addPop(_ p: ZombiePop) {
        pops.append(p)
        nextPop += 1
    }

    /// Нарисовать кадр раунда в фоне и показать.
    private func draw() async {
        guard field.width > 0 else { return }
        let r = round
        let aspect = Double(field.height / field.width)
        let at = pops.map { ($0.id, $0.world) }
        let px = await Task.detached(priority: .userInitiated) {
            ZombieFrames.play(r, aspect: aspect, marks: at)
        }.value
        guard !Task.isCancelled else { return }
        frame = px.image
        marks = px.marks
    }

    /// Кадр сразу, на главном потоке: снимок UI-теста и смена размера.
    private func redraw() {
        guard field.width > 0, phase == .playing else { return }
        let px = ZombieFrames.play(round, aspect: Double(field.height / field.width), marks: pops.map { ($0.id, $0.world) })
        frame = px.image
        marks = px.marks
    }

    private func makePosters() async {
        guard posterIntro == nil else { return }
        let a = await Task.detached(priority: .userInitiated) { ZombieFrames.poster(happy: false) }.value
        let b = await Task.detached(priority: .userInitiated) { ZombieFrames.poster(happy: true) }.value
        posterIntro = a.image
        posterDone = b.image
    }

    /// Записать итог: монеты, рекорд, «Поиграть» в ядре. Потом — карточка итога.
    private func finish() {
        guard phase == .playing else { return }
        let r0 = round
        let r: ZombieResult
        do {
            r = try PetStore.shared.mutate { f in ZombieRun.finish(r0, in: &f, now: Clock.now()) }
        } catch {
            model.show(RefuseText.text("store"), ok: false)
            model.showZombie = false
            return
        }
        model.refresh()
        Task { await AppActions.shared.afterChange() }
        dragFrom = nil
        phase = .done(r)
        model.haptic(.success)
        SoundKit.shared.play(r.isRecord && r.score > 0 ? .hearts : .ok)
    }

    /// Закрыть экран. Посреди раунда с очками — сначала засчитать его; после раунда Шиба в комнате радуется.
    private func close() {
        switch phase {
        case .intro:
            model.showZombie = false
        case .playing:
            guard round.score > 0, !frozen else {
                runID += 1
                model.showZombie = false
                return
            }
            finish()
            if case .done(let r) = phase {
                model.showZombie = false
                model.cheerZombie(r, toast: true)
            }
        case .done(let r):
            model.showZombie = false
            model.cheerZombie(r, toast: false)
        }
    }

    /// PET_ZOMBIE=play|done — детерминированные снимки (сид 7, автопилот).
    private func uiTestSetup() {
        guard Env.isUITest, phase == .intro, let mode = Env.value("PET_ZOMBIE") else { return }
        switch mode {
        case "play":
            let r = ZombieRun.autoplay(seed: Self.testSeed, until: Self.testFreeze)
            begin(r)
            // Подпись над последним другом, как будто он только что поймал игрушку.
            if let zb = r.zombies.last(where: { !$0.isActive }) {
                pops = [ZombiePop(id: 0, t: r.t, text: "+\(zb.kind.points)", kind: .friend,
                                  world: RVec(zb.x, 1.25 * zb.kind.size + 0.35, zb.z))]
                nextPop = 1
            }
            frozen = true
            phase = .playing
            redraw()
        case "done":
            begin(ZombieRun.autoplay(seed: Self.testSeed))
            frozen = true
            phase = .playing
            finish()
        default:
            break
        }
    }
}

// MARK: - Кадры

/// Готовый кадр: пиксели и где на нём подписи (доли ширины и высоты).
struct ZombieFrame: Sendable {
    var w = 0
    var h = 0
    var rgba: [UInt8] = []
    var marks: [Int: CGPoint] = [:]

    var image: CGImage? {
        guard w > 0, h > 0, rgba.count == w * h * 4,
              let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

enum ZombieFrames {
    /// Кадр раунда под соотношение сторон поля (высота/ширина) и экранные места подписей.
    static func play(_ r: ZombieRound, aspect: Double, marks: [(Int, RVec)]) -> ZombieFrame {
        var c = RetroCanvas(w: ZombieArt.width, h: ZombieArt.height(for: aspect))
        ZombieArt.render(r, into: &c)
        var at: [Int: CGPoint] = [:]
        for (id, p) in marks {
            if let s = c.project(p) { at[id] = CGPoint(x: s.x / Double(c.w), y: s.y / Double(c.h)) }
        }
        return ZombieFrame(w: c.w, h: c.h, rgba: c.rgba(), marks: at)
    }

    /// Постер для карточек: до раунда — зомби бредут из тумана, после — стали друзьями.
    static func poster(happy: Bool) -> ZombieFrame {
        var c = RetroCanvas(w: ZombieArt.width, h: ZombieArt.height(for: 0.62))
        ZombieArt.poster(into: &c, happy: happy)
        return ZombieFrame(w: c.w, h: c.h, rgba: c.rgba())
    }
}

// MARK: - Подписи и мелочи

/// «+15» над новым другом, «Обслюнявил!» над Шибой, «ГАВ!» — крупно.
struct ZombiePop: Identifiable, Equatable {
    enum Kind: Equatable { case friend, hug, bark }
    static let life = 0.9

    let id: Int
    let t: Double
    let text: String
    let kind: Kind
    let world: RVec

    static func == (a: ZombiePop, b: ZombiePop) -> Bool { a.id == b.id }
}

private struct ZombiePopView: View {
    let pop: ZombiePop
    @State private var up = false

    var body: some View {
        Text(pop.text)
            .font(.system(size: pop.kind == .bark ? 30 : 20, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.6), radius: 0, x: 2, y: 2)
            .fixedSize()
            .offset(y: up ? -26 : 0)
            .scaleEffect(up ? 1 : 0.6)
            .opacity(up ? 1 : 0.4)
            .onAppear {
                withAnimation(.spring(duration: 0.45, bounce: 0.45)) { up = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch pop.kind {
        case .friend: return PetPalette.yellow
        case .hug: return PetPalette.blush
        case .bark: return .white
        }
    }
}

/// Счёт и таймер поверх кадра: тёмная капсула, белые цифры.
private struct ZombieChip: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .font(.system(size: 17, weight: .bold, design: .rounded))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Capsule().fill(.black.opacity(0.42)))
        .accessibilityElement(children: .ignore)
    }
}

/// Постер в карточке: пиксели крупные, края скруглены.
private struct ZombiePoster: View {
    let image: CGImage?

    var body: some View {
        ZStack {
            ZombieRunScreen.night
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
            }
        }
        .aspectRatio(CGFloat(ZombieArt.width) / CGFloat(ZombieArt.height(for: 0.62)), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityHidden(true)
    }
}

// MARK: - Карточки

/// «Играть»: постер, правила, рекорд, сколько монет ещё дадут сегодня.
private struct ZombieIntroCard: View {
    @Environment(AppModel.self) private var model
    let poster: CGImage?
    let gate: String?
    let best: Int
    let left: Int
    let start: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZombiePoster(image: poster)
            Text("Зомби просто хотят обниматься")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)
            Text(PetNames.adapt("Веди Шибу пальцем — он сам кидает игрушки. Попал — зомби стал другом. Друзья копят «Гав!»: лай отгоняет всех рядом. Дошёл до Шибы — обслюнявил, минус сердечко.", name: model.snap.name))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalette.soft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                GamePill(icon: "trophy.fill", tint: PetPalette.yellow, text: best > 0 ? "Рекорд \(best)" : "Рекорда пока нет")
                    .accessibilityIdentifier("zombie.best")
                GamePill(icon: "", emoji: "🪙", tint: PetPalette.accent,
                         text: left > 0 ? "Ещё до \(EconText.coins(left))" : "Монеты на сегодня всё")
                    .accessibilityIdentifier("zombie.left")
            }
            if let gate {
                HStack(spacing: 8) {
                    Image(systemName: gate == "asleep" ? "moon.zzz.fill" : (gate == "away" ? "figure.walk" : "exclamationmark.circle.fill"))
                        .accessibilityHidden(true)
                    Text(Tricks.reasonText(gate))
                        .multilineTextAlignment(.leading)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(PetPalette.soft.opacity(0.14)))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("zombie.gate")
            }
            GameButton(title: "Играть", icon: "play.fill", enabled: gate == nil, action: start)
                .accessibilityIdentifier("zombie.play")
        }
        .padding(16)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 28).fill(PetPalette.card))
    }
}

/// Итог: постер с друзьями, заголовок, счёт, друзья и сердечки, награда, «Ещё раз» и «Готово».
private struct ZombieDoneCard: View {
    @Environment(AppModel.self) private var model
    let poster: CGImage?
    let result: ZombieResult
    let again: Bool
    let start: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZombiePoster(image: poster)
            Text(ZombieRun.resultTitle(result))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("zombie.title")
            Text("\(result.score)")
                .font(.system(size: 50, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PetPalette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel(Text("Счёт: \(result.score)"))
                .accessibilityIdentifier("zombie.final")
            HStack(spacing: 10) {
                GamePill(icon: "face.smiling.inverse", tint: PetPalette.green, text: ZombieRun.friendsText(result.friends))
                GamePill(icon: "heart.fill", tint: PetPalette.red,
                         text: result.survived ? "\(result.hearts) " + EconText.plural(result.hearts, "сердечко", "сердечка", "сердечек") : "Обслюнявили")
            }
            Text("Рекорд \(result.best)")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalette.soft)
            if let reward = ZombieRun.rewardText(result) {
                Text(reward)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(result.totalCoins > 0 ? PetPalette.accent : PetPalette.soft)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(PetPalette.accent.opacity(result.totalCoins > 0 ? 0.16 : 0.06)))
                    .accessibilityIdentifier("zombie.reward")
            }
            if result.played {
                Text(PetNames.adapt("Шибе было весело!", name: model.snap.name))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.green)
            }
            HStack(spacing: 10) {
                GameButton(title: "Ещё раз", icon: "arrow.counterclockwise", enabled: again, action: start)
                    .accessibilityIdentifier("zombie.again")
                GameButton(title: "Готово", icon: "checkmark", enabled: true, filled: false, action: close)
                    .accessibilityIdentifier("zombie.done")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 28).fill(PetPalette.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zombie.result")
    }
}
