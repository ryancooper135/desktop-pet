// Мини-игра «Лови мячик» (волна 9): на весь экран, открывается из меню круглой кнопки «Мини-игры» в ряду над панелью
// (GamesButton в конце файла, волна 12) и по pet://catch. Три состояния: карточка «Играть» (рекорд, сколько монет
// ещё можно сегодня), сам раунд (сверху падают мячики и косточки, миску водишь пальцем внизу) и карточка итога.
// Логика — CatchGame (Shared): раскладка от сида, поимка, награда, запись в сейв. Тут только вид, цикл кадров,
// хаптика и звук.
// Решения (Вадим может поменять): на весь экран, а не листом — лист тянулся бы вниз вместе с миской;
// миска — простая фигура, мячик — tennisball.fill, косточка нарисована фигурами (своего SF Symbol у неё нет);
// ушёл в фон или открыл Пункт управления посреди раунда — время стоит (FrameClock: шаг не больше 1/20 с, вне
// активного состояния 0, цикл просыпается раз в 1/4 с).
// UI-тесты: PET_CATCH=play — раунд замер на 12-й секунде (автопилот, сид 7), PET_CATCH=done — раунд сыгран
// автопилотом и записан, видна карточка итога.

import SwiftUI
@preconcurrency import PetCore

struct CatchGameScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    private enum Phase: Equatable {
        case intro
        case playing
        case done(CatchResult)
    }

    @State private var phase: Phase = .intro
    @State private var round = CatchRound(seed: 1)
    @State private var bowlX = 0.5
    @State private var pops: [CatchPop] = []
    @State private var catches = 0
    @State private var runID = 0
    /// Снимок для UI-теста: раунд не идёт сам.
    @State private var frozen = false
    /// Приложение активно — зеркало scenePhase для цикла кадров: окружение, взятое задачей, не обновляется.
    @State private var live = true
    /// Раунд «просто так» (волна 32): причина MiniGames.busy на старте; nil — настоящий.
    @State private var free: String?

    /// Сид UI-тестов: одна и та же раскладка на каждом прогоне.
    static let testSeed: UInt64 = 7
    /// Где замирает PET_CATCH=play.
    static let testFreezeT = 12.0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ChallengeBadge(game: .ball)
            switch phase {
            case .intro:
                Spacer(minLength: 0)
                IntroCard(note: note, name: model.snap.name, best: model.file?.catchBest ?? 0, left: coinsLeft) { start() }
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            case .playing:
                hud
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                field
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            case .done(let r):
                Spacer(minLength: 0)
                DoneCard(result: r, start: { start() }, close: { model.showCatch = false })
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            }
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .task(id: runID) { await loop() }
        .onChange(of: scenePhase, initial: true) { _, p in live = p == .active }
        .onAppear { uiTestSetup() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch.screen")
    }

    /// Плашка «просто так» на карточке «Играть» (волна 32): пёс занят или монеты на сегодня кончились. Играть можно всегда.
    private var note: String? {
        model.file.flatMap { MiniGames.note($0, at: model.snap.t, left: coinsLeft) }
    }

    /// Занят ли пёс прямо сейчас — тогда раунд «просто так».
    private var busyNow: String? {
        model.file.flatMap { MiniGames.busy($0, at: model.snap.t) }
    }

    private var coinsLeft: Int {
        model.file.map { CatchGame.coinsLeft($0, now: model.snap.t) } ?? 0
    }

    // MARK: верх

    private var topBar: some View {
        HStack {
            Text(CatchConfig.shared.name)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                model.showCatch = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PetPalette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(SquishStyle())
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel(Text("Закрыть"))
            .accessibilityIdentifier("catch.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var hud: some View {
        HStack(spacing: 10) {
            GameChip(icon: "star.fill", tint: PetPalette.yellow, text: "\(round.score)")
                .accessibilityLabel(Text("Очки: \(round.score)"))
                .accessibilityIdentifier("catch.score")
            GameChip(icon: "timer", tint: PetPalette.accent, text: "\(Int(round.timeLeft.rounded(.up)))")
                .accessibilityLabel(Text("Осталось секунд: \(Int(round.timeLeft.rounded(.up)))"))
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(0..<round.maxMisses, id: \.self) { i in
                    Image(systemName: i < round.missed ? "heart.slash.fill" : "heart.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(i < round.missed ? PetPalette.soft.opacity(0.6) : PetPalette.red)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(PetPalette.card))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Промахов: \(round.missed) из \(round.maxMisses)"))
            .accessibilityIdentifier("catch.misses")
        }
    }

    // MARK: поле

    private var field: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let ball = CGFloat(CatchGame.radius * 2) * w
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 24).fill(PetPalette.card)
                // Пунктир, куда опускается миска.
                Path { p in
                    p.move(to: CGPoint(x: 16, y: CGFloat(CatchGame.catchY) * h + ball * 0.9))
                    p.addLine(to: CGPoint(x: w - 16, y: CGFloat(CatchGame.catchY) * h + ball * 0.9))
                }
                .stroke(PetPalette.soft.opacity(0.18), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 8]))
                ForEach(round.visible, id: \.index) { d in
                    DropView(kind: d.kind, size: ball)
                        .position(x: CGFloat(d.x) * w, y: CGFloat(d.y(at: round.t)) * h)
                }
                ForEach(pops) { p in
                    PopLabel(pop: p, age: round.t - p.t)
                        .position(x: CGFloat(p.x) * w, y: popY(h: h, ball: ball))
                }
                BowlView(width: CGFloat(CatchGame.bowlHalf * 2) * w, bounce: catches)
                    .position(x: CGFloat(bowlX) * w, y: CGFloat(CatchGame.catchY) * h + ball * 0.35)
                    // Волна 31: с VoiceOver миску двигают смахиванием вверх/вниз — шестая часть хода за раз.
                    .accessibilityValue(Text(A11y.side(bowlX, in: CatchGame.bowlRange)))
                    .accessibilityAdjustableAction { dir in
                        guard !frozen else { return }
                        bowlX = A11y.nudge(bowlX, up: dir.isUp, range: CatchGame.bowlRange)
                    }
                    .accessibilityIdentifier("catch.bowl")
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard !frozen, w > 0 else { return }
                        bowlX = CatchGame.clampBowl(Double(v.location.x / w))
                    }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch.field")
    }

    /// Где всплывает «+1»: чуть выше миски (дальше поднимает PopLabel).
    private func popY(h: CGFloat, ball: CGFloat) -> CGFloat {
        CGFloat(CatchGame.catchY) * h - ball * 1.2
    }

    // MARK: раунд

    private func start() {
        free = busyNow
        Feel.prepare(.tap, .nudge)
        Feel.tap(.button)
        round = CatchRound(seed: Env.isUITest ? Self.testSeed : UInt64.random(in: 1...UInt64.max))
        bowlX = 0.5
        pops = []
        frozen = false
        phase = .playing
        runID += 1
    }

    /// Кадры примерно по 1/60 с. Время раунда — сумма шагов, а не часы: в фоне, вне активного состояния
    /// и на подвисании оно стоит (FrameClock).
    private func loop() async {
        guard phase == .playing, !frozen else { return }
        var clock = FrameClock(now: ProcessInfo.processInfo.systemUptime)
        while !Task.isCancelled, phase == .playing, !round.isOver {
            try? await Task.sleep(for: .milliseconds(FrameClock.waitMs(running: live)))
            let dt = clock.tick(now: ProcessInfo.processInfo.systemUptime, running: live)
            guard dt > 0 else { continue }
            let events = round.advance(to: round.t + dt, bowlX: bowlX)
            handle(events)
            pops.removeAll { round.t - $0.t > CatchPop.life }
        }
        if !Task.isCancelled, phase == .playing, round.isOver { finish() }
    }

    private func handle(_ events: [CatchEvent]) {
        for e in events {
            switch e {
            case .caught(let d):
                catches += 1
                pops.append(CatchPop(x: d.x, t: round.t, text: "+\(d.kind.points)", ok: true))
                Feel.tap(d.kind == .bone ? .yip : .boop)
            case .missed(let d):
                pops.append(CatchPop(x: d.x, t: round.t, text: "мимо", ok: false))
                // Промах в игре — мягкое «не то», не тревога (волна 29).
                Feel.nudge(.refuse)
            }
        }
    }

    /// Записать итог: монеты, рекорд, «Поиграть» в ядре. Потом — карточка итога.
    private func finish() {
        let r: CatchResult
        do {
            r = try PetStore.shared.mutate { f in
                Challenges.play(.ball, in: &f, now: Clock.now()) { g, t in
                    CatchGame.finish(score: round.score, caught: round.caught, missed: round.missed,
                                     in: &g, now: t, free: free)
                }
            }
        } catch {
            model.refuse(RefuseText.text("store"))
            model.showCatch = false
            return
        }
        model.refresh()
        Task { await AppActions.shared.afterChange() }
        phase = .done(r)
        Feel.success(CoinChime.cue(.miniGame(coins: r.coins, record: r.isRecord && r.score > 0)))
    }

    /// PET_CATCH=play|done — детерминированные снимки (сид 7, автопилот).
    private func uiTestSetup() {
        guard Env.isUITest, phase == .intro, let mode = Env.value("PET_CATCH") else { return }
        free = busyNow
        switch mode {
        case "play":
            let (r, x) = CatchGame.autoplay(seed: Self.testSeed, until: Self.testFreezeT)
            round = r
            bowlX = x
            frozen = true
            phase = .playing
        case "done":
            let (r, x) = CatchGame.autoplay(seed: Self.testSeed, speed: 3)
            round = r
            bowlX = x
            frozen = true
            phase = .playing
            finish()
        default:
            break
        }
    }
}

