// Волна 18: «что нужно сейчас» и обучение жестам на главном экране.
// Что показать, решает Shared/NeedHint.swift (NeedHints.pick, NeedHints.gates, Tips) — здесь только вид и Coach:
// • плашка «что нужно сейчас» над рядом «Гулять» (hint.plate): тап делает дело или показывает, где оно делается;
// • обучение ласке — палец ходит по Шибе и подпись «Проведи пальцем по Шибе» (tip.pet): новичку и когда просит;
// • ручка «Шкалы» под панелью (open.needs): то же, что свайп вверх, но видно и нажимается;
// • разовые подсказки других жестов (tip.gesture): щекотка, свайп вверх — по одной, с крестиком;
// • подсветка кнопки панели, к которой ведёт плашка или неактивная «Гулять».
// Решения и почему так — DECISIONS.md, «Волна 18: подсказки и жесты».

import SwiftUI
@preconcurrency import PetCore

/// Учитель на главном: подсветка кнопок, обучение ласке, разовые подсказки жестов.
/// Отдельно от AppModel: экранное состояние подсказок, ядро и стор его не видят (кроме TipLog в SaveFile).
@MainActor @Observable
final class Coach {
    static let shared = Coach()

    /// Подсказки жестов. В тестах выключены (снимки и UI-тесты не должны зависеть от пальца поверх Шибы),
    /// кроме PET_TIPS=1 — снимок ui-89. Плашка и бейджи кнопок от этого не зависят.
    static let enabled = !Env.isTesting || Env.value("PET_TIPS") == "1"
    /// Тап по плашке «Погладить»: столько секунд палец показывается даже выученному хозяину.
    static let forcedTutorS: Double = 12
    /// После удачной ласки обучение не возвращается столько секунд (даже если пёс опять просит).
    static let tutorRestS: Double = 600
    /// Сколько секунд держится подсветка кнопки.
    static let highlightS: Double = 2.4

    /// Палец показан по тапу (плашка или пузырь «Погладь меня»), независимо от счётчика.
    private(set) var tutorForced = false
    /// До этого момента (часы приложения) обучение само не показывается: только что погладили или закрыли.
    private(set) var tutorQuietUntil: Double = 0
    /// Кнопка панели, которую сейчас подсвечиваем (feed, pet, play, bath, walk).
    private(set) var highlight: String? = nil
    /// Растёт на каждую подсветку: кольцо пульсирует заново, даже если кнопка та же.
    private(set) var highlightId = 0
    /// Разовая подсказка жеста на экране.
    private(set) var gestureTip: GestureTip? = nil

    @ObservationIgnored private var forceTask: Task<Void, Never>?
    @ObservationIgnored private var highlightTask: Task<Void, Never>?
    @ObservationIgnored private var tipTask: Task<Void, Never>?
    /// Тост «только что гладил» уже сказан для отката, что кончается в этот момент.
    @ObservationIgnored private var cooldownToldUntil: Double = 0

    private init() {}

    // MARK: обучение ласке

    /// Показывать ли палец сейчас. Только при чистой сцене и когда ласка пройдёт (на откате пальцем не погладить).
    func showTutor(file: SaveFile?, snap: PetSnapshot, petReady: Bool, sceneClear: Bool) -> Bool {
        guard Self.enabled, sceneClear, petReady, snap.alive, snap.level < 3, let f = file else { return false }
        if tutorForced { return true }
        guard snap.t >= tutorQuietUntil else { return false }
        return Tips.showPetTutor(f.tips, wantsPet: snap.want == "pet", petReady: petReady, now: snap.t)
    }

