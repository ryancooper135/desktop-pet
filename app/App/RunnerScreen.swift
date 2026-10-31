// Мини-игра «Раннер» (волна 55b): бесконечный забег пса по его миру — двор → район → парк. На весь экран,
// открывается из меню «Мини-игры» (GamesButton) и по pet://runner. Три состояния, как у «Лови мячик» и «Блок Дуо»:
// карточка «Играть», забег, карточка итога.
// Логика — Runner (Shared): трасса от сида, полосы, прыжок и подкат, удары, монеты, рекорд, награда по правилам
// мини-игр (MiniGames: пёс занят — «просто так», общий дневной потолок). Тут только вид, свайпы, звук и VoiceOver.
// 3D — RunnerScene.swift (та же модель породы, простые фигуры из пулов).
// Решения (Вадим может поменять):
// • свайп влево/вправо — полоса, вверх — прыжок (лужи, клумбы), вниз — подкат (лавки, голуби); ящик — только обежать;
// • три сердечка; после удара секунда неуязвимости (пёс мигает), сбитая вещь исчезает;
// • закрыл посреди забега — забег засчитан как есть (как в «Блок Дуо»);
// • после забега, когда экран закрылся, пёс в комнате радуется и говорит фразу (AppModel.cheerRunner).
// Фон: уход приложения в фон — время забега стоит (scenePhase → session.live), вернулся — бежим дальше.
// UI-тесты: PET_RUNNER=play — забег на 20-й секунде (автопилот, сид 7), стоит; PET_RUNNER=done — пробежан до конца
// автопилотом и записан, видна карточка итога.

import RealityKit
import SwiftUI
import UIKit
@preconcurrency import PetCore

