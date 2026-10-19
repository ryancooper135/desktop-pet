// Мини-игра «Блок Дуо» (волна 12): на весь экран, открывается из меню кнопки «Мини-игры» (GamesButton) и по
// pet://blockduo. Три состояния, как у «Лови мячик»: карточка «Играть», партия, карточка итога с монетами.
// Логика — BlockDuo (Shared): раздача от сида, линии, комбо, ход Шибы, награда. Тут только вид, перетаскивание,
// анимация ходов по шагам, хаптика и звук.
// Решения (Вадим может поменять):
// • фигуру тащишь пальцем из тройки внизу; на поле она висит выше пальца (иначе палец закрывает место),
//   место подсвечено её цветом, линии, которые исчезнут, — светлее;
// • клетки Шибы — рыжие с лапкой, его последний ход обведён, пока ты не сходишь; пока он «думает», тройка пустая;
// • закрыл посреди партии — партия засчитана как есть (монеты по очкам), чтобы долгая игра не пропадала;
// • после партии, когда экран закрылся, Шиба в комнате подпрыгивает, виляет и говорит фразу (AppModel.cheerBlockDuo).
// UI-тесты: PET_BLOCKDUO=play — партия на 10-м ходу (автопилот, сид 7), фигура зависла над местом с подсветкой;
// PET_BLOCKDUO=done — партия сыграна автопилотом до конца и записана, видна карточка итога.

import SwiftUI
@preconcurrency import PetCore

struct BlockDuoScreen: View {
    @Environment(AppModel.self) private var model

    private enum Phase: Equatable {
        case intro
        case playing
        case done(BlockDuoResult)
    }

    /// Фигура в руке: из какого места тройки и где палец (в координатах экрана игры).
    private struct Drag: Equatable {
        var slot: Int
        var loc: CGPoint
    }

    @State private var phase: Phase = .intro
    @State private var game = BlockDuoGame(seed: 1)
    /// Что нарисовано: идёт за game с задержкой, пока проигрываются шаги хода (легла фигура → мигнули линии → ход Шибы).
    @State private var shown = [UInt8](repeating: 0, count: BlockDuo.cells)
    @State private var shownTray: [BlockPiece?] = [nil, nil, nil]
    @State private var flash: Set<Int> = []
    /// Клетки последнего хода Шибы — обведены до следующего хода.
    @State private var shibaMark: Set<Int> = []
    @State private var drag: Drag? = nil
    /// Снимок UI-теста: фигура висит над этим местом.
    @State private var pinned: (slot: Int, at: BlockCell)? = nil
    @State private var busy = false
    @State private var status = ""
    @State private var pop: ScorePop? = nil
    @State private var boardFrame: CGRect = .zero
    @State private var anim: Task<Void, Never>? = nil
    @State private var bounce = 0

    /// Сид UI-тестов: одна и та же партия на каждом прогоне.
    static let testSeed: UInt64 = 7
    /// На каком ходу замирает PET_BLOCKDUO=play.
    static let testFreezeMoves = 10
    /// На сколько фигура в руке выше пальца.
    private static let lift: CGFloat = 76
    private static let space = "blockduo.space"
    private static let gap: CGFloat = 3

