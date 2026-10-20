// Автомат с капсулами (волна 5): цена за билетик и за монеты, шкала гаранта, крутка с анимацией и инвентарь.
// Логика — CapsuleMachine (Shared/Capsule.swift), тут только вид. Исход известен сразу (бросок детерминированный),
// анимация его только показывает: шарик дрожит цветом редкости → «Тапни, чтобы открыть» → крышка слетает,
// внутри предмет; дубликат рассыпается в клочки. Кошелёк и инвентарь обновляются после раскрытия (model.refresh).
// Решения (Вадим может поменять): без билетиков и монет кнопки не гаснут — нажатие объясняет отказ текстом.
// Волна 11: у предметов свои плоские иконки (ItemIcon), в коллекции кнопка по роли — надеть, на полку,
// играть этим; под круткой карточка «Лавка дня» открывает ShopSheet (Shared/ShopDaily.swift).

import SwiftUI
@preconcurrency import PetCore

struct CapsuleScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Phase: Equatable { case idle, shaking, ready, open }

    @State private var phase: Phase = .idle
    @State private var pull: CapsulePull?
    @State private var refusal: String?
    @State private var wobble = 0
    @State private var shattered = false
    @State private var flow: Task<Void, Never>?

    /// Сколько трясётся шарик и сколько ждёт тапа, прежде чем открыться сам.
    static let shakeFor: Double = 1.3
    static let autoOpen: Double = 3

    private var busy: Bool { phase == .shaking || phase == .ready }

    var body: some View {
        @Bindable var model = model
        let offer = model.file.map { CapsuleMachine.offer($0, at: Clock.now()) }
        ScrollView {
            VStack(spacing: 16) {
                header(offer)
                GachaBall(phase: phase, pull: pull, shattered: shattered, wobble: wobble)
                    .frame(height: 230)
                    .contentShape(Rectangle())
                    .onTapGesture { if phase == .ready { reveal() } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(ballLabel))
                    .accessibilityAddTraits(phase == .ready ? .isButton : [])
                    .accessibilityAction { if phase == .ready { reveal() } }
                    .accessibilityIdentifier("capsule.ball")
                result
                if let offer { pity(offer) }
                if let offer { buttons(offer) }
                shopCard
                inventory
            }
            .padding(20)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .sheet(isPresented: $model.showShop) {
            ShopSheet()
                .environment(model)
                .presentationDetents([.large])
        }
        .animation(.snappy, value: refusal)
        .onDisappear {
            flow?.cancel()
            model.refresh()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capsule.screen")
    }

    // MARK: части

    private func header(_ o: CapsuleOffer?) -> some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                SheetCloseButton(id: "capsule.close")
            }
            Text(o?.name ?? "Автомат")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
            if let w = model.file?.econ.wallet {
                Text("🪙 \(w.coins)   🎟 \(w.tickets)   ✂️ \(w.shards)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text("\(EconText.coins(w.coins)), \(EconText.tickets(w.tickets)), \(EconText.shards(w.shards))"))
                    .accessibilityIdentifier("capsule.wallet")
                // Волна 19: что за три значка — с первого взгляда было непонятно.
                Text(Onboarding.walletLegend)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capsule.walletHelp")
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        if phase == .ready {
            Text(EconText.ui("capsule_tap"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.soft)
                .transition(.opacity)
        } else if phase == .open, let p = pull {
            VStack(spacing: 4) {
                Text(EconText.ui("capsule_got", ["item": p.item.name]))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                Text(EconText.rarityName(p.rarity))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(rarityColor(p.rarity))
                Text(p.duplicate ? EconText.ui("capsule_duplicate", ["count": "\(p.shards)"]) : EconText.ui("capsule_new"))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
            }
            .multilineTextAlignment(.center)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("capsule.result")
        }
        if let refusal {
            Text(refusal)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.red)
                .multilineTextAlignment(.center)
                .transition(.opacity)
                .accessibilityIdentifier("capsule.refusal")
        }
    }

    private func pity(_ o: CapsuleOffer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(o.pityProgress >= 1 ? EconText.ui("capsule_pity_ready")
                 : EconText.ui("capsule_pity", ["count": "\(o.pityCount)", "total": "\(o.pityTotal)"]))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PetPalette.ink)
            ProgressView(value: min(max(o.pityProgress, 0), 1))
                .tint(rarityColor(.epic))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capsule.pity")
    }

    private func buttons(_ o: CapsuleOffer) -> some View {
        VStack(spacing: 8) {
            Text(EconText.ui("capsule_pull"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.soft)
            HStack(spacing: 10) {
                PullButton(title: EconText.ui("capsule_price_ticket"),
                           price: "🎟 \(o.ticketPrice)",
                           note: o.tickets > 0 ? "У тебя \(EconText.tickets(o.tickets))" : "Билетиков нет",
                           can: o.canPayTicket) { start(.ticket) }
                    .disabled(busy)
                    .accessibilityIdentifier("capsule.pull.ticket")
                PullButton(title: EconText.ui("capsule_price_coins"),
                           price: "🪙 \(o.coinPrice)",
                           note: o.coinPullsLeft > 0 ? "Сегодня ещё \(o.coinPullsLeft)" : EconText.ui("capsule_limit"),
                           can: o.canPayCoins) { start(.coins) }
                    .disabled(busy)
                    .accessibilityIdentifier("capsule.pull.coins")
            }
        }
    }

    /// Вход в лавку: одна карточка под круткой, три иконки витрины — видно, что там сегодня.
    private var shopCard: some View {
        let offers = model.file.map { ShopDaily.offers($0, now: Clock.now()) } ?? []
        return Button {
            model.haptic(.light)
            model.showShop = true
        } label: {
            HStack(spacing: 10) {
                Text("🛍")
                    .font(.system(size: 26))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Лавка дня")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    Text("Три вещи за монеты, завтра другие")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                }
                Spacer(minLength: 0)
                HStack(spacing: -6) {
                    ForEach(offers) { o in
                        ItemIcon(id: o.id, size: 30)
                            .padding(3)
                            .background(Circle().fill(PetPalette.bg))
                            .opacity(o.state == .sold ? 0.4 : 1)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PetPalette.soft)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.card))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(PetPalette.accent.opacity(0.35), lineWidth: 1.5) }
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Лавка дня"))
        .accessibilityHint(Text("Три вещи за монеты"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("capsule.shop")
    }

    /// Что предмет делает сейчас и что сделает кнопка: подпись под именем и кнопка справа.
    private struct Use {
        var note: String
        var on: Bool
        var title: String
        var label: String
        var key: String
        var act: () -> Void
    }

    private func use(_ it: CapsuleItem) -> Use? {
        switch ItemCatalog.role(it.id) {
        case .wear:
            guard let slot = Wear.info(it.id)?.slot else { return nil }
            let on = model.worn[slot] == it.id
            return Use(note: on ? "надето" : slot.place, on: on, title: on ? "Снять" : "Надеть",
                       label: on ? "Снять «\(it.name)»" : "Надеть «\(it.name)»", key: "wear.\(it.id)") { model.wear(it.id) }
        case .decor:
            let on = model.shelf == it.id
            return Use(note: on ? "на полке" : "на полку в комнате", on: on, title: on ? "Убрать" : "На полку",
                       label: on ? "Убрать «\(it.name)» с полки" : "Поставить «\(it.name)» на полку",
                       key: "shelf.\(it.id)") { model.toggleShelf(it.id) }
        case .toy:
            let on = model.toy == it.id
            return Use(note: on ? "играем этим" : "мячик для «Поиграть»", on: on, title: on ? "Убрать" : "Играть",
                       label: on ? "Играть обычным мячиком" : "Играть «\(it.name)»",
                       key: "toy.\(it.id)") { model.toggleToy(it.id) }
        case nil:
            return nil
        }
    }

    @ViewBuilder
    private var inventory: some View {
        let items = model.file.map { CapsuleMachine.inventory($0) } ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Коллекция")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                Spacer(minLength: 0)
                Text("\(items.count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
            }
            if items.isEmpty {
                Text("Пока пусто. Покрути ручку!")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
            }
            ForEach(items, id: \.id) { it in
                let u = use(it)
                let on = u?.on ?? false
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ItemTile(id: it.id, rarity: it.rarity, size: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(it.name)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(PetPalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(EconText.rarityName(it.rarity))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(rarityColor(it.rarity))
                            if let u {
                                Text(u.note)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(on ? PetPalette.accent : PetPalette.soft)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    if let u { useButton(u) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(PetPalette.card))
                .overlay {
                    if on { RoundedRectangle(cornerRadius: 12).strokeBorder(PetPalette.accent.opacity(0.55), lineWidth: 1.5) }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capsule.inventory")
    }

    /// «Надеть / На полку / Играть» — залитая акцентом, «Снять / Убрать» — обводка: что в деле, видно издалека.
    private func useButton(_ u: Use) -> some View {
        let on = u.on
        return Button {
            u.act()
        } label: {
            Text(u.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(on ? PetPalette.accent : .white)
                // 86, а не 78: «На полку» шире прочих и раздувала свою кнопку — столбец кнопок шёл лесенкой.
                .padding(.horizontal, 10)
                .frame(minWidth: 86, minHeight: 32)
                .background(Capsule().fill(on ? PetPalette.card : PetPalette.accent))
                .overlay { Capsule().strokeBorder(PetPalette.accent, lineWidth: on ? 1.5 : 0) }
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(Text(u.label))
        .accessibilityIdentifier(u.key)
    }

    private var ballLabel: String {
        switch phase {
        case .idle: return "Капсула"
        case .shaking: return "Капсула трясётся"
        case .ready: return EconText.ui("capsule_tap")
        case .open: return pull.map { EconText.ui("capsule_got", ["item": $0.item.name]) } ?? "Капсула"
        }
    }

    // MARK: крутка

    private func start(_ pay: CapsulePay) {
        guard !busy else { return }
        model.haptic(.light)
        guard let r = model.pullCapsule(pay) else { return }
        switch r {
        case .failure(let why):
            refusal = Self.text(why)
            model.haptic(.warning)
            SoundKit.shared.play(.refuse)
        case .success(let p):
            refusal = nil
            pull = p
            shattered = false
            SoundKit.shared.play(.button)
            withAnimation(.snappy) { phase = .shaking }
            flow?.cancel()
            flow = Task {
                if !reduceMotion {
                    // Три встряски подряд: каждая — проход phaseAnimator по trigger.
                    for _ in 0..<3 {
                        wobble += 1
                        try? await Task.sleep(for: .seconds(Self.shakeFor / 3))
                        if Task.isCancelled { return }
                    }
                }
                withAnimation(.snappy) { phase = .ready }
                model.haptic(.medium)
                try? await Task.sleep(for: .seconds(Self.autoOpen))
                if Task.isCancelled { return }
                if phase == .ready { reveal() }
            }
        }
    }

    private func reveal() {
        guard phase == .ready, let p = pull else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { phase = .open }
        model.haptic(p.rarity >= .epic ? .success : .medium)
        SoundKit.shared.play(p.rarity >= .rare ? .hearts : .ok)
        // Кошелёк, шкала и коллекция — только теперь.
        model.refresh()
        guard p.duplicate else { return }
        flow?.cancel()
        flow = Task {
            try? await Task.sleep(for: .seconds(0.9))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.5)) { shattered = true }
        }
    }

    static func text(_ r: CapsuleRefusal) -> String {
        switch r {
        case .noTickets: return EconText.ui("econ_no_tickets")
        case .notEnoughCoins(let need): return EconText.notEnough(need: need)
        case .dailyLimit: return EconText.ui("capsule_limit")
        }
    }
}

/// Цвет редкости из economy.json («#9AA0A6»). Не разобрался — мягкий серый палитры.
func rarityColor(_ r: Rarity) -> Color {
    let hex = EconomyConfig.shared.rarity(r).color
    return UInt32(hex.hasPrefix("#") ? String(hex.dropFirst()) : hex, radix: 16).map { Color(hex: $0) } ?? PetPalette.soft
}

/// Кнопка крутки: что платим, цена и подпись снизу. Не по карману — бледнее, но нажимается (отказ текстом).
struct PullButton: View {
    let title: String
    let price: String
    let note: String
    let can: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(price)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(note)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(PetPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(RoundedRectangle(cornerRadius: 16).fill(PetPalette.card))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(can ? PetPalette.accent : PetPalette.soft.opacity(0.3), lineWidth: 2)
            }
            .opacity(can ? 1 : 0.6)
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title), \(price)"))
        .accessibilityValue(Text(note))
        .accessibilityAddTraits(.isButton)
    }
}

/// Шарик-капсула: верх цвета редкости (до крутки — акцент), низ кремовый. Открыт — крышка слетает, внутри предмет.
struct GachaBall: View {
    let phase: CapsuleScreen.Phase
    let pull: CapsulePull?
    let shattered: Bool
    let wobble: Int

    private static let shake: [Double] = [0, -10, 10, -7, 7, -3, 0]
    private static let side: CGFloat = 150

    private var lidColor: Color {
        guard phase != .idle, let p = pull else { return PetPalette.accent }
        return rarityColor(p.rarity)
    }

    var body: some View {
        let open = phase == .open
        let r = Self.side / 2
        ZStack {
            // Предмет внутри.
            if open, let p = pull {
                ZStack {
                    ItemIcon(id: p.item.id, size: 84)
                        .shadow(color: rarityColor(p.rarity).opacity(0.7), radius: 12)
                        .scaleEffect(shattered ? 0.3 : 1)
                        .opacity(shattered ? 0 : 1)
                    if p.duplicate {
                        ForEach(0..<6, id: \.self) { i in
                            let a = Double(i) / 6 * 2 * Double.pi
                            let dx = CGFloat(cos(a)) * 70, dy = CGFloat(sin(a)) * 70
                            Image(systemName: "triangle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(rarityColor(p.rarity))
                                .rotationEffect(.radians(a))
                                .offset(x: shattered ? dx : 0, y: shattered ? dy : 0)
                                .opacity(shattered ? 1 : 0)
                        }
                    }
                }
                .offset(y: -40)
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                       topTrailingRadius: r, style: .circular)
                    .fill(lidColor)
                    .frame(width: Self.side, height: r)
                    .overlay(alignment: .topLeading) {
                        // Блик на крышке.
                        Capsule().fill(.white.opacity(0.45))
                            .frame(width: 30, height: 12)
                            .rotationEffect(.degrees(-30))
                            .offset(x: 26, y: 22)
                    }
                    .rotationEffect(.degrees(open ? -35 : 0), anchor: .bottomLeading)
                    .offset(x: open ? -30 : 0, y: open ? -70 : 0)
                    .opacity(open ? 0 : 1)
                Rectangle()
                    .fill(PetPalette.ink.opacity(0.25))
                    .frame(width: Self.side, height: 3)
                    .opacity(open ? 0 : 1)
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r, bottomTrailingRadius: r,
                                       topTrailingRadius: 0, style: .circular)
                    .fill(PetPalette.cream)
                    .frame(width: Self.side, height: r)
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r, bottomTrailingRadius: r,
                                               topTrailingRadius: 0, style: .circular)
                            .stroke(PetPalette.furDark.opacity(0.3), lineWidth: 2)
                    }
            }
            .phaseAnimator(Self.shake, trigger: wobble, content: { view, deg in
                view.rotationEffect(.degrees(deg), anchor: .bottom)
            }, animation: { _ in
                .linear(duration: 0.06)
            })
            .offset(y: open ? 40 : 0)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: open)
        .animation(.easeInOut(duration: 0.3), value: phase)
    }
}

/// Иконка предмета на плитке цвета редкости: так в коллекции и в лавке редкость видна без подписи.
struct ItemTile: View {
    let id: String
    let rarity: Rarity
    var size: CGFloat = 44

    var body: some View {
        ItemIcon(id: id, size: size * 0.82)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(rarityColor(rarity).opacity(0.16)))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(rarityColor(rarity).opacity(0.5), lineWidth: 1.5)
            }
    }
}