/// Всплывающее «+1» / «мимо» над миской.
/// «+1» / «мимо»: всплывает и гаснет за CatchPop.life секунд раунда.
private struct PopLabel: View {
    let pop: CatchPop
    let age: Double

    var body: some View {
        let k = max(0, age)
        let fade = max(0, 1 - k / CatchPop.life)
        Text(pop.text)
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(pop.ok ? PetPalette.green : PetPalette.red)
            .offset(y: CGFloat(-k * 60))
            .opacity(fade)
    }
}

private struct CatchPop: Identifiable {
    static let life = 0.7
    let id = UUID()
    let x: Double
    let t: Double
    let text: String
    let ok: Bool
}

// MARK: - Карточки

/// «Играть»: правила в две строки, рекорд, сколько монет ещё дадут сегодня. Пёс занят или монеты кончились —
/// плашка «играем просто так» (волна 32), но «Играть» нажимается всегда.
private struct IntroCard: View {
    let note: String?
    let name: String
    let best: Int
    let left: Int
    let start: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                DropView(kind: .ball, size: 44)
                DropView(kind: .bone, size: 44)
            }
            .accessibilityHidden(true)
            Text("Лови миской мячики и косточки")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Води миску пальцем. Мячик — 1 очко, косточка — 2. Три промаха — и всё.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalette.soft)
                .multilineTextAlignment(.center)
                // Волна 31: VoiceOver после правил слышит, как играть без пальца и чего не будет слышно.
                .accessibilityLabel(Text("Води миску пальцем. Мячик — 1 очко, косточка — 2. Три промаха — и всё. "
                    + A11y.gameNote(.catchBall)))
            HStack(spacing: 10) {
                GamePill(icon: "trophy.fill", tint: PetPalette.yellow, text: best > 0 ? "Рекорд \(best)" : "Рекорда пока нет")
                    .accessibilityIdentifier("catch.best")
                GamePill(icon: "", emoji: "🪙", tint: PetPalette.accent,
                         text: left > 0 ? "Ещё до \(EconText.coins(left))" : "Монеты на сегодня всё")
                    .accessibilityIdentifier("catch.left")
            }
            if let note {
                HStack(spacing: 8) {
                    Image(systemName: MiniGames.noteIcon(note))
                        .accessibilityHidden(true)
                    Text(MiniGames.noteText(note, name: name))
                        .multilineTextAlignment(.leading)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(PetPalette.soft.opacity(0.14)))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("catch.gate")
            }
            GameButton(title: "Играть", icon: "play.fill", enabled: true, action: start)
                .accessibilityIdentifier("catch.play")
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 28).fill(PetPalette.card))
    }
}