struct RunnerScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    private enum Phase: Equatable {
        case intro
        case playing
        case done(RunnerResult)
    }

    @State private var phase: Phase = .intro
    @State private var session = RunnerSession()
    /// Забег «просто так» (MiniGames.busy на старте); nil — настоящий.
    @State private var free: String?
    /// Номер забега: перезапускает запасной цикл времени.
    @State private var runID = 0
    /// Сцена рождается после въезда экрана (вид, созданный за краем, на CI оставался пустым — см. YardStage).
    @State private var sceneOn = false
    /// Свайп уже сработал в этом касании.
    @State private var latched = false

    /// Сид UI-тестов: одна и та же трасса на каждом прогоне.
    static let testSeed: UInt64 = 7
    /// На какой секунде замирает PET_RUNNER=play.
    static let testFreezeAt = 20.0
    /// Сколько пройти пальцем, чтобы свайп сработал.
    private static let swipeAt: CGFloat = 28

    var body: some View {
        ZStack {
            LinearGradient(colors: RunnerWorld.sky(session.biome), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.2), value: session.biome)
            scene
                .ignoresSafeArea()
            if phase == .playing { track }
            VStack(spacing: 0) {
                topBar
                ChallengeBadge(game: .runner)
                if phase == .playing { hud }
                Spacer(minLength: 0)
                switch phase {
                case .intro:
                    RunnerIntroCard(note: note, best: model.file?.runnerBest ?? 0, left: coinsLeft) { start() }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                case .playing:
                    EmptyView()
                case .done(let r):
                    RunnerDoneCard(result: r, start: { start() }, close: { close() })
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
        }
        .onAppear {
            session.world.bind(session)
            session.world.loadDog()
            uiTestSetup()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            sceneOn = true
        }
        // Запасной ход времени: на CI RealityView под fullScreenCover может не нарисовать ни кадра.
        .task(id: runID) {
            guard runID > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(FrameClock.waitMs(running: session.running && session.live)))
                session.frame(now: ProcessInfo.processInfo.systemUptime, render: false)
            }
        }
        .onChange(of: session.over) { _, over in
            if over, phase == .playing { finish() }
        }
        .onChange(of: session.ahead) { _, text in
            guard phase == .playing, session.running, UIAccessibility.isVoiceOverRunning else { return }
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        .onChange(of: scenePhase, initial: true) { _, p in
            session.live = p == .active
        }
        .onDisappear { closedFromOutside() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runner.screen")
    }

    private var note: String? {
        model.file.flatMap { MiniGames.note($0, at: model.snap.t, left: coinsLeft) }
    }

    private var busyNow: String? {
        model.file.flatMap { MiniGames.busy($0, at: model.snap.t) }
    }

    private var coinsLeft: Int {
        model.file.map { Runner.coinsLeft($0, now: model.snap.t) } ?? 0
    }

    // MARK: сцена

    @ViewBuilder private var scene: some View {
        if sceneOn {
            RealityView { content in
                content.camera = .virtual
                RunnerTickSystem.registerOnce()
                content.add(session.world.root)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    // MARK: верх

    private var topBar: some View {
        HStack {
            Text(RunnerConfig.shared.name)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PetPalette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(SquishStyle())
            .bGlass(Circle(), interactive: true)
            .accessibilityLabel(Text("Закрыть"))
            .accessibilityHint(Text(phase == .playing && session.metres > 0 ? "Забег засчитается как есть" : ""))
            .accessibilityIdentifier("runner.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Сердечки, метры, косточки, где бежим — значок и число.
    private var hud: some View {
        HStack(spacing: 8) {
            BChip(icon: "heart.fill", text: "\(session.lives)", color: PetPalette.red)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Сердечек: \(session.lives)"))
                .accessibilityIdentifier("runner.lives")
            BChip(icon: "figure.run", text: "\(session.metres) м", color: PetPalette.accent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(session.metres) метров"))
                .accessibilityIdentifier("runner.metres")
            BChip(icon: "🦴", text: "\(session.picked)", emoji: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Косточек: \(session.picked)"))
                .accessibilityIdentifier("runner.picked")
            BChip(icon: session.biome.icon, text: session.biome.title, color: PetPalette.green)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("runner.biome")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .allowsHitTesting(false)
    }

    // MARK: управление

    /// Весь экран — поле свайпов; для VoiceOver — один элемент «Дорожка»: смахивание вверх/вниз меняет полосу,
    /// двойное касание — прыжок, действие «Подкат».
    private var track: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        guard !latched else { return }
                        let dx = v.translation.width, dy = v.translation.height
                        guard max(abs(dx), abs(dy)) >= Self.swipeAt else { return }
                        latched = true
                        if abs(dx) > abs(dy) {
                            session.swipe(dx < 0 ? .left : .right)
                        } else {
                            session.swipe(dy < 0 ? .jump : .slide)
                        }
                    }
                    .onEnded { _ in latched = false }
            )
            .accessibilityElement()
            .accessibilityLabel(Text("Дорожка"))
            .accessibilityValue(Text("\(["левая полоса", "средняя полоса", "правая полоса"][session.lane]). \(session.ahead)"))
            .accessibilityHint(Text("Смахни вверх или вниз — сменить полосу. Двойное касание — прыжок."))
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: session.swipe(.right)
                case .decrement: session.swipe(.left)
                @unknown default: break
                }
            }
            .accessibilityAction { session.swipe(.jump) }
            .accessibilityAction(named: Text("Подкат")) { session.swipe(.slide) }
            .accessibilityIdentifier("runner.track")
    }

    // MARK: забег

    private func start() {
        free = busyNow
        Feel.tap(.button)
        session.calm = Motion.reduce
        session.start(seed: Env.isUITest ? Self.testSeed : UInt64.random(in: 1...UInt64.max))
        runID += 1
        phase = .playing
    }

    /// Записать итог: монеты, рекорд, «Поиграть» в ядре. Потом — карточка итога, пёс садится.
    private func finish() {
        guard phase == .playing else { return }
        let run = session.run
        let free = free
        session.stop(pose: .sit)
        let r: RunnerResult
        do {
            r = try PetStore.shared.mutate { f in
                Challenges.play(.runner, in: &f, now: Clock.now()) { g, t in Runner.finish(run, in: &g, now: t, free: free) }
            }
        } catch {
            model.refuse(RefuseText.text("store"))
            model.showRunner = false
            return
        }
        model.refresh()
        Task { await AppActions.shared.afterChange() }
        phase = .done(r)
        Feel.success(CoinChime.cue(.miniGame(coins: r.coins, record: r.isRecord && r.score > 0)))
    }

    /// Закрыть экран. Посреди забега с метрами — сначала засчитать его; после забега пёс в комнате радуется.
    private func close() {
        guard model.showRunner else { return }
        switch phase {
        case .intro:
            model.showRunner = false
        case .playing:
            guard session.run.score > 0, !session.frozen else {
                session.stop(pose: .idle)
                model.showRunner = false
                return
            }
            finish()
            if case .done(let r) = phase {
                model.showRunner = false
                model.cheerRunner(r, toast: true)
            }
        case .done(let r):
            model.showRunner = false
            model.cheerRunner(r, toast: false)
        }
    }

    /// Экран закрыли не крестиком (pet://home из виджета, острова, уведомления): забег засчитывается так же.
    private func closedFromOutside() {
        guard phase == .playing, session.run.score > 0, !session.frozen else {
            session.stop(pose: .idle)
            return
        }
        finish()
        if case .done(let r) = phase { model.cheerRunner(r, toast: true) }
    }

    /// PET_RUNNER=play|done — детерминированные снимки (сид 7, автопилот).
    private func uiTestSetup() {
        guard Env.isUITest, phase == .intro, let mode = Env.value("PET_RUNNER") else { return }
        free = busyNow
        session.calm = true
        switch mode {
        case "play":
            session.load(Runner.autoplay(seed: Self.testSeed, until: Self.testFreezeAt), running: false)
            session.world.clip(.run)
            phase = .playing
        case "done":
            session.load(Runner.autoplay(seed: Self.testSeed), running: false)
            phase = .playing
            finish()
        default:
            break
        }
    }
}

// MARK: - Карточки

/// «Играть»: три правила значками, рекорд, сколько монет ещё можно, плашка «просто так».
private struct RunnerIntroCard: View {
    @Environment(AppModel.self) private var model
    let note: String?
    let best: Int
    let left: Int
    let start: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            BIconCircle(icon: "figure.run", color: PetPalette.accent, size: 52)
                .accessibilityHidden(true)
            Text(PetNames.adapt("Бежим с Шибой: двор, район, парк", name: model.snap.name))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                BChip(icon: "arrow.left.and.right", text: "ящик", color: PetPalette.food)
                BChip(icon: "arrow.up", text: "лужа", color: PetPalette.wash)
                BChip(icon: "arrow.down", text: "лавка", color: PetPalette.vio)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Свайп влево или вправо — обежать ящик. Вверх — прыжок через лужу или клумбу. "
                + "Вниз — подкат под лавку или голубей. "
                + PetNames.adapt(A11y.gameNote(.runner), name: model.snap.name)))
            .accessibilityIdentifier("runner.rules")
            HStack(spacing: 8) {
                BChip(icon: "trophy.fill", text: best > 0 ? "\(best)" : "—", color: PetPalette.yellow)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(best > 0 ? "Рекорд \(best)" : "Рекорда пока нет"))
                    .accessibilityIdentifier("runner.best")
                BChip(icon: "🪙", text: left > 0 ? "\(left)" : "0", emoji: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(left > 0 ? "Ещё до \(EconText.coins(left)) сегодня" : "Монеты на сегодня всё"))
                    .accessibilityIdentifier("runner.left")
            }
            if let note {
                HStack(spacing: 8) {
                    Image(systemName: MiniGames.noteIcon(note))
                        .accessibilityHidden(true)
                    Text(MiniGames.noteText(note, name: model.snap.name))
                        .multilineTextAlignment(.leading)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(PetPalette.soft.opacity(0.14)))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("runner.gate")
            }
            GameButton(title: "Играть", icon: "play.fill", enabled: true, action: start)
                .accessibilityIdentifier("runner.play")
        }
        .frame(maxWidth: 420)
        .bCard(padding: 20, corner: 28)
    }
}

