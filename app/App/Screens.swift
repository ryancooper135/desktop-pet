// Второстепенные экраны: шкалы по запросу, «Пока тебя не было», настройки, ошибка сохранения, каталог превью.

import SwiftUI
import UIKit
@preconcurrency import PetCore

// MARK: - Шкалы

/// Лист по высоте содержимого: на .medium под шкалами оставалась пустая половина листа.
/// Пока высота не измерена — .medium; при крупном шрифте содержимое длиннее экрана — прокрутка.
struct NeedsSheet: View {
    @Environment(AppModel.self) private var model
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let snap = model.snap
        ScrollView {
            content(snap)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(PetPalette.bg.ignoresSafeArea())
        // Один detent: тянуть вверх в пустоту нечего. Высоту больше экрана система сама ограничит, дальше — прокрутка.
        .presentationDetents(contentHeight > 0 ? [.height(CGFloat(HomeText.sheetHeight(content: Double(contentHeight))))] : [.medium])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("needs.sheet")
    }

    private func content(_ snap: PetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Как там \(snap.name)")
                    .axLines(1)
                    .petFont(20, .bold)
                    .foregroundStyle(PetPalette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 14)
                // Волна 22: такой же крестик, как у листов волны 21, — лист шкал закрывается не только свайпом.
                SheetCloseButton(id: "needs.close")
                    .padding(.leading, 6)
            }
            ForEach(VisibleNeeds.all, id: \.self) { n in
                NeedBar(need: n, value: snap.needs[n] ?? 0, grows: true)
            }
            // Шерсть одной строкой (волна 5): стадия от ухода за неделю, см. Shared/Coat.swift. Волна 19: лохматая — где расчесать.
            if let coat = model.coat, snap.alive {
                Text(Onboarding.coatLine(coat.stage, ageS: model.file.map { snap.t - $0.createdT } ?? .infinity))
                    .petFont(13, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .accessibilityIdentifier("needs.coat")
            }
            if let next = nextEvent {
                Text(next)
                    .petFont(13, .medium)
                    .foregroundStyle(PetPalette.soft)
                    .accessibilityIdentifier("needs.next")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «Проголодается в 18:00» — ближайшее событие прогноза на сутки.
    private var nextEvent: String? {
        guard let f = model.file, model.snap.alive else { return nil }
        let now = Clock.now()
        let events = ForecastTools.upcoming(f, at: now, horizonH: 24)
        return Presenter.sheetNext(timer: model.snap.timer, event: ForecastTools.nextLow(events, after: now), at: now)
    }
}

// MARK: - Пока тебя не было

/// Волна 52: «Пока тебя не было» 2.0 (макет A «Лента», design/wave52). Сверху вниз: что делал пёс (2–3 момента
/// с иконкой), что накопилось во дворе — одной кнопкой «Забрать всё» (тот же model.collectYard, что во дворе),
/// что изменилось (погода, сезон, уровень, достижения) и одна подсказка с наградой. Пустые блоки не рисуются.
/// Блоки проявляются по очереди; с Reduce Motion — сразу. Каждая карточка для VoiceOver — одна фраза.
struct AwayScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: AwayReport
    /// Сколько блоков уже проявилось (лесенка 0,08 с).
    @State private var shown = 0
    /// «Забрать всё» нажато: что реально пришло (может отличаться от предпросмотра на секунды копилки).
    @State private var collected: YardHarvest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .awayAppear(0, shown)
                momentList
                if report.died {
                    Text(Presenter.typeset(report.cta))
                        .petFont(17, .semibold)
                        .foregroundStyle(PetPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                        .awayAppear(2, shown)
                } else {
                    if let stash = report.stash {
                        section("Накопилось")
                            .awayAppear(2, shown)
                        stashCard(stash)
                            .awayAppear(2, shown)
                    }
                    if !report.changes.isEmpty {
                        section("Что изменилось")
                            .awayAppear(3, shown)
                        AwayFlow(spacing: 8) {
                            ForEach(report.changes) { c in chip(c) }
                        }
                        .awayAppear(3, shown)
                    }
                }
                buttons
                    .padding(.top, 16)
                    .awayAppear(4, shown)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("away.screen")
        .task {
            if reduceMotion {
                shown = 5
                return
            }
            for i in 1...5 {
                withAnimation(.easeOut(duration: 0.35)) { shown = i }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    // MARK: блоки

    private var hero: some View {
        AXRow(spacing: 14) {
            PetFaceView(pose: model.snap.pose)
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(Presenter.typeset(report.greet))
                    .petFont(28, .heavy)
                    .foregroundStyle(PetPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(report.subtitle)
                    .petFont(17, .semibold)
                    .foregroundStyle(PetPalette.soft)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder private var momentList: some View {
        if !report.cards.isEmpty {
            if !report.died {
                section("Что делал \(model.snap.name)")
                    .awayAppear(1, shown)
            }
            VStack(spacing: 8) {
                ForEach(report.cards) { c in moment(c) }
            }
            .padding(.top, report.died ? 16 : 0)
            .awayAppear(1, shown)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .tracking(0.8)
            .petFont(13, .bold)
            .foregroundStyle(PetPalette.soft)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func moment(_ c: AwayReport.Card) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AwayTile(icon: c.icon, tone: c.tone)
            VStack(alignment: .leading, spacing: 2) {
                if !c.title.isEmpty {
                    Text(c.title)
                        .petFont(19, .bold)
                        .foregroundStyle(PetPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(Presenter.typeset(c.text))
                    .petFont(15)
                    .foregroundStyle(PetPalette.ink.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.leading, 11)
        .padding(.trailing, 14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(PetPalette.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("away.card.\(c.id)")
    }

    private func stashCard(_ stash: YardHarvest) -> some View {
        let got = collected
        let h = got ?? stash
        let chips = AwayBuilder.stashChips(h)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("+\(h.coins) 🪙")
                    .petFont(30, .heavy)
                    .foregroundStyle(PetPalette.ink)
                Text(got == nil ? "в копилке двора" : "в кошельке")
                    .petFont(15, .semibold)
                    .foregroundStyle(PetPalette.soft)
            }
            .accessibilityElement(children: .combine)
            if !chips.isEmpty {
                AwayFlow(spacing: 8) {
                    ForEach(chips, id: \.self) { t in
                        Text(t)
                            .petFont(15, .semibold)
                            .foregroundStyle(PetPalette.ink)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 38)
                            .background(Capsule().fill(PetPalette.bg))
                    }
                }
            }
            if let got {
                Label(Presenter.typeset(YardText.harvest(got)), systemImage: "checkmark.circle.fill")
                    .petFont(15, .semibold)
                    .foregroundStyle(AwayReport.Tone.play.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("away.collected")
            } else {
                Button {
                    // Тот же сбор, что кнопкой во дворе: Yard.collect + награды записи, звон CoinChime, тост.
                    if let h = model.collectYard(), !h.isEmpty {
                        withAnimation(Motion.calm(.spring(response: 0.35, dampingFraction: 0.8))) { collected = h }
                    }
                } label: {
                    Label("Забрать всё", systemImage: "tray.and.arrow.down.fill")
                        .petFont(18, .bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Capsule().fill(AwayReport.Tone.vio.color))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Монеты и порции со двора — в кошелёк и кладовую")
                .accessibilityIdentifier("away.collect")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(PetPalette.card))
    }

    private func chip(_ c: AwayReport.Card) -> some View {
        HStack(spacing: 7) {
            Image(systemName: c.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(c.tone.color)
                .accessibilityHidden(true)
            Text(c.title)
                .petFont(15, .semibold)
                .foregroundStyle(PetPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 10)
        .padding(.trailing, 13)
        .frame(minHeight: 38)
        .background(Capsule().fill(PetPalette.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.text)
        .accessibilityIdentifier("away.change.\(c.id)")
    }

    @ViewBuilder private var buttons: some View {
        if report.died {
            Button {
                model.startOver()
            } label: {
                Text("Начать заново").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(PetPalette.accent)
            // Вторая кнопка — тихая, в тон экрана, а не системно-синяя.
            later("Закрыть")
        } else {
            if let hint = report.hint {
                hintCard(hint)
            } else if model.snap.main.action != nil {
                // Подсказки нет (всё сделано) — как раньше: главная кнопка комнаты.
                Button {
                    model.away = nil
                    model.doMain()
                } label: {
                    Label(model.snap.main.title, systemImage: model.snap.main.icon)
                        .petFont(17, .bold)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(PetPalette.accent)
            }
            later("Потом")
        }
    }

    private func later(_ title: String) -> some View {
        Button(title) { model.away = nil }
            .petFont(16, .semibold)
            .tint(PetPalette.soft)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("away.later")
    }

    private func hintCard(_ h: AwayReport.Hint) -> some View {
        let title = h.reward.isEmpty ? h.button : "\(h.button) · \(h.reward)"
        return AXRow(spacing: 12) {
            HStack(spacing: 12) {
                AwayTile(icon: h.icon, tone: h.tone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.label.uppercased())
                        .tracking(0.6)
                        .petFont(13, .bold)
                        .foregroundStyle(AwayReport.Tone.vio.color)
                    Text(Presenter.typeset(h.title))
                        .petFont(18, .bold)
                        .foregroundStyle(PetPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            Button {
                model.away = nil
                if let a = h.action { model.act(a) }
            } label: {
                Text(title)
                    .petFont(15, .bold)
                    .foregroundStyle(PetPalette.bg)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(PetPalette.ink))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("away.hint")
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(PetPalette.card))
    }
}

/// Цветная плашка с SF Symbol — иконка момента или подсказки. Растёт с Dynamic Type.
private struct AwayTile: View {
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 46
    let icon: String
    let tone: AwayReport.Tone

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: side * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: side * 0.33, style: .continuous).fill(tone.color))
            .accessibilityHidden(true)
    }
}

extension AwayReport.Tone {
    /// Цвета макета волны 52: одинаковые в обеих темах (иконка белая на плашке).
    var color: Color {
        switch self {
        case .food: return Color(hex: 0xFF9446)
        case .love: return Color(hex: 0xFF5E86)
        case .play: return Color(hex: 0x22C59A)
        case .wash: return Color(hex: 0x3EA7FF)
        case .gold: return Color(hex: 0xF4B42F)
        case .night: return Color(hex: 0x5B6CD9)
        case .vio: return Color(hex: 0x6C5CE7)
        }
    }
}

private extension View {
    /// Блок проявляется, когда до него дошла лесенка: прозрачность и сдвиг на 14 pt снизу.
    func awayAppear(_ i: Int, _ shown: Int) -> some View {
        opacity(shown > i ? 1 : 0)
            .offset(y: shown > i ? 0 : 14)
    }
}

/// Чипы в строку с переносом (перемены, кладовая/билетик).
private struct AwayFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        let w = rows.map(\.width).max() ?? 0
        let h = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for (i, size) in zip(row.items, row.sizes) {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, v) in subviews.enumerated() {
            var size = v.sizeThatFits(.unspecified)
            if size.width > width { size = v.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.items.append(i)
            row.sizes.append(size)
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Настройки

struct SettingsScreen: View {
    /// Как приложение зовут на экране и в Siri (CFBundleDisplayName): «Питомец».
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Питомец"
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var bed: Int = 23 * 60
    @State private var island = true
    @State private var roomEvening = RoomEveningMode.standard
    @State private var loaded = false
    @State private var confirmStartOver = false
    /// Волна 19: знакомство, правила или гайд виджета, открытые снова из раздела «Подсказки».
    @State private var guide: GuideKind?
    /// Звук только на этом телефоне (UserDefaults), по умолчанию включён. Читает SoundKit.
    @AppStorage(SoundKit.enabledKey) private var sound = true
    // Волна 32: остальные переключатели «Звук и отклик» и «Уведомления» (PetPref), тоже по умолчанию включены.
    @AppStorage(PetPref.voice.key) private var voice = true
    @AppStorage(PetPref.music.key) private var music = true
    /// «Для разработки» в Release-сборке на iPhone: открывается семью касаниями по строке версии внизу настроек.
    @AppStorage(Self.devUnlockKey) private var devUnlocked = false
    @State private var versionTaps = 0
    @AppStorage(PetPref.haptics.key) private var haptics = true
    @AppStorage(PetPref.notifications.key) private var notifications = true
    /// Что разрешил iPhone; nil — ещё не спросили систему.
    @State private var notifPermission: NotifPermission?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    /// 20:00–23:55 и 00:00–02:00 с шагом 5 минут.
    static let bedOptions: [Int] = Array(stride(from: 20 * 60, to: 24 * 60, by: 5)) + Array(stride(from: 0, through: 2 * 60, by: 5))

    /// Авторы 3D (волна 58). Проверяет PetBreedTests.testAssetCreditsListed: каждый CC-BY из ASSETS_LICENSES.md назван здесь.
    static let modelCredits = "Шиба и Хаски — Quaternius (CC0). Миска «Dog bowl» и мячик «Tennis ball» — Poly by Google (CC-BY 3.0). "
        + "Цветок, книжки и мишка — Kenney Furniture Kit (CC0). Паркет — ambientCG WoodFloor036 (CC0)."

    /// Раздел «Для разработки» (каталог превью): только в отладочной сборке и не на скриншотах UI-тестов.
    /// PET_DEVTOOLS=1 — показать и под UI-тестом: так YardDemoUITests доходит до «Двор 3D».
    /// Семь касаний по версии открывают раздел только там, где он вообще есть (DevGate.devMenu):
    /// в Debug и в ipa с флагом PET_DEV_IPA. В ipa для друзей — нет (волна 59).
    static let devUnlockKey = "pet.devtools.unlocked"

    var body: some View {
        let name = model.snap.name
        let sleep = model.ownerSleep
        NavigationStack {
            Form {
                Section {
                    Picker("Ложусь в", selection: $bed) {
                        ForEach(Self.bedOptions, id: \.self) { m in
                            Text(Self.hm(m)).tag(m)
                        }
                    }
                    .listRowBackground(PetPalette.card)
                } header: {
                    Text("Лампа")
                } footer: {
                    Text("Через 15 минут после этого времени \(name) тоже ляжет спать.")
                }

                // Сон хозяина (OwnerSleep): учится сам по заходам вечером и утром, можно задать руками.
                Section {
                    NavigationLink { OwnerSleepScreen() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Я сплю примерно \(OwnerSleep.text(sleep.window))")
                                .monospacedDigit()
                            Text(OwnerSleep.status(sleep))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(PetPalette.card)
                    .accessibilityIdentifier("settings.ownerSleep")
                    if let m = OwnerSleep.suggestedBed(sleep, bedMin: bed) {
                        Button("Ложиться вместе со мной: \(Self.hm(m))") { bed = m }
                            .listRowBackground(PetPalette.card)
                            .accessibilityIdentifier("settings.ownerSleep.bed")
                    }
                } footer: {
                    Text(Self.ownerSleepNote(sleep, name: name))
                }

                Section {
                    Picker("Комната вечером", selection: $roomEvening) {
                        ForEach(RoomEveningMode.allCases, id: \.self) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .listRowBackground(PetPalette.card)
                    .accessibilityIdentifier("settings.roomEvening")
                } footer: {
                    Text(Self.roomEveningNote(roomEvening))
                }

                Section {
                    Toggle("\(name) на острове", isOn: $island)
                        .listRowBackground(PetPalette.card)
                } header: {
                    Text("Остров")
                } footer: {
                    Text("Остров — тёмная область вокруг камеры вверху экрана. Там и на экране блокировки видно питомца и кнопки ухода.")
                }

                Section {
                    Toggle(PetPref.sound.title, isOn: $sound)
                        .listRowBackground(PetPalette.card)
                        .accessibilityIdentifier(PetPref.sound.id)
                    Toggle(isOn: $voice) { prefLabel(.voice) }
                        .disabled(!sound)
                        .listRowBackground(PetPalette.card)
                        .accessibilityIdentifier(PetPref.voice.id)
                    Toggle(isOn: $music) { prefLabel(.music) }
                        .listRowBackground(PetPalette.card)
                        .accessibilityIdentifier(PetPref.music.id)
                    Toggle(PetPref.haptics.title, isOn: $haptics)
                        .listRowBackground(PetPalette.card)
                        .accessibilityIdentifier(PetPref.haptics.id)
                } header: {
                    Text("Звук и отклик")
                } footer: {
                    Text("Тихие звуки одной громкости. В беззвучном режиме телефона их не слышно. Музыка: Alex McCulloch (Pro Sensory), omfgdude — CC0.")
                }

                Section {
                    Toggle(PetPref.notifications.title, isOn: $notifications)
                        .listRowBackground(PetPalette.card)
                        .accessibilityIdentifier(PetPref.notifications.id)
                    if let p = notifPermission, NotifPref.needsSystemSettings(on: notifications, permission: p),
                       let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        Button("Открыть настройки iPhone") { openURL(url) }
                            .listRowBackground(PetPalette.card)
                            .accessibilityIdentifier("settings.notifications.system")
                    }
                } footer: {
                    Text(NotifPref.footer(on: notifications, permission: notifPermission ?? .allowed))
                }

                // Волна 57: вместо «Привычек» — команды голосом (SitIntent/PawIntent, ShortcutsProvider).
                Section {
                    Label("«\(Self.appName), сидеть»", systemImage: "mic.fill")
                        .listRowBackground(PetPalette.card)
                        .accessibilityIdentifier("settings.siri")
                } footer: {
                    Text("И «\(Self.appName), дай лапу» — Siri откроет приложение, \(name) выполнит команду.")
                }

                // Свой персонаж (волна 12): папка из «Файлов» вместо Шибы в комнате.
                Section {
                    NavigationLink {
                        CharacterPacksScreen()
                    } label: {
                        LabeledContent {
                            Text(model.characterEntry?.name ?? model.breed.title)
                        } label: {
                            Label("Свой персонаж", systemImage: "figure.walk.circle")
                        }
                    }
                    .listRowBackground(PetPalette.card)
                    .accessibilityIdentifier("settings.character")
                } footer: {
                    Text("Папка из «Файлов»: модель с анимациями и character.json — имя, клипы, рост, цвет. Характер, вещи и сохранение остаются, меняется только облик.")
                }

                // Волна 19: всё, что показывалось один раз, можно открыть снова.
                Section {
                    Button { guide = .intro } label: {
                        Label("Как тут всё устроено", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("settings.intro")
                    Button { guide = .rules } label: {
                        Label("Честно о главном: сердечки", systemImage: "heart.text.square")
                    }
                    .accessibilityIdentifier("settings.rules")
                    Button { guide = .widget } label: {
                        Label("Виджет и остров", systemImage: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("settings.widgetGuide")
                } header: {
                    Text("Подсказки")
                }
                .foregroundStyle(PetPalette.ink)
                .listRowBackground(PetPalette.card)

                // Волна 58: авторы 3D-моделей. CC-BY требует подписи в приложении (content/ASSETS_LICENSES.md).
                Section {
                    Text(Self.modelCredits)
                        .petFont(12)
                        .foregroundStyle(PetPalette.soft)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(PetPalette.card)
                        .accessibilityIdentifier("settings.credits")
                    Text(AboutInfo.versionLine(Bundle.main.infoDictionary))
                        .petFont(13)
                        .foregroundStyle(PetPalette.ink)
                        .listRowBackground(PetPalette.card)
                        .accessibilityIdentifier("settings.about.version")
                    Text(AboutInfo.feedbackLine)
                        .petFont(13)
                        .foregroundStyle(PetPalette.soft)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(PetPalette.card)
                        .accessibilityIdentifier("settings.feedback")
                } header: {
                    Text("Об игре")
                }

                if DevGate.showDevSection(uiTest: Env.isUITest, devtoolsEnv: Env.value("PET_DEVTOOLS") == "1",
                                          unlocked: devUnlocked) {
                    Section("Для разработки") {
                        NavigationLink("Каталог превью") { PreviewCatalogScreen() }
                            .listRowBackground(PetPalette.card)
                    }
                }

                Section {
                    Button("Начать заново", role: .destructive) { confirmStartOver = true }
                        .listRowBackground(PetPalette.card)
                } footer: {
                    // Версия видна в «Об игре»; здесь — только цель для семи касаний, и только где есть dev-раздел.
                    if DevGate.devMenu {
                        Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                versionTaps += 1
                                if versionTaps >= 7 { devUnlocked = true }
                            }
                            .accessibilityIdentifier("settings.version")
                    }
                }
            }
            // Тёплая «бумага» приложения вместо системного серого фона списка.
            .scrollContentBackground(.hidden)
            .background(PetPalette.bg.ignoresSafeArea())
            .tint(PetPalette.accent)
            .toolbarBackground(PetPalette.bg, for: .navigationBar)
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            // pet://characters (UI-тесты): сразу экран «Свой персонаж» поверх настроек.
            .navigationDestination(isPresented: Bindable(model).showCharacters) { CharacterPacksScreen() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .onAppear {
                guard !loaded else { return }
                if let f = model.file {
                    bed = Self.bedOptions.contains(f.owner.bedMin) ? f.owner.bedMin : 23 * 60
                    island = f.island.enabled
                    roomEvening = f.roomEveningMode
                }
                loaded = true
            }
            .onChange(of: bed) { _, m in
                if loaded, m != model.file?.owner.bedMin { model.setBedtime(minute: m) }
            }
            .onChange(of: roomEvening) { _, m in
                if loaded, m != model.file?.roomEveningMode { model.setRoomEvening(m) }
            }
            .onChange(of: sound) { _, on in
                // Выключили — замолчать сразу; включили — короткое «да», чтобы было слышно громкость.
                if on { SoundKit.shared.play(.ok) } else { SoundKit.shared.stop() }
                // Музыка играет по своему переключателю: движок поднимется снова, если она включена.
                SoundKit.shared.musicPrefChanged()
            }
            .onChange(of: voice) { _, on in
                if on { SoundKit.shared.play(.yip) }
            }
            .onChange(of: music) { _, _ in
                SoundKit.shared.musicPrefChanged()
            }
            .onChange(of: haptics) { _, on in
                // Включили — короткий отклик, чтобы почувствовать.
                if on { Feel.haptic(.tap) }
            }
            .onChange(of: notifications) { _, _ in
                Task {
                    await NotificationScheduler.prefChanged()
                    notifPermission = await NotificationScheduler.permission()
                }
            }
            .task {
                notifPermission = await NotificationScheduler.permission()
            }
            .onChange(of: scenePhase) { _, phase in
                // Вернулись из настроек iPhone — разрешение могло поменяться.
                guard phase == .active else { return }
                Task { notifPermission = await NotificationScheduler.permission() }
            }
            .onChange(of: island) { _, on in
                guard loaded, on != model.file?.island.enabled else { return }
                Task { await AppActions.shared.setIsland(enabled: on) }
            }
            .confirmationDialog("Начать заново с новым щенком? Этот питомец не вернётся.",
                                isPresented: $confirmStartOver, titleVisibility: .visible) {
                Button("Начать заново", role: .destructive) {
                    model.startOver()
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            }
            .sheet(item: $guide) { kind in
                switch kind {
                case .intro: IntroScreen(onDone: { guide = nil }).environment(model)
                case .rules: RulesScreen(onDone: { GuideCenter.shared.ackRules(); guide = nil }).environment(model)
                case .widget: WidgetGuideSheet(onDone: { guide = nil }).environment(model)
                }
            }
        }
        .presentationBackground(PetPalette.bg)
    }

    static func hm(_ m: Int) -> String {
        String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Переключатель с пояснением под названием (PetPref.footer).
    private func prefLabel(_ p: PetPref) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.title)
            if let f = p.footer {
                Text(f)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func ownerSleepNote(_ est: SleepEstimate, name: String) -> String {
        let base = "В это время \(name) не шлёт уведомлений."
        switch est.source {
        case .learning: return base + " Окно подстраивается само: по тому, когда ты последний раз заходишь вечером и первый — утром."
        case .learned: return base + " Окно выучено по последним двум неделям и меняется вместе с тобой."
        case .manual: return base + " Задано вручную — само не меняется."
        }
    }

    static func roomEveningNote(_ m: RoomEveningMode) -> String {
        switch m {
        case .byTime: "После заката в комнате тёплый вечерний свет, после «Ложусь в» — ночной полумрак."
        case .byTheme: "В тёмной теме телефона — вечерний свет, ночью — полумрак. В светлой — всегда день."
        case .alwaysDay: "Комната всегда светлая, как днём."
        }
    }
}

/// «Я сплю примерно»: задать окно сна вручную, снова учиться самому или забыть выученное (OwnerSleep).
struct OwnerSleepScreen: View {
    @Environment(AppModel.self) private var model
    @State private var bed = OwnerSleep.defaultWindow.bed
    @State private var wake = OwnerSleep.defaultWindow.wake
    @State private var loaded = false
    @State private var confirmForget = false

    /// Засыпаю 18:00–04:00, просыпаюсь 04:00–14:00 — как вечер и утро в OwnerSleep (с округлением до 5 минут).
    static let bedOptions: [Int] = Array(stride(from: 18 * 60, to: 24 * 60, by: 5)) + Array(stride(from: 0, through: 4 * 60, by: 5))
    static let wakeOptions: [Int] = Array(stride(from: 4 * 60, through: 14 * 60, by: 5))

    var body: some View {
        let est = model.ownerSleep
        Form {
            Section {
                LabeledContent("Сейчас", value: OwnerSleep.text(est.window))
                    .monospacedDigit()
                    .listRowBackground(PetPalette.card)
                    .accessibilityIdentifier("ownerSleep.now")
            } footer: {
                Text(Self.note(est))
            }

            Section {
                Picker("Засыпаю", selection: $bed) {
                    ForEach(Self.bedOptions, id: \.self) { m in Text(OwnerSleep.hm(m)).tag(m) }
                }
                .listRowBackground(PetPalette.card)
                Picker("Просыпаюсь", selection: $wake) {
                    ForEach(Self.wakeOptions, id: \.self) { m in Text(OwnerSleep.hm(m)).tag(m) }
                }
                .listRowBackground(PetPalette.card)
            } header: {
                Text("Задать вручную")
            } footer: {
                // Кнопка «Учиться самому» есть только в ручном режиме — без неё сноска ссылалась в пустоту.
                Text(est.source == .manual
                     ? "Выбранное время держится, пока не нажмёшь «Учиться самому»."
                     : "Тронешь время — окно станет ручным и само меняться перестанет.")
            }

            Section {
                if est.source == .manual {
                    Button("Учиться самому") { model.setOwnerSleep(nil); sync(model.ownerSleep) }
                        .listRowBackground(PetPalette.card)
                }
                Button("Забыть выученное", role: .destructive) { confirmForget = true }
                    .listRowBackground(PetPalette.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PetPalette.bg.ignoresSafeArea())
        .tint(PetPalette.accent)
        .navigationTitle("Я сплю")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            sync(est)
            loaded = true
        }
        // Тронул выбор — окно становится ручным; совпало с тем, что уже стоит, — ничего не пишем.
        .onChange(of: bed) { _, _ in commit() }
        .onChange(of: wake) { _, _ in commit() }
        .confirmationDialog("Забыть, когда ты спишь? Две недели наблюдений пропадут, до 5 ночей снова 00:00–08:00.",
                            isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Забыть", role: .destructive) {
                model.forgetOwnerSleep()
                sync(model.ownerSleep)
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// Пикеры — на текущее окно. Запись не случится: commit пропускает окно, совпавшее с текущим.
    private func sync(_ est: SleepEstimate) {
        bed = Self.bedOptions.contains(est.window.bed) ? est.window.bed : OwnerSleep.defaultWindow.bed
        wake = Self.wakeOptions.contains(est.window.wake) ? est.window.wake : OwnerSleep.defaultWindow.wake
    }

    private func commit() {
        guard loaded else { return }
        let w = SleepWindow(bed: bed, wake: wake)
        if w != model.ownerSleep.window { model.setOwnerSleep(w) }
    }

    static func note(_ est: SleepEstimate) -> String {
        switch est.source {
        case .learning(let k): "Пока учусь: \(k) из \(OwnerSleep.minNights) ночей. До тех пор — 00:00–08:00."
        case .learned: "Выучено по \(est.nights) ночам за две недели: медиана последнего захода вечером и первого утром."
        case .manual: "Задано вручную."
        }
    }
}

/// Все превью виджетов, острова и мордочек на одном экране (PreviewCatalog из Shared).
struct PreviewCatalogScreen: View {
    var body: some View {
        let items = previewCatalog()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                // Двор в 3D (волна 33 F): станции и ярусы — отдельным экраном, RealityView в ленте превью тяжёл.
                NavigationLink { YardArtDemoScreen() } label: {
                    Text("Двор 3D: станции и ярусы")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PetPalette.accent)
                }
                .accessibilityIdentifier("yard.demo")
                WeatherPinRow()
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(items[i].name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PetPalette.soft)
                        items[i].view
                    }
                }
            }
            .padding(16)
        }
        .background(PetPalette.bg.ignoresSafeArea())
        .navigationTitle("Превью")
    }
}

/// «Погода в комнате» (волна 39 D): закрепить погоду для проверки — капли за окном, приглушённый свет,
/// реплики. Только до перезапуска (Weather.pinned в памяти); «авто» — снова по календарю. Двор берёт её же.
private struct WeatherPinRow: View {
    @State private var pinned: WeatherKind? = Weather.pinned

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Погода в комнате")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(PetPalette.soft)
            HStack(spacing: 6) {
                chip("авто", on: pinned == nil, id: "weather.pin.auto") { set(nil) }
                ForEach([WeatherKind.clear, .cloudy, .rain, .snow], id: \.self) { w in
                    chip(w.title.lowercased(), on: pinned == w, id: "weather.pin.\(w.rawValue)") { set(w) }
                }
            }
        }
    }

    private func set(_ w: WeatherKind?) {
        Weather.pinned = w
        pinned = w
    }

    private func chip(_ title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .frame(minHeight: 32)
                .background(on ? PetPalette.accent : PetPalette.card, in: Capsule())
                .foregroundStyle(on ? Color.white : PetPalette.ink)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Ошибка сохранения

/// Файл сохранения не читается. Он уже отложен в state.broken-<t>.json; молча новый щенок не заводится.
struct StoreErrorScreen: View {
    @Environment(AppModel.self) private var model
    let message: String
    @State private var confirmStartOver = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(PetPalette.red)
            Text("Не открывается сохранение")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(PetPalette.soft)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                model.retryStore()
            } label: {
                Text("Попробовать снова").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(PetPalette.accent)
            Button("Начать заново", role: .destructive) { confirmStartOver = true }
                .frame(minHeight: 44)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PetPalette.bg.ignoresSafeArea())
        .confirmationDialog("Начать с новым щенком? Старое сохранение останется лежать в отдельном файле.",
                            isPresented: $confirmStartOver, titleVisibility: .visible) {
            Button("Начать заново", role: .destructive) { model.startOver() }
            Button("Отмена", role: .cancel) {}
        }
    }
}