/// Итог: очки, заголовок, награда, «Ещё раз» и «Готово».
private struct DoneCard: View {
    @Environment(AppModel.self) private var model
    let result: CatchResult
    let start: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: result.isRecord && result.score > 0 ? "trophy.fill" : "pawprint.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(result.isRecord && result.score > 0 ? PetPalette.yellow : PetPalette.accent)
                .accessibilityHidden(true)
            Text(CatchGame.resultTitle(result))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("catch.title")
                .accessibilityAddTraits(.isHeader)
            // Звезда, как у очков в раунде (HudChip): без неё крупное «49» рядом с «Поймано 42» читалось загадкой.
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(PetPalette.yellow)
                    .accessibilityHidden(true)
                Text("\(result.score)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.ink)
                    .accessibilityLabel(Text("Очки: \(result.score)"))
                    .accessibilityIdentifier("catch.final")
            }
            Text("Поймано мячиков: \(result.caught) · рекорд \(result.best) \(EconText.plural(result.best, "очко", "очка", "очков"))")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalette.soft)
            if let reward = CatchGame.rewardText(result) {
                Text(reward)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(result.totalCoins > 0 ? PetPalette.accent : PetPalette.soft)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(PetPalette.accent.opacity(result.totalCoins > 0 ? 0.16 : 0.06)))
                    .accessibilityIdentifier("catch.reward")
            }
            if result.played {
                Text(PetNames.adapt("Шибе было весело!", name: model.snap.name))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.green)
            }
            HStack(spacing: 10) {
                GameButton(title: "Ещё раз", icon: "arrow.counterclockwise", enabled: true, action: start)
                    .accessibilityIdentifier("catch.again")
                GameButton(title: "Готово", icon: "checkmark", enabled: true, filled: false, action: close)
                    .accessibilityIdentifier("catch.done")
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 28).fill(PetPalette.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch.result")
    }
}

