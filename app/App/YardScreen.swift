// Волна 34 G: экран «Двор» — маленький тайкун. Сверху двор в 3D из сейва (YardLive) с табличками «+N/ч»,
// под ним копилка-свинка (тап — сбор), карточка следующей плиты, карточки станций и кнопка следующего яруса.
// Логика — Yard и YardText (Shared), действия — AppModel+Yard; тут только вид. Денег нет: всё в монетах 🪙 из игры.
// Решения (Вадим может поменять): кнопки не тускнеют — без монет нажатие качает карточку и объясняет тостом.
// Волна 35 M: таблички «+N/ч», пёс у станций и тиканье монет живут в сцене (YardLive, YardDogLive): тик — когда
// монетка/сухарик падает в корзинку, не больше двух станций. Золотая табличка станции — за клочки ✂️.
// Волна 36 P: переезд двора — тихая карточка внизу, когда двор полный и пёс ур. 30+; подтверждение своим
// слоем внутри экрана (не системный alert — ID надёжны в UI-тестах). Звёзды ★ славы — в шапке.

import RealityKit
import SwiftUI
@preconcurrency import PetCore

struct YardScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Станция, что только что встала или выросла: в новой сцене она «выскакивает».
    @State private var popId: String?
    @State private var flyCoins = 0
    @State private var fountain = 0
    @State private var sparkle = 0
    @State private var piggyTaps = 0
    @State private var plateShake = 0
    @State private var tierShake = 0
    @State private var shakes: [String: Int] = [:]
    @State private var popTask: Task<Void, Never>?
    /// Сцена в окне прокрутки. Ушла за край — RealityView убираем: 3D не рисует впустую (батарея), а на CI
    /// главный поток не стоит в ожидании кадра и UI-тест успевает листать. Вернулась — мир собирается заново, уже на виду.
    @State private var sceneOnScreen = true
    /// Открыто подтверждение переезда.
    @State private var confirmMove = false

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 14) {
                    header
                    if let f = model.file {
                        content(f, now: Clock.now())
                    }
                }
                .padding(20)
            }
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .overlay(alignment: .top) {
            // Свой тост: главный экран под обложкой не виден, а отказ не бывает немым.
            if let toast = model.toast {
                ToastView(toast: toast)
                    .allowsHitTesting(false)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.toast)
        .overlay {
            if confirmMove, let f = model.file {
                moveConfirm(f)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: confirmMove)
        .onDisappear { popTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("yard.screen")
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                SheetCloseButton(id: "yard.screen.close")
            }
            Text("Двор")
                .petFont(22, .bold)
                .foregroundStyle(PetPalette.ink)
                .accessibilityAddTraits(.isHeader)
            if let f = model.file {
                let tier = HomeShop.level(f, .yard)
                let cozy = Yard.cozy(f.yard)
                Text(cozy > 0 ? "Ярус «\(YardText.tierName(tier))» · уют \(cozy)" : "Ярус «\(YardText.tierName(tier))»")
                    .petFont(14, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .accessibilityIdentifier("yard.screen.tierName")
                if f.yard.moves > 0 {
                    Text("\(YardText.gloryStars(moves: f.yard.moves)) \(YardText.districtName(Yard.district(moves: f.yard.moves)))")
                        .petFont(14, .bold)
                        .foregroundStyle(PetPalette.yellow)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(YardText.gloryLabel(moves: f.yard.moves)))
                        .accessibilityIdentifier("yard.screen.glory")
                }
                let coins = f.econ.wallet.coins
                Text("🪙 \(coins)")
                    .petFont(15, .semibold)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.soft)
                    .contentTransition(.numericText(value: Double(coins)))
                    .animation(.snappy, value: coins)
                    .accessibilityLabel(Text(EconText.coins(coins)))
                    .accessibilityIdentifier("yard.screen.wallet")
            }
        }
    }

    // MARK: - Содержимое

    @ViewBuilder private func content(_ f: SaveFile, now: Double) -> some View {
        let dog = model.yardDogLevel
        let tier = HomeShop.level(f, .yard)
        let rate = Yard.rate(f, dogLevel: dog)
        diorama(f, now: now, tier: tier, dog: dog)
        bankCard(f, now: now, dog: dog, rate: rate)
        plateCard(f, tier: tier, dog: dog, rate: rate)
        ForEach(owned(f), id: \.id) { st in
            stationCard(st, f: f, dog: dog)
        }
        tierCard(f, tier: tier, dog: dog)
        if Yard.canMove(f.yard, dogLevel: dog) {
            moveCard(f)
        }
        Text("Копилка копит до суток. Двор остаётся, даже если начать заново с новым щенком.")
            .petFont(12, .medium)
            .foregroundStyle(PetPalette.soft)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    /// Поставленные станции в порядке конфига.
    private func owned(_ f: SaveFile) -> [YardStation] {
        YardConfig.shared.stations.filter { f.yard.stations[$0.id] != nil }
    }

    // MARK: - Двор в 3D

    @ViewBuilder private func diorama(_ f: SaveFile, now: Double, tier: Int, dog: Int) -> some View {
        let night = model.roomSchedule.phaseNow(dark: colorScheme == .dark) >= 1.5
        // Поднос копилки — четвертями: сцена не пересобирается каждую секунду.
        let fill = Float((Yard.fill(f, now: now, dogLevel: dog) * 4).rounded() / 4)
        let s = f.yard
        let levels = s.stations.keys.sorted().map { "\($0)=\(s.stations[$0] ?? 0)" }.joined(separator: ",")
        let pop = popId
        let spots = YardLive.spots(s, tier: tier)
        let helper = Yard.helper(f)
        let rates = spots.map { YardTickRate(id: $0.id, rate: Yard.stationRate($0.id, in: s, dogLevel: dog, helper: helper)) }
        let mode = YardDogMode.of(pose: model.snap.pose, alive: model.snap.alive)
        let live = YardLive.Live(rates: rates, mode: mode, calm: reduceMotion, forced: YardDogLive.forced)
        let gold = s.gold.sorted().joined(separator: ",")
        let perHour = rates.map { "\($0.id)=\(YardText.perHour($0.rate))" }.joined(separator: ",")
        // Ключ сцены — всё видимое: ярус, плиты, уровни, поднос, ночь, доход на табличках, золото, дома ли пёс.
        let key = "\(tier)#\(s.plates.joined(separator: ","))#\(levels)#\(fill)#\(night)#\(perHour)#\(gold)#\(mode)#\(reduceMotion)"
        let dogPose = YardDogLive.pose(mode: mode, spots: spots, tier: tier, night: night, calm: reduceMotion, now: now)
        // Сцена по ключу: одна и та же RealityView, внутри меняется только мир. Раньше вид пересоздавался .id(key),
        // и новый, родившийся за краем экрана (улучшили станцию внизу списка), на CI оставался пустым.
        let build: @MainActor @Sendable () -> Entity = {
            let scene = YardLive.scene(s, tier: tier, fill: fill, night: night, brushed: false, live: live)
            if let pop, let spot = spots.first(where: { $0.id == pop }) {
                YardLive.pop(pop, in: scene, scale: spot.scale)
            }
            // Пёс догружается отдельно: двор виден сразу. Мир успел смениться — сядет в старый, его уже нет в сцене.
            if mode != .absent {
                Task { @MainActor in
                    let body = await YardDogLive.model()
                    YardDogLive.attach(to: scene, body: body)
                }
            }
            return scene
        }
        Group {
            if sceneOnScreen {
                RealityView { content in
                    content.camera = .virtual
                    YardArtSystem.registerOnce()
                    YardLiveSystem.registerOnce()
                    let holder = Entity()
                    YardLive.swap(in: holder, key: key, build: build)
                    content.add(holder)
                } update: { content in
                    guard let holder = content.entities.first(where: { YardLive.isHolder($0) }) else { return }
                    YardLive.swap(in: holder, key: key, build: build)
                }
            } else {
                Color.clear
            }
        }
        .frame(height: 300)
        .background(night ? Color(hex: 0x2a3350) : PetPalette.stageBg)
        .overlay {
            ZStack {
                YardBurst(emoji: "🪙", trigger: flyCoins, inward: true)
                YardBurst(emoji: "✨", trigger: sparkle, inward: false)
            }
            .opacity(reduceMotion ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onScrollVisibilityChange(threshold: 0.02) { sceneOnScreen = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(sceneLabel(tier: tier, rates: rates, dog: dogPose, mode: mode)))
        // Для UI-тестов: сколько плит, ярус, уровни станций («dryer=3»), что делает пёс и золотые станции.
        .accessibilityValue(Text("plates=\(s.plates.count),tier=\(tier),\(levels),dog=\(dogPose?.clipKey ?? "none"),gold=\(gold),moves=\(s.moves),dog3d=\(mode == .absent ? "none" : YardDogLive.state)"))
        .accessibilityIdentifier("yard.screen.scene")
    }

    /// VoiceOver: ярус, станции с доходом (таблички в сцене не читаются), где Шиба.
    private func sceneLabel(tier: Int, rates: [YardTickRate], dog: YardDogPose?, mode: YardDogMode) -> String {
        let cfg = YardConfig.shared
        let head = "Двор, ярус «\(YardText.tierName(tier))»"
        let st = rates.compactMap { r in cfg.station(r.id).map { "\($0.name) \(YardText.perHour(r.rate))" } }
        var out = st.isEmpty ? head + ". Станций пока нет" : head + ". Станции: " + st.joined(separator: ", ")
        switch mode {
        case .absent: break
        case .asleep: out += ". Шиба спит"
        case .awake:
            if let id = dog?.station, let name = cfg.station(id)?.name {
                out += dog?.phase == .act ? ". Шиба у станции «\(name)»" : ". Шиба бегает к станции «\(name)»"
            } else {
                out += ". Шиба отдыхает во дворе"
            }
        }
        return out
    }

    // MARK: - Копилка

    @ViewBuilder private func bankCard(_ f: SaveFile, now: Double, dog: Int, rate: Double) -> some View {
        let bank = Yard.peek(f, now: now, dogLevel: dog).bank
        let cap = Yard.cap(rate: rate)
        let fill = Yard.fill(f, now: now, dogLevel: dog)
        let full = !f.yard.stations.isEmpty && fill >= 1 - 1e-9
        HStack(spacing: 14) {
            Button { collect() } label: {
                ZStack {
                    Circle()
                        .stroke(PetPalette.soft.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0.001, fill))
                        .stroke(full ? PetPalette.green : PetPalette.accent,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.snappy, value: fill)
                    Text("🐷")
                        .font(.system(size: 40))
                        .keyframeAnimator(initialValue: 1.0, trigger: piggyTaps) { v, s in
                            v.scaleEffect(s)
                        } keyframes: { _ in
                            CubicKeyframe(1.22, duration: 0.12)
                            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                        }
                }
                .frame(width: 84, height: 84)
                .overlay {
                    YardBurst(emoji: "🪙", trigger: fountain, inward: false)
                        .opacity(reduceMotion ? 0 : 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Circle())
            }
            .buttonStyle(SquishStyle())
            .accessibilityLabel(Text("Копилка: \(EconText.coins(Int(bank))). Собрать"))
            .accessibilityIdentifier("yard.screen.collect")

            VStack(alignment: .leading, spacing: 3) {
                Text(cap > 0 ? "\(Int(bank)) из \(Int(cap)) 🪙" : "0 🪙")
                    .petFont(20, .heavy)
                    .monospacedDigit()
                    .foregroundStyle(PetPalette.ink)
                    .contentTransition(.numericText(value: bank))
                    .animation(.snappy, value: Int(bank))
                    .accessibilityIdentifier("yard.screen.bank.sum")
                Text(YardText.bank(fill: fill, fullAt: Yard.fullAt(f, now: now, dogLevel: dog)))
                    .petFont(14, .semibold)
                    .foregroundStyle(full ? PetPalette.green : PetPalette.soft)
                if rate > 0 {
                    Text("Двор приносит \(YardText.perHour(rate))")
                        .petFont(13, .medium)
                        .foregroundStyle(PetPalette.soft)
                }
            }
            .axLines(2)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("yard.screen.bank")
    }

    private func collect() {
        piggyTaps += 1
        guard let h = model.collectYard(), !h.isEmpty else { return }
        fountain += 1
    }

    // MARK: - Следующая плита

    @ViewBuilder private func plateCard(_ f: SaveFile, tier: Int, dog: Int, rate: Double) -> some View {
        let kitchen = HomeShop.level(f, .kitchen)
        if let p = YardText.focusPlate(f.yard, yardLevel: tier, dogLevel: dog, kitchenLevel: kitchen) {
            let coins = f.econ.wallet.coins
            let lock = Yard.lock(p.id, f.yard, yardLevel: tier, dogLevel: dog, kitchenLevel: kitchen)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(p.isStation ? Self.emoji(p.id) : "🌼")
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(PetPalette.accent.opacity(0.16)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Дальше: \(p.name)")
                            .petFont(17, .bold)
                            .foregroundStyle(PetPalette.ink)
                        Text(p.isStation
                             ? "станция · \(YardText.perHour(Yard.stationRate(p.id, level: 1, dogLevel: dog, moves: f.yard.moves)))"
                             : p.cozy > 0 ? "украшение · уют +\(p.cozy)" : "украшение")
                            .petFont(14, .medium)
                            .foregroundStyle(PetPalette.soft)
                    }
                    .axLines(2)
                    .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if let lock {
                    Label {
                        Text(YardText.lock(lock))
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                    .petFont(13, .semibold)
                    .foregroundStyle(PetPalette.soft)
                    .accessibilityIdentifier("yard.screen.plate.lock")
                } else if p.price > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: YardText.progress(price: p.price, coins: coins))
                            .tint(PetPalette.accent)
                            .accessibilityHidden(true)
                        Text(YardText.more(price: p.price, coins: coins, rate: rate))
                            .petFont(13, .semibold)
                            .foregroundStyle(coins >= p.price ? PetPalette.green : PetPalette.soft)
                            .accessibilityIdentifier("yard.screen.plate.more")
                    }
                }

                YardActionButton(title: p.isStation ? "Поставить" : "Купить", price: p.price,
                                 id: "yard.screen.plate.buy",
                                 label: "\(p.name): купить за \(EconText.coins(p.price))") {
                    buyPlate(p)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
            .modifier(RefuseShake(trigger: plateShake))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("yard.screen.plate")
        }
    }

    private func buyPlate(_ p: YardPlate) {
        guard let r = model.buyYardPlate(p.id) else { return }
        if case .ok = r {
            flyCoins += 1
            if p.isStation { pop(p.id) } else { sparkle += 1 }
        } else {
            plateShake += 1
        }
    }

    // MARK: - Станции

    @ViewBuilder private func stationCard(_ st: YardStation, f: SaveFile, dog: Int) -> some View {
        let level = f.yard.stations[st.id] ?? 1
        let helper = Yard.helper(f)
        let gold = f.yard.gold.contains(st.id)
        let now = Yard.stationRate(st.id, level: level, dogLevel: dog, helper: helper, gold: gold, moves: f.yard.moves)
        let top = st.maxLevel
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(Self.emoji(st.id))
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(PetPalette.accent.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.name)
                        .petFont(17, .bold)
                        .foregroundStyle(PetPalette.ink)
                    Text("ур. \(level) · \(YardText.perHour(now))")
                        .petFont(14, .medium)
                        .monospacedDigit()
                        .foregroundStyle(PetPalette.soft)
                }
                .axLines(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                LevelPips(level: level, top: top)
            }
            .accessibilityElement(children: .combine)

            if let helper, helper.station == st.id {
                Text("🐕 Пёс помогает здесь: +\(helper.pct) %")
                    .petFont(13, .semibold)
                    .foregroundStyle(PetPalette.green)
                    .accessibilityIdentifier("yard.screen.helper")
            }
            if let portion = st.portionName {
                Text("А ещё — \(portion) в кладовую")
                    .petFont(13, .medium)
                    .foregroundStyle(PetPalette.soft)
            }

            if level < top {
                let next = Yard.stationRate(st.id, level: level + 1, dogLevel: dog, helper: helper, gold: gold, moves: f.yard.moves)
                Rectangle()
                    .fill(PetPalette.soft.opacity(0.2))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ур. \(level + 1): \(YardText.perHour(next)) вместо \(YardText.perHour(now))")
                        .petFont(14, .bold)
                        .foregroundStyle(PetPalette.ink)
                    if let pb = YardText.payback(Yard.paybackDays(st.id, level: level, moves: f.yard.moves)) {
                        Text(pb)
                            .petFont(13, .medium)
                            .foregroundStyle(PetPalette.soft)
                    }
                }
                .accessibilityElement(children: .combine)
                YardActionButton(title: "Улучшить", price: st.price(toLevel: level + 1) ?? 0,
                                 id: "yard.screen.station.\(st.id).up",
                                 label: "\(st.name): улучшить за \(EconText.coins(st.price(toLevel: level + 1) ?? 0))") {
                    upgrade(st.id)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                    Text("Лучший уровень")
                }
                .petFont(14, .bold)
                .foregroundStyle(PetPalette.yellow)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.yellow.opacity(0.14)))
                .accessibilityElement(children: .combine)
            }
            goldRow(st, gold: gold)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(PetPalette.card))
        .modifier(RefuseShake(trigger: shakes[st.id, default: 0]))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("yard.screen.station.\(st.id)")
    }

    private func upgrade(_ id: String) {
        guard let r = model.upgradeYardStation(id) else { return }
        if case .upgraded = r {
            flyCoins += 1
            pop(id)
        } else {
            shakes[id, default: 0] += 1
        }
    }

    /// Золотая табличка: есть — строка-награда, нет — кнопка за клочки ✂️ (сток клочков, +3 % к станции).
    @ViewBuilder private func goldRow(_ st: YardStation, gold: Bool) -> some View {
        let cfg = YardConfig.shared
        if gold {
            HStack(spacing: 6) {
                Text("🏅")
                    .accessibilityHidden(true)
                Text("Золотая табличка · +\(cfg.goldPct) %")
            }
            .axLines(2)
            .petFont(14, .bold)
            .foregroundStyle(PetPalette.yellow)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.yellow.opacity(0.14)))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("yard.screen.station.\(st.id).goldOwned")
        } else if cfg.goldPrice > 0 {
            YardActionButton(title: "Золотая табличка +\(cfg.goldPct) %", price: cfg.goldPrice,
                             id: "yard.screen.station.\(st.id).gold",
                             label: "\(st.name): золотая табличка за \(EconText.shards(cfg.goldPrice))",
                             currency: "✂️", filled: false) {
                gild(st.id)
            }
        }
    }

    private func gild(_ id: String) {
        guard let r = model.goldYardStation(id) else { return }
        if case .ok = r {
            sparkle += 1
            pop(id)
        } else {
            shakes[id, default: 0] += 1
        }
    }

    // MARK: - Ярус

    @ViewBuilder private func tierCard(_ f: SaveFile, tier: Int, dog: Int) -> some View {
        let tb = YardText.tierButton(Yard.nextTier(f.yard, yardLevel: tier, dogLevel: dog))
        Group {
            if tb.reason == nil && tb.price == nil {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                    Text(tb.title)
                }
                .petFont(14, .bold)
                .foregroundStyle(PetPalette.yellow)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.yellow.opacity(0.14)))
                .accessibilityElement(children: .combine)
            } else {
                Button { openTier() } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: tb.isOpen ? "arrow.up.forward.square.fill" : "lock.fill")
                                .accessibilityHidden(true)
                            Text(tb.title)
                                .petFont(15, .bold)
                            Spacer(minLength: 8)
                            if let price = tb.price {
                                Text("🪙 \(price)")
                                    .petFont(15, .heavy)
                                    .monospacedDigit()
                            }
                        }
                        if let reason = tb.reason {
                            Text(reason)
                                .petFont(13, .semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .opacity(0.85)
                        }
                    }
                    .axLines(2)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(PetPalette.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 14).strokeBorder(PetPalette.accent, lineWidth: 1.5))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(SquishStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(tb.title))
                .accessibilityValue(Text(tb.reason ?? tb.price.map { "за \(EconText.coins($0))" } ?? ""))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("yard.screen.tier")
            }
        }
        .modifier(RefuseShake(trigger: tierShake))
    }

    private func openTier() {
        guard let r = model.openYardTier() else { return }
        if case .ok = r {
            flyCoins += 1
            sparkle += 1
        } else {
            tierShake += 1
        }
    }

    // MARK: - Переезд

    /// Тихая карточка: двор достроен — можно переехать в новый район со славой.
    @ViewBuilder private func moveCard(_ f: SaveFile) -> some View {
        Button { confirmMove = true } label: {
            HStack(spacing: 12) {
                Text("🚚")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(PetPalette.yellow.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(YardText.moveTitle)
                        .petFont(16, .bold)
                        .foregroundStyle(PetPalette.ink)
                    Text(YardText.moveLine(moves: f.yard.moves))
                        .petFont(13, .medium)
                        .foregroundStyle(PetPalette.soft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .axLines(3)
                .minimumScaleFactor(0.85)
                Image(systemName: "chevron.right")
                    .foregroundStyle(PetPalette.soft)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).strokeBorder(PetPalette.soft.opacity(0.3), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(YardText.moveTitle))
        .accessibilityValue(Text(YardText.moveLine(moves: f.yard.moves)))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("yard.screen.move")
    }

    /// Подтверждение переезда: что останется, что начнётся заново, какая слава. «Переехать» / «Остаться».
    @ViewBuilder private func moveConfirm(_ f: SaveFile) -> some View {
        let lines = YardText.moveConfirm(moves: f.yard.moves)
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { confirmMove = false }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(YardText.moveTitle)
                    .petFont(20, .bold)
                    .foregroundStyle(PetPalette.ink)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(i == 0 ? "✓" : i == 1 ? "↺" : "★")
                            .foregroundStyle(i == 2 ? PetPalette.yellow : PetPalette.soft)
                            .accessibilityHidden(true)
                        Text(line)
                            .petFont(15, i == 2 ? .bold : .medium)
                            .foregroundStyle(PetPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                HStack(spacing: 10) {
                    Button { confirmMove = false } label: {
                        Text("Остаться")
                            .petFont(15, .bold)
                            .foregroundStyle(PetPalette.accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(PetPalette.accent, lineWidth: 1.5))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(SquishStyle())
                    .accessibilityIdentifier("yard.screen.move.cancel")
                    Button { move() } label: {
                        Text("Переехать")
                            .petFont(15, .bold)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 14).fill(PetPalette.accent))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(SquishStyle())
                    .accessibilityIdentifier("yard.screen.move.confirm")
                }
                .axLines(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 4)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22).fill(PetPalette.card))
            .padding(.horizontal, 20)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("yard.screen.move.sheet")
        }
    }

    private func move() {
        confirmMove = false
        guard let r = model.moveYard(), case .ok = r else { return }
        sparkle += 1
    }

    // MARK: - Общее

    private func pop(_ id: String) {
        popId = id
        popTask?.cancel()
        popTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            if Task.isCancelled { return }
            popId = nil
        }
    }

    /// Значок станции на карточке.
    static func emoji(_ id: String) -> String {
        switch id {
        case "dryer": return "🥖"
        case "bones": return "🦴"
        case "porridge": return "🥣"
        case "spinner": return "🧶"
        case "pies": return "🥧"
        case "photo": return "📸"
        case "sausage": return "🌭"
        case "mill": return "🌙"
        default: return "🏡"
        }
    }
}