    /// Показать палец по просьбе (тап по плашке или пузырю), на forcedTutorS секунд или до ласки.
    func forceTutor() {
        tutorForced = true
        forceTask?.cancel()
        forceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.forcedTutorS))
            if Task.isCancelled { return }
            self?.tutorForced = false
        }
    }

    /// Провели пальцем по Шибе (StrokeEvent.stroke). Ласка пройдёт — засчитать в обучение и убрать палец.
    /// Действие ядру уходит всегда: отказ (откат) объясняет AppActions → petRefused.
    func stroked(_ model: AppModel) {
        let now = Clock.now()
        let ready = model.file.map { NeedHints.gates($0, at: now)["pet"]?.ok ?? true } ?? false
        if ready, model.snap.alive, model.snap.pose != .away {
            _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in Tips.noteStroke(&f.tips, at: now) }
            tutorForced = false
            forceTask?.cancel()
            tutorQuietUntil = now + Self.tutorRestS
            offerGestureTip(model)
        }
        model.act(.pet)
    }

    /// Ласка из приложения упёрлась в откат: один тост на окно отката («ещё раз через 2 мин»), дальше тихо —
    /// кнопка и так показывает бейдж с минутами, а частые поглаживания не должны сыпать тостами.
    func petRefused(_ model: AppModel) {
        let now = Clock.now()
        guard let f = model.file, let until = NeedHints.gates(f, at: now)["pet"]?.until, until > now else { return }
        guard until > cooldownToldUntil else { return }
        cooldownToldUntil = until
        model.show("Только что гладил — ещё раз через \(NeedHints.minutesLeft(until, now: now))", ok: false, emoji: "⏳")
        highlightButton("pet")
    }

    // MARK: подсветка кнопок

    func highlightButton(_ kind: String) {
        highlight = kind
        highlightId += 1
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.highlightS))
            if Task.isCancelled { return }
            self?.highlight = nil
        }
    }

    // MARK: плашка и пузырь

    /// Тап по плашке «что нужно сейчас» или по пузырю-мысли: сделать или показать, где это делается.
    func go(_ hint: NeedHint, _ model: AppModel) {
        switch hint.go {
        case .feed:
            highlightButton("feed")
            model.act(.feed(Catalog.mainFood))
        case .bath:
            highlightButton("bath")
            model.act(.bath)
        case .play:
            highlightButton("play")
            model.act(.play)
        case .pet:
            // Погладить кнопкой можно, но просит он руку — учим жесту, кнопку подсвечиваем как запасной путь.
            forceTutor()
            highlightButton("pet")
            if !Self.enabled { model.show(hint.detail) }
        case .walk:
            highlightButton("walk")
            model.act(.walk)
        case .none:
            model.show(hint.detail, ok: false)
        }
    }

    /// Пузырь «Погладь меня» и другие мысли: есть плашка — как она, нет — шкалы.
    func tapThought(_ model: AppModel) {
        if let f = model.file, let hint = NeedHints.pick(model.snap, file: f) {
            go(hint, model)
        } else {
            model.showNeeds = true
        }
    }

    // MARK: разовые подсказки жестов

    /// После удачной ласки — следующая невиданная подсказка жеста (щекотка, свайп), через паузу, на gestureTipFor секунд.
    private func offerGestureTip(_ model: AppModel) {
        guard Self.enabled, gestureTip == nil, let f = try? PetStore.shared.read() else { return }
        guard let tip = Tips.nextGesture(f.tips, name: f.petName) else { return }
        tipTask?.cancel()
        tipTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled, model.sceneClear else { return }
            self.gestureTip = tip
            self.markSeen(tip.key)
            try? await Task.sleep(for: .seconds(Tips.gestureTipFor))
            if Task.isCancelled { return }
            if self.gestureTip == tip { self.gestureTip = nil }
        }
    }

    /// Крестик на подсказке жеста.
    func dismissGestureTip() {
        tipTask?.cancel()
        gestureTip = nil
    }

    /// Жест сделан сам (щекотка, свайп вверх) — подсказка о нём больше не нужна.
    func performed(_ key: String) {
        guard Self.enabled else { return }
        if gestureTip?.key == key { dismissGestureTip() }
        markSeen(key)
    }

    private func markSeen(_ key: String) {
        guard let f = try? PetStore.shared.read(), !f.tips.seen.contains(key) else { return }
        _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in Tips.markSeen(&f.tips, key) }
    }
}

// MARK: - Цвета кнопок

enum ActTint {
    /// Насыщенный цвет активной кнопки панели: иконка и подпись на нём белые.
    static func color(_ kind: String) -> Color {
        switch kind {
        case "feed": return Color(hex: 0xe8793f)
        case "pet": return Color(hex: 0xe0607e)
        case "play": return Color(hex: 0x4fa85a)
        case "bath": return Color(hex: 0x4a90d9)
        case "walk": return Color(hex: 0x8a6fd1)
        case "wake": return Color(hex: 0xd99a1e)
        case "bed": return Color(hex: 0x6b6fd6)
        default: return PetPalette.accent
        }
    }
}

/// Кольцо подсветки вокруг кнопки: пульсирует, пока Coach.highlight на этом виде.
struct HighlightRing: ViewModifier {
    let kind: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let coach = Coach.shared
        let on = coach.highlight == kind
        content
            .overlay {
                if on {
                    Capsule()
                        .strokeBorder(ActTint.color(kind), lineWidth: 3)
                        .padding(-4)
                        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.35, 1.0]) { ring, a in
                            ring.opacity(a)
                        } animation: { _ in .easeInOut(duration: 0.4) }
                        .id(coach.highlightId)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: on)
    }
}

extension View {
    func coachHighlight(_ kind: String) -> some View { modifier(HighlightRing(kind: kind)) }
}

// MARK: - Плашка «что нужно сейчас»