// MARK: - Мелочи (общие для мини-игр: и BlockDuoScreen)

struct GameButton: View {
    let title: String
    let icon: String
    let enabled: Bool
    var filled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(filled ? Color.white : PetPalette.ink)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(filled ? (enabled ? PetPalette.accent : PetPalette.soft) : PetPalette.soft.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(SquishStyle())
        .opacity(enabled ? 1 : 0.55)
        .accessibilityValue(Text(enabled ? "" : "Сейчас нельзя"))
    }
}

struct GamePill: View {
    let icon: String
    /// Монеты везде — 🪙, как в кошельке на главном.
    var emoji: String? = nil
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let emoji {
                    Text(emoji)
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                }
            }
            .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(PetPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Capsule().fill(PetPalette.soft.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

struct GameChip: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .monospacedDigit()
                .foregroundStyle(PetPalette.ink)
                .contentTransition(.numericText())
        }
        .font(.system(size: 17, weight: .bold, design: .rounded))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Capsule().fill(PetPalette.card))
        .accessibilityElement(children: .ignore)
    }
}

/// Мячик (tennisball.fill) или косточка из фигур.
private struct DropView: View {
    let kind: CatchKind
    let size: CGFloat

    var body: some View {
        switch kind {
        case .ball:
            Image(systemName: "tennisball.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(hex: 0xb8d94a))
                .frame(width: size, height: size)
        case .bone:
            BoneShape()
                .fill(PetPalette.cream)
                .overlay(BoneShape().stroke(PetPalette.furDark.opacity(0.55), lineWidth: max(1.5, size * 0.05)))
                .frame(width: size * 1.35, height: size * 0.6)
                .rotationEffect(.degrees(-20))
        }
    }
}

/// Косточка: перемычка и по два кружка на концах.
private struct BoneShape: Shape {
    func path(in r: CGRect) -> Path {
        let k = r.height / 2.0 * 0.55
        var p = Path()
        p.addRoundedRect(in: CGRect(x: r.minX + k, y: r.midY - r.height * 0.18, width: r.width - 2 * k, height: r.height * 0.36),
                         cornerSize: CGSize(width: 2, height: 2))
        for cx in [r.minX + k, r.maxX - k] {
            for cy in [r.midY - r.height * 0.25, r.midY + r.height * 0.25] {
                p.addEllipse(in: CGRect(x: cx - k, y: cy - k, width: 2 * k, height: 2 * k))
            }
        }
        return p
    }
}

/// Миска: чаша с ободком и лапкой. Подпрыгивает на каждую поимку.
private struct BowlView: View {
    let width: CGFloat
    let bounce: Int

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: width * 0.3,
                                   bottomTrailingRadius: width * 0.3, topTrailingRadius: 4)
                .fill(PetPalette.accent)
                .frame(width: width * 0.86, height: width * 0.36)
                .padding(.top, width * 0.05)
            Capsule()
                .fill(PetPalette.furDark)
                .frame(width: width, height: width * 0.1)
            Image(systemName: "pawprint.fill")
                .font(.system(size: width * 0.14, weight: .bold))
                .foregroundStyle(PetPalette.cream)
                .padding(.top, width * 0.17)
        }
        .frame(width: width, height: width * 0.42, alignment: .top)
        .keyframeAnimator(initialValue: 1.0, trigger: bounce) { view, s in
            view.scaleEffect(x: 2 - s, y: s, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.82, duration: 0.07)
                SpringKeyframe(1.0, duration: 0.25, spring: .bouncy)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Миска"))
    }
}