/// «Поставить · 🪙 140». Не тускнеет без монет: нажатие объясняет отказ тостом и качает карточку.
/// currency — значок цены (✂️ у золотой таблички), filled: false — контурная, для второстепенного действия.
struct YardActionButton: View {
    let title: String
    let price: Int
    let id: String
    let label: String
    var currency = "🪙"
    var filled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .petFont(15, .bold)
                Spacer(minLength: 8)
                Text(price > 0 ? "\(currency) \(price)" : "даром")
                    .petFont(15, .heavy)
                    .monospacedDigit()
            }
            .axLines(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(filled ? Color.white : PetPalette.accent)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: 14).fill(PetPalette.accent)
                } else {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(PetPalette.accent, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }
}

/// Горсть значков: фонтаном из центра (сбор, ✨ покупки) или снизу в центр (монеты летят во двор).
/// trigger 0 — покой, ничего не видно.
struct YardBurst: View {
    let emoji: String
    let trigger: Int
    let inward: Bool

    private struct Frame {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var o: Double = 0
        var s: CGFloat = 1
    }

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                coin(i)
            }
        }
    }

    private func coin(_ i: Int) -> some View {
        let dx = CGFloat(i - 3) * 22
        let up = CGFloat(70 + (i * 37) % 40)
        let delay = 0.01 + Double(i) * 0.04
        // Внутрь: из-под сцены в центр и гаснут; наружу: вверх веером и оседают.
        let x0: CGFloat = inward ? dx * 2 : 0, x1: CGFloat = inward ? 0 : dx * 1.6
        let y0: CGFloat = inward ? 170 : 0, yMid: CGFloat = inward ? 60 : -up, y1: CGFloat = inward ? 0 : -up * 0.4
        let s0: CGFloat = inward ? 1 : 0.6, sMid: CGFloat = inward ? 1 : 1.1, s1: CGFloat = inward ? 0.4 : 0.9
        return Text(emoji)
            .font(.system(size: 18))
            .keyframeAnimator(initialValue: Frame(), trigger: trigger) { v, f in
                v.scaleEffect(f.s).offset(x: f.x, y: f.y).opacity(f.o)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    MoveKeyframe(x0)
                    LinearKeyframe(x0, duration: delay)
                    CubicKeyframe(x1, duration: 0.75)
                }
                KeyframeTrack(\.y) {
                    MoveKeyframe(y0)
                    LinearKeyframe(y0, duration: delay)
                    CubicKeyframe(yMid, duration: 0.35)
                    CubicKeyframe(y1, duration: 0.4)
                }
                KeyframeTrack(\.o) {
                    MoveKeyframe(0)
                    LinearKeyframe(0, duration: delay)
                    LinearKeyframe(1, duration: 0.08)
                    LinearKeyframe(1, duration: 0.47)
                    LinearKeyframe(0, duration: 0.2)
                }
                KeyframeTrack(\.s) {
                    MoveKeyframe(s0)
                    LinearKeyframe(s0, duration: delay)
                    SpringKeyframe(sMid, duration: 0.3, spring: .bouncy)
                    LinearKeyframe(s1, duration: 0.45)
                }
            }
    }
}