/// Плашка над рядом «Гулять»: значок, что сделать и как; справа — куда ведёт. Тихая (откат, отдых) — без стрелки,
/// приглушённая. Всё хорошо — её нет (NeedHints.pick == nil).
struct NeedHintPlate: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 12
    /// Над панелью места мало: дальше кегли не растут (подпись ужмётся или перенесётся).
    static let titleMax: CGFloat = 20
    static let detailMax: CGFloat = 16

    var body: some View {
        if let f = model.file, let hint = NeedHints.pick(snap, file: f) {
            plate(hint)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func plate(_ hint: NeedHint) -> some View {
        let tint = hint.quiet ? PetPalette.soft : ActTint.color(hint.go.rawValue)
        return Button {
            Coach.shared.go(hint, model)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: hint.quiet ? "clock.fill" : hint.icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(tint))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hint.title)
                        .font(.system(size: min(titleSize, Self.titleMax), weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    Text(hint.detail)
                        .font(.system(size: min(detailSize, Self.detailMax), weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                }
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let then = hint.then, !hint.quiet {
                    // «Сначала покормить → Гулять»: куда это ведёт.
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right")
                        Image(systemName: "figure.walk")
                        Text(then)
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ActTint.color("walk"))
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityHidden(true)
                }
                if !hint.quiet {
                    Image(systemName: hint.go == .pet ? "hand.draw.fill" : "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(hint.urgent ? PetPalette.red : tint.opacity(hint.quiet ? 0.2 : 0.55),
                                  lineWidth: hint.urgent ? 2 : 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.label(hint)))
        .accessibilityHint(Text(Self.a11yHint(hint)))
        .accessibilityAddTraits(hint.quiet ? [] : .isButton)
        .accessibilityIdentifier("hint.plate")
    }

    /// VoiceOver: «Сейчас нужно: сначала покормить, потом гулять».
    static func label(_ h: NeedHint) -> String {
        var s = "Сейчас нужно: \(h.title)"
        if let then = h.then { s += ", потом \(then.lowercased())" }
        return s
    }

    static func a11yHint(_ h: NeedHint) -> String {
        switch h.go {
        case .pet: return "Погладить можно действием «Погладить» на питомце"
        case .none: return h.detail
        default: return "Дважды коснитесь, чтобы сделать"
        }
    }
}

// MARK: - Обучение ласке

/// Палец ходит по спине Шибы туда-обратно, под ним дорожка длиной с засчитанную ласку и подпись.
/// Касания не ловит: гладить сквозь него. Reduce Motion — палец стоит, дорожка со стрелками.
struct PetTutorOverlay: View {
    /// Кто в комнате (snap.name): своему персонажу — «Проведи пальцем по питомцу».
    var name: String = PetNames.shiba
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var textSize: CGFloat = 15
    /// Дорожка = StrokeTracker.strokePath: столько пути и засчитывает одна ласка.
    static let track: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.5)
            ZStack {
                Capsule()
                    .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 7]))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: Self.track, height: 26)
                    .shadow(color: .black.opacity(0.25), radius: 3)
                    .overlay {
                        if reduceMotion {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                        }
                    }
                    .position(center)
                finger
                    .position(x: center.x, y: center.y + 26)
                Text(Tips.petTutorText(name: name))
                    .font(.system(size: min(textSize, 20), weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(PetPalette.card).shadow(color: .black.opacity(0.15), radius: 6, y: 2))
                    .position(x: center.x, y: center.y + 92)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Tips.petTutorLabel(name: name)))
        .accessibilityIdentifier("tip.pet")
    }

    @ViewBuilder private var finger: some View {
        let hand = Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 40, weight: .regular))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        if reduceMotion {
            hand
        } else {
            hand.phaseAnimator([-1.0, 1.0]) { v, x in
                v.offset(x: x * Self.track / 2)
            } animation: { _ in .easeInOut(duration: 1.1) }
        }
    }
}

// MARK: - Ручка «Шкалы»

/// Под панелью действий: то же, что свайп вверх по Шибе. Нажать или потянуть вверх — откроются шкалы.
struct NeedsHandle: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 12

    var body: some View {
        Button {
            Coach.shared.performed("swipe")
            model.showNeeds = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.up")
                    .font(.system(size: min(size, 16), weight: .heavy))
                Text("Шкалы")
                    .font(.system(size: min(size, 16), weight: .bold, design: .rounded))
            }
            .foregroundStyle(PetPalette.soft)
            .padding(.horizontal, 16)
            .frame(minWidth: 120, minHeight: 32)
            .background(Capsule().fill(PetPalette.card.opacity(0.85)))
            .contentShape(Capsule())
        }
        .buttonStyle(SquishStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onEnded { g in
                if g.translation.height < -12 {
                    Coach.shared.performed("swipe")
                    model.showNeeds = true
                }
            }
        )
        .accessibilityLabel(Text("Шкалы"))
        .accessibilityHint(Text("Все шкалы питомца"))
        .accessibilityIdentifier("open.needs")
    }
}

// MARK: - Разовая подсказка жеста

/// «Четыре быстрых тапа по Шибе — щекотка» с крестиком. Сама уходит через Tips.gestureTipFor секунд.
struct GestureTipChip: View {
    let tip: GestureTip
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tip.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PetPalette.accent)
                .accessibilityHidden(true)
            Text(tip.text)
                .font(.system(size: min(size, 17), weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Button {
                Coach.shared.dismissGestureTip()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PetPalette.soft)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Закрыть подсказку"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .background(Capsule().fill(PetPalette.card).shadow(color: .black.opacity(0.12), radius: 6, y: 2))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tip.gesture")
    }
}