/// Итог: заголовок, очки, метры и косточки, награда, «Ещё раз» и «Готово».
private struct RunnerDoneCard: View {
    @Environment(AppModel.self) private var model
    let result: RunnerResult
    let start: () -> Void
    let close: () -> Void

    var body: some View {
        let record = result.isRecord && result.score > 0
        VStack(spacing: 12) {
            BIconCircle(icon: record ? "trophy.fill" : (result.finished ? "flag.checkered" : "figure.run"),
                        color: record ? PetPalette.yellow : PetPalette.accent, size: 52, bounce: record ? 1 : 0)
                .accessibilityHidden(true)
            Text(Runner.resultTitle(result))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("runner.title")
                .accessibilityAddTraits(.isHeader)
            Text("\(result.score)")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PetPalette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel(Text("Очки: \(result.score)"))
                .accessibilityIdentifier("runner.final")
            HStack(spacing: 8) {
                BChip(icon: "figure.run", text: "\(result.metres) м", color: PetPalette.accent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(result.metres) метров"))
                BChip(icon: "🦴", text: "\(result.picked)", emoji: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Косточек: \(result.picked)"))
                BChip(icon: "trophy.fill", text: "\(result.best)", color: PetPalette.yellow)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Рекорд \(result.best)"))
            }
            if let reward = Runner.rewardText(result) {
                Text(reward)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(result.totalCoins > 0 ? PetPalette.accent : PetPalette.soft)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(PetPalette.accent.opacity(result.totalCoins > 0 ? 0.16 : 0.06)))
                    .accessibilityIdentifier("runner.reward")
            }
            HStack(spacing: 10) {
                GameButton(title: "Ещё раз", icon: "arrow.counterclockwise", enabled: true, action: start)
                    .accessibilityIdentifier("runner.again")
                GameButton(title: "Готово", icon: "checkmark", enabled: true, filled: false, action: close)
                    .accessibilityIdentifier("runner.done")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 420)
        .bCard(padding: 20, corner: 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runner.result")
    }
}