    var body: some View {
        VStack(spacing: 0) {
            topBar
            switch phase {
            case .intro:
                Spacer(minLength: 0)
                BlockIntroCard(gate: gate, best: model.file?.blockduoBest ?? 0, left: coinsLeft) { start() }
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            case .playing:
                playArea
            case .done(let r):
                Spacer(minLength: 0)
                BlockDoneCard(result: r, again: gate == nil, start: { start() }, close: { close() })
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            }
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .onAppear { uiTestSetup() }
        .onDisappear { anim?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blockduo.screen")
    }

    private var gate: String? {
        guard let f = model.file else { return Tricks.loadingReason }
        return BlockDuo.gate(f, at: model.snap.t)
    }

    private var coinsLeft: Int {
        model.file.map { BlockDuo.coinsLeft($0, now: model.snap.t) } ?? 0
    }

    // MARK: верх

    private var topBar: some View {
        HStack {
            Text(BlockDuoConfig.shared.name)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
            Spacer()
            Button {
                model.haptic(.light)
                close()
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
            .accessibilityHint(Text(phase == .playing && game.score > 0 ? "Партия засчитается с текущим счётом" : ""))
            .accessibilityIdentifier("blockduo.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var hud: some View {
        HStack(spacing: 8) {
            GameChip(icon: "star.fill", tint: PetPalette.yellow, text: "\(game.score)")
                .accessibilityLabel(Text("Общий счёт: \(game.score)"))
                .accessibilityIdentifier("blockduo.score")
            GameChip(icon: "pawprint.fill", tint: PetPalette.fur, text: "\(game.shiba)")
                .accessibilityLabel(Text("Очки Шибы: \(game.shiba)"))
                .accessibilityIdentifier("blockduo.shiba")
            Spacer(minLength: 0)
            if game.combo > 1 {
                GameChip(icon: "flame.fill", tint: PetPalette.red, text: "×\(game.combo)")
                    .accessibilityLabel(Text("Комбо \(game.combo)"))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: game.combo > 1)
    }

    // MARK: партия

    private var playArea: some View {
        VStack(spacing: 0) {
            hud
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            board
                .padding(.horizontal, 16)
            Text(status)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 22)
                .padding(.top, 10)
                .contentTransition(.opacity)
                .accessibilityIdentifier("blockduo.status")
            Spacer(minLength: 8)
            tray
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .overlay { floating }
        .coordinateSpace(.named(Self.space))
    }

    private var cellSize: CGFloat {
        boardFrame.width > 0 ? (boardFrame.width - 16 - Self.gap * 7) / 8 : 36
    }

    private var board: some View {
        let pv = currentPreview
        let preview = Set(pv?.cells ?? [])
        let clearing = pv?.clearing ?? []
        let color = currentPiece?.color ?? 1
        return VStack(spacing: Self.gap) {
            ForEach(0..<BlockDuo.size, id: \.self) { r in
                HStack(spacing: Self.gap) {
                    ForEach(0..<BlockDuo.size, id: \.self) { c in
                        let i = r * BlockDuo.size + c
                        BoardCell(value: shown[i],
                                  ghost: preview.contains(i) ? color : nil,
                                  clearing: clearing.contains(i),
                                  flash: flash.contains(i),
                                  shibaMark: shibaMark.contains(i) && shown[i] == BlockDuo.shibaColor)
                    }
                }
            }
        }
        .padding(8)
        .aspectRatio(1, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 22).fill(PetPalette.card))
        .overlay { popView }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { boardFrame = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Поле 8 на 8, занято клеток: \(shown.filter { $0 != 0 }.count)"))
        .accessibilityIdentifier("blockduo.board")
    }

    @ViewBuilder
    private var popView: some View {
        if let pop {
            VStack(spacing: 2) {
                Text(pop.text)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                if let sub = pop.sub {
                    Text(sub)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(pop.shiba ? PetPalette.furDark : PetPalette.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(PetPalette.card.opacity(0.92)))
            .id(pop.id)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private var tray: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { slot in
                TraySlot(piece: shownTray[slot], cell: min(cellSize * 0.5, 19), gap: 2,
                         lifted: drag?.slot == slot || pinned?.slot == slot,
                         fits: shownTray[slot].map { game.fitsAnywhere($0) } ?? true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 118)
                    .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
                    .contentShape(Rectangle())
                    .gesture(dragGesture(slot))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(shownTray[slot] == nil ? "Пусто" : "Фигура \(slot + 1)"))
                    .accessibilityIdentifier("blockduo.slot.\(slot)")
            }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: bounce) { view, s in
            view.scaleEffect(s)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.94, duration: 0.08)
                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            }
        }
    }

    /// Фигура в руке: размером с клетки поля, над пальцем.
    @ViewBuilder
    private var floating: some View {
        if let p = currentPiece, let center = floatCenter {
            PieceView(form: p.form, color: p.color, cell: cellSize, gap: Self.gap)
                .opacity(currentPreview == nil ? 0.75 : 0.95)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .position(center)
                .allowsHitTesting(false)
        }
    }

    private var currentSlot: Int? { drag?.slot ?? pinned?.slot }

    private var currentPiece: BlockPiece? {
        guard let slot = currentSlot, shownTray.indices.contains(slot) else { return nil }
        return shownTray[slot]
    }

    /// Центр фигуры в руке. Снимок UI-теста — прямо над своим местом, чуть выше (как будто сейчас отпустят).
    private var floatCenter: CGPoint? {
        guard let p = currentPiece else { return nil }
        if let d = drag { return CGPoint(x: d.loc.x, y: d.loc.y - Self.lift) }
        guard let pin = pinned, boardFrame.width > 0 else { return nil }
        let step = cellSize + Self.gap
        return CGPoint(x: boardFrame.minX + 8 + (CGFloat(pin.at.c) + CGFloat(p.form.w) / 2) * step - Self.gap / 2,
                       y: boardFrame.minY + 8 + (CGFloat(pin.at.r) + CGFloat(p.form.h) / 2) * step - Self.gap / 2 - 6)
    }

    /// Куда ляжет фигура в руке: левый верхний угол рамки — ближайшая клетка под ним.
    private var target: BlockCell? {
        if let pin = pinned { return pin.at }
        guard let p = currentPiece, let center = floatCenter, boardFrame.width > 0 else { return nil }
        let step = cellSize + Self.gap
        let x = center.x - CGFloat(p.form.w) * step / 2 - boardFrame.minX - 8
        let y = center.y - CGFloat(p.form.h) * step / 2 - boardFrame.minY - 8
        return BlockCell(r: Int((y / step).rounded()), c: Int((x / step).rounded()))
    }

    private var currentPreview: BlockPreview? {
        guard let slot = currentSlot, let at = target, !busy || pinned != nil else { return nil }
        return game.preview(slot: slot, at: at)
    }

    private func dragGesture(_ slot: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { v in
                guard pinned == nil, !busy, shownTray[slot] != nil else { return }
                if drag == nil {
                    model.haptic(.light)
                }
                let old = currentPreview?.cells
                drag = Drag(slot: slot, loc: v.location)
                // Щелчок, когда фигура «встала» на новое место.
                if let now = currentPreview?.cells, now != old { model.haptic(.light) }
            }
            .onEnded { _ in
                guard let d = drag else { return }
                let at = target
                drag = nil
                guard let at, game.preview(slot: d.slot, at: at) != nil else {
                    // Отпустил мимо — фигура вернулась в тройку.
                    model.haptic(.warning)
                    SoundKit.shared.play(.refuse)
                    return
                }
                commit(slot: d.slot, at: at)
            }
    }

    // MARK: ходы

    private func start() {
        guard gate == nil else {
            model.haptic(.warning)
            SoundKit.shared.play(.refuse)
            return
        }
        model.haptic(.light)
        SoundKit.shared.play(.button)
        anim?.cancel()
        begin(BlockDuoGame(seed: Env.isUITest ? Self.testSeed : UInt64.random(in: 1...UInt64.max)))
        phase = .playing
    }

    private func begin(_ g: BlockDuoGame) {
        game = g
        shown = g.board
        shownTray = g.tray
        flash = []
        shibaMark = g.lastShiba.map { Set($0.cells).subtracting($0.cleared) } ?? []
        drag = nil
        pinned = nil
        busy = false
        pop = nil
        status = Self.hint(g)
    }

    /// «Ещё 2 фигуры — потом ходит Шиба».
    private static func hint(_ g: BlockDuoGame) -> String {
        let left = g.tray.compactMap { $0 }.count
        switch left {
        case 3: return "Ставь фигуры — после трёх ходит Шиба"
        case 2: return "Ещё две фигуры — потом ход Шибы"
        default: return "Последняя фигура — и ход Шибы"
        }
    }

    /// Поставить фигуру. Состояние партии меняется сразу, а на экран ход выходит по шагам.
    private func commit(slot: Int, at: BlockCell) {
        guard let turn = game.place(slot: slot, at: at) else { return }
        let after = game
        busy = true
        shownTray[slot] = nil
        shibaMark = []
        anim = Task { @MainActor in
            await show(turn.mine)
            if turn.dealt {
                if let s = turn.shiba {
                    status = "Шиба думает, куда поставить…"
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    await show(s)
                    shibaMark = Set(s.cells).subtracting(s.cleared)
                    status = s.lines > 0 ? "Шиба убрал линию! Гав!" : "Шиба поставил свою фигурку"
                } else if turn.shibaSkipped {
                    status = "Шибе некуда поставить — пропускает ход"
                    model.haptic(.light)
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { shownTray = after.tray }
                bounce += 1
            } else {
                status = Self.hint(after)
            }
            shown = after.board
            busy = false
            if after.isOver {
                status = "Места больше нет"
                model.haptic(.warning)
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                finish()
            }
        }
    }

    /// Один ход на экране: фигура легла → полные линии вспыхнули → исчезли.
    private func show(_ m: BlockMove) async {
        withAnimation(.spring(duration: 0.2)) { shown = m.placed }
        model.haptic(m.who == .me ? .light : .medium)
        SoundKit.shared.play(.boop)
        guard !m.cleared.isEmpty else {
            if m.who == .shiba { showPop(ScorePop(text: "+\(m.gained)", sub: "Шиба", shiba: true)) }
            try? await Task.sleep(for: .milliseconds(m.who == .me ? 120 : 350))
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.12)) { flash = Set(m.cleared) }
        model.haptic(.success)
        SoundKit.shared.play(.yip)
        var sub: [String] = []
        if m.who == .shiba { sub.append("Шиба") }
        if m.combo > 1 { sub.append("комбо ×\(m.combo)") }
        if m.perfect { sub.append("чистое поле!") }
        showPop(ScorePop(text: "+\(m.gained)", sub: sub.isEmpty ? nil : sub.joined(separator: " · "), shiba: m.who == .shiba))
        try? await Task.sleep(for: .milliseconds(260))
        guard !Task.isCancelled else { return }
        var b = m.placed
        for i in m.cleared { b[i] = 0 }
        withAnimation(.easeOut(duration: 0.22)) {
            shown = b
            flash = []
        }
        try? await Task.sleep(for: .milliseconds(220))
    }

    private func showPop(_ p: ScorePop) {
        withAnimation(.spring(duration: 0.25, bounce: 0.4)) { pop = p }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if pop?.id == p.id { withAnimation(.easeOut(duration: 0.25)) { pop = nil } }
        }
    }

    /// Записать итог: монеты, рекорд, «Поиграть» в ядре. Потом — карточка итога.
    private func finish() {
        guard phase == .playing else { return }
        let g = game
        let r: BlockDuoResult
        do {
            r = try PetStore.shared.mutate { f in BlockDuo.finish(g, in: &f, now: Clock.now()) }
        } catch {
            model.show(RefuseText.text("store"), ok: false)
            model.showBlockDuo = false
            return
        }
        model.refresh()
        Task { await AppActions.shared.afterChange() }
        anim?.cancel()
        busy = false
        drag = nil
        phase = .done(r)
        model.haptic(.success)
        SoundKit.shared.play(r.isRecord && r.score > 0 ? .hearts : .ok)
    }

    /// Закрыть экран. Посреди партии с очками — сначала засчитать её; после партии Шиба в комнате радуется.
    private func close() {
        switch phase {
        case .intro:
            model.showBlockDuo = false
        case .playing:
            guard game.score > 0, !Env.isUITest || pinned == nil else {
                anim?.cancel()
                model.showBlockDuo = false
                return
            }
            finish()
            if case .done(let r) = phase {
                model.showBlockDuo = false
                model.cheerBlockDuo(r, toast: true)
            }
        case .done(let r):
            model.showBlockDuo = false
            model.cheerBlockDuo(r, toast: false)
        }
    }

    /// PET_BLOCKDUO=play|done — детерминированные снимки (сид 7, автопилот).
    private func uiTestSetup() {
        guard Env.isUITest, phase == .intro, let mode = Env.value("PET_BLOCKDUO") else { return }
        switch mode {
        case "play":
            let g = BlockDuo.autoplay(seed: Self.testSeed, moves: Self.testFreezeMoves)
            begin(g)
            if let m = BlockDuo.pilotMove(g) { pinned = (m.slot, m.at) }
            phase = .playing
        case "done":
            begin(BlockDuo.autoplay(seed: Self.testSeed))
            phase = .playing
            finish()
        default:
            break
        }
    }
}

/// «+240 · комбо ×2» над полем.
private struct ScorePop: Equatable {
    let id = UUID()
    let text: String
    var sub: String? = nil
    var shiba = false
}

// MARK: - Клетки и фигуры

enum BlockPalette {
    /// Цвета 1…8 веб-версии, приглушённые под тёплую палитру приложения; 9 — Шиба (рыжий, как шерсть).
    static func color(_ v: UInt8) -> Color {
        switch v {
        case 1: return Color(hex: 0xef6f6c)
        case 2: return Color(hex: 0xf5a04a)
        case 3: return Color(hex: 0xf2c84b)
        case 4: return Color(hex: 0x6cc58a)
        case 5: return Color(hex: 0x4fbfd6)
        case 6: return Color(hex: 0x6f8ff0)
        case 7: return Color(hex: 0xa883e8)
        case 8: return Color(hex: 0xef86c4)
        case BlockDuo.shibaColor: return PetPalette.fur
        default: return PetPalette.soft.opacity(0.13)
        }
    }
}

/// Одна клетка: цветной кубик с бликом; у Шибы — лапка. ghost — сюда ляжет фигура в руке.
private struct BoardCell: View {
    let value: UInt8
    let ghost: UInt8?
    let clearing: Bool
    let flash: Bool
    let shibaMark: Bool

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                if value != 0 {
                    BlockCube(color: BlockPalette.color(value), paw: value == BlockDuo.shibaColor, size: s)
                } else if let ghost {
                    RoundedRectangle(cornerRadius: s * 0.22)
                        .fill(BlockPalette.color(ghost).opacity(0.45))
                } else {
                    RoundedRectangle(cornerRadius: s * 0.22)
                        .fill(BlockPalette.color(0))
                }
                if clearing {
                    // Эта линия исчезнет, если отпустить здесь.
                    RoundedRectangle(cornerRadius: s * 0.22)
                        .fill(Color.white.opacity(0.38))
                    RoundedRectangle(cornerRadius: s * 0.22)
                        .strokeBorder(PetPalette.yellow, lineWidth: max(1.5, s * 0.07))
                }
                if shibaMark {
                    RoundedRectangle(cornerRadius: s * 0.22)
                        .strokeBorder(PetPalette.furDark, lineWidth: max(1.5, s * 0.08))
                }
                if flash {
                    RoundedRectangle(cornerRadius: s * 0.22)
                        .fill(Color.white.opacity(0.85))
                }
            }
            .scaleEffect(flash ? 1.12 : 1)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Кубик: заливка, светлый верх и тень снизу — объём, как в веб-версии, но мягче.
private struct BlockCube: View {
    let color: Color
    var paw = false
    let size: CGFloat

    var body: some View {
        let r = size * 0.22
        ZStack {
            RoundedRectangle(cornerRadius: r).fill(color)
            RoundedRectangle(cornerRadius: r)
                .fill(LinearGradient(colors: [.white.opacity(0.32), .clear, .black.opacity(0.12)],
                                     startPoint: .top, endPoint: .bottom))
            if paw {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(PetPalette.cream.opacity(0.9))
            }
        }
    }
}

/// Фигура из кубиков (в тройке — мелко, в руке — размером с клетки поля).
private struct PieceView: View {
    let form: BlockShape
    let color: UInt8
    let cell: CGFloat
    let gap: CGFloat

    var body: some View {
        let step = cell + gap
        ZStack(alignment: .topLeading) {
            ForEach(form.cells, id: \.self) { c in
                BlockCube(color: BlockPalette.color(color), paw: color == BlockDuo.shibaColor, size: cell)
                    .frame(width: cell, height: cell)
                    .offset(x: CGFloat(c.c) * step, y: CGFloat(c.r) * step)
            }
        }
        .frame(width: CGFloat(form.w) * step - gap, height: CGFloat(form.h) * step - gap, alignment: .topLeading)
    }
}

/// Место в тройке: фигура или пусто. Фигура, которой некуда встать, — бледная.
private struct TraySlot: View {
    let piece: BlockPiece?
    let cell: CGFloat
    let gap: CGFloat
    let lifted: Bool
    let fits: Bool

    var body: some View {
        ZStack {
            if let piece {
                PieceView(form: piece.form, color: piece.color, cell: cell, gap: gap)
                    .opacity(lifted ? 0.2 : (fits ? 1 : 0.35))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Карточки

/// «Играть»: правила в две строки, рекорд, сколько монет ещё дадут сегодня.
private struct BlockIntroCard: View {
    let gate: String?
    let best: Int
    let left: Int
    let start: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                PieceView(form: BlockShape("XX\nX.", 1), color: 6, cell: 20, gap: 2)
                PieceView(form: BlockShape("XX", 1), color: BlockDuo.shibaColor, cell: 20, gap: 2)
                PieceView(form: BlockShape("X\nX\nX", 1), color: 4, cell: 20, gap: 2)
            }
            .accessibilityHidden(true)
            Text("Собирай линии вместе с Шибой")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)
            Text("Тащи фигуры на поле. Полная строка или столбец исчезают. После каждых трёх фигур свою ставит Шиба — счёт общий.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalette.soft)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                GamePill(icon: "trophy.fill", tint: PetPalette.yellow, text: best > 0 ? "Рекорд \(best)" : "Рекорда пока нет")
                    .accessibilityIdentifier("blockduo.best")
                GamePill(icon: "", emoji: "🪙", tint: PetPalette.accent,
                         text: left > 0 ? "Ещё до \(EconText.coins(left))" : "Монеты на сегодня всё")
                    .accessibilityIdentifier("blockduo.left")
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
                .accessibilityIdentifier("blockduo.gate")
            }
            GameButton(title: "Играть", icon: "play.fill", enabled: gate == nil, action: start)
                .accessibilityIdentifier("blockduo.play")
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 28).fill(PetPalette.card))
    }
}

/// Итог: заголовок, общий счёт, кто сколько, линии и комбо, награда, «Ещё раз» и «Готово».
private struct BlockDoneCard: View {
    let result: BlockDuoResult
    let again: Bool
    let start: () -> Void
    let close: () -> Void

    var body: some View {
        let record = result.isRecord && result.score > 0
        VStack(spacing: 12) {
            Image(systemName: record ? "trophy.fill" : "square.grid.3x3.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(record ? PetPalette.yellow : PetPalette.accent)
                .accessibilityHidden(true)
            Text(BlockDuo.resultTitle(result))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("blockduo.title")
            Text("\(result.score)")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PetPalette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel(Text("Общий счёт: \(result.score)"))
                .accessibilityIdentifier("blockduo.final")
            HStack(spacing: 10) {
                GamePill(icon: "hand.point.up.left.fill", tint: PetPalette.accent, text: "Ты \(result.mine.formatted())")
                GamePill(icon: "pawprint.fill", tint: PetPalette.fur, text: "Шиба \(result.shiba.formatted())")
            }
            Text("Линий \(result.lines) · лучшее комбо ×\(max(result.maxCombo, 1)) · рекорд \(result.best)")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalette.soft)
                .multilineTextAlignment(.center)
            if let reward = BlockDuo.rewardText(result) {
                Text(reward)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(result.totalCoins > 0 ? PetPalette.accent : PetPalette.soft)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(PetPalette.accent.opacity(result.totalCoins > 0 ? 0.16 : 0.06)))
                    .accessibilityIdentifier("blockduo.reward")
            }
            if result.played {
                Text("Шибе было весело!")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.green)
            }
            HStack(spacing: 10) {
                GameButton(title: "Ещё раз", icon: "arrow.counterclockwise", enabled: again, action: start)
                    .accessibilityIdentifier("blockduo.again")
                GameButton(title: "Готово", icon: "checkmark", enabled: true, filled: false, action: close)
                    .accessibilityIdentifier("blockduo.done")
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 28).fill(PetPalette.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blockduo.result")
    }
}