/// Кнопка «Мини-игры» в ряду над панелью, за «Трюками» (волна 12; в волне 9 тут был один мячик): только значок,
/// по нажатию — меню мини-игр из реестра MiniGame (волна 55; «Щенок против зомби» убран). Седьмой круг в ряд на iPhone Air уже не влезает,
/// поэтому игры живут под одной кнопкой. Волна 32: открывается всегда — спит, гуляет, устал… — игра идёт «просто так»
/// (MiniGames.busy), об этом говорит карточка «Играть». Id — open.games, пункты — open.<MiniGame.rawValue>: open.catch, open.blockduo.
struct GamesButton: View {
    @Environment(AppModel.self) private var model
    /// Время снимка: по нему MiniGames.busy.
    let t: Double

    private var busy: String? {
        model.file.flatMap { MiniGames.busy($0, at: t) }
    }

    var body: some View {
        Menu {
            ForEach(MiniGame.allCases, id: \.self) { g in
                Button {
                    open(g)
                } label: {
                    Label(g.name, systemImage: g.icon)
                }
                .accessibilityIdentifier("open.\(g.rawValue)")
            }
        } label: {
            icon
        }
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(Text("Мини-игры"))
        .accessibilityValue(Text(busy.map { MiniGames.noteText($0, name: model.snap.name) } ?? ""))
        .accessibilityHint(Text(PetNames.adapt(MiniGames.menuHint(), name: model.snap.name)))
        .accessibilityIdentifier("open.games")
    }

    /// Открыть игру реестра на весь экран. Новая игра — новый case здесь и fullScreenCover в HomeScreen.
    private func open(_ g: MiniGame) {
        switch g {
        case .ball: model.showCatch = true
        case .blockduo: model.showBlockDuo = true
        }
    }

    private var icon: some View {
        Image(systemName: "gamecontroller.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(PetPalette.ink)
            .frame(width: 48, height: 48)
            .contentShape(Circle())
    }
}
