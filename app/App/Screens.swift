// Второстепенные экраны: шкалы по запросу, «Пока тебя не было», настройки, ошибка сохранения, каталог превью.

import SwiftUI
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
                Text("Как \(snap.name)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                Spacer()
                HeartsView(hearts: snap.hearts, max: snap.heartsMax, size: 14)
            }
            ForEach(VisibleNeeds.all, id: \.self) { n in
                NeedBar(need: n, value: snap.needs[n] ?? 0)
            }
            // Шерсть одной строкой (волна 5): стадия от ухода за неделю, см. Shared/Coat.swift.
            if let coat = model.coat, snap.alive {
                Text("Шерсть: \(coat.stage.title.lowercased())")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
                    .accessibilityIdentifier("needs.coat")
            }
            if let next = nextEvent {
                Text(next)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
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
        guard let e = ForecastTools.nextLow(events, after: now) else { return "Сутки без забот" }
        return "\(ForecastTools.title(e)) в \(Clock.hm(e.t))"
    }
}

// MARK: - Пока тебя не было

struct AwayScreen: View {
    @Environment(AppModel.self) private var model
    let report: AwayReport

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)
            PetFaceView(pose: model.snap.pose)
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text(report.greet)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .multilineTextAlignment(.center)
                Text(report.subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(report.cards) { card in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: card.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PetPalette.accent)
                            .frame(width: 22)
                        Text(Presenter.keepDash(card.text))
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(PetPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20).fill(PetPalette.card))

            Text(Presenter.keepDash(report.cta))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.ink)
                .multilineTextAlignment(.center)

            Spacer(minLength: 10)

            if report.died {
                Button {
                    model.startOver()
                } label: {
                    Text("Начать заново").frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(PetPalette.accent)
                // Вторая кнопка — тихая, в тон экрана, а не системно-синяя.
                Button("Закрыть") { model.away = nil }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tint(PetPalette.soft)
                    .frame(minHeight: 44)
            } else {
                if let _ = model.snap.main.action {
                    Button {
                        model.away = nil
                        model.doMain()
                    } label: {
                        Label(model.snap.main.title, systemImage: model.snap.main.icon)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PetPalette.accent)
                }
                Button("Потом") { model.away = nil }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tint(PetPalette.soft)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("away.screen")
    }
}

// MARK: - Настройки

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var bed: Int = 23 * 60
    @State private var island = true
    @State private var roomEvening = RoomEveningMode.standard
    @State private var loaded = false
    @State private var confirmStartOver = false
    /// Звук только на этом телефоне (UserDefaults), по умолчанию включён. Читает SoundKit.
    @AppStorage(SoundKit.enabledKey) private var sound = true

    /// 20:00–23:55 и 00:00–02:00 с шагом 5 минут.
    static let bedOptions: [Int] = Array(stride(from: 20 * 60, to: 24 * 60, by: 5)) + Array(stride(from: 0, through: 2 * 60, by: 5))

    /// Раздел «Для разработки» (каталог превью): только в отладочной сборке и не на скриншотах UI-тестов.
    static var showDevTools: Bool {
        #if DEBUG
        return !Env.isUITest
        #else
        return false
        #endif
    }

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
                    Toggle("Звук", isOn: $sound)
                        .listRowBackground(PetPalette.card)
                        .accessibilityIdentifier("settings.sound")
                } footer: {
                    Text("Тихие звуки в одной тональности. В беззвучном режиме телефона их не слышно.")
                }

                Section {
                    NavigationLink {
                        HabitsScreen()
                    } label: {
                        Label("Привычки и «Команды»", systemImage: "checklist")
                    }
                    .listRowBackground(PetPalette.card)
                    .accessibilityIdentifier("settings.habits")
                } footer: {
                    Text("«\(HabitsScreen.appName), я дома», «я выпил воды» — Siri и автоматизации отмечают твой день, \(name) отвечает и даёт монеты.")
                }

                if Self.showDevTools {
                    Section("Для разработки") {
                        NavigationLink("Каталог превью") { PreviewCatalogScreen() }
                            .listRowBackground(PetPalette.card)
                    }
                }

                Section {
                    Button("Начать заново", role: .destructive) { confirmStartOver = true }
                        .listRowBackground(PetPalette.card)
                }
            }
            // Тёплая «бумага» приложения вместо системного серого фона списка.
            .scrollContentBackground(.hidden)
            .background(PetPalette.bg.ignoresSafeArea())
            .tint(PetPalette.accent)
            .toolbarBackground(PetPalette.bg, for: .navigationBar)
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
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
        }
        .presentationBackground(PetPalette.bg)
    }

    static func hm(_ m: Int) -> String {
        String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func ownerSleepNote(_ est: SleepEstimate, name: String) -> String {
        let base = "В это время \(name) не шлёт уведомлений."
        switch est.source {
        case .learning: return base + " Учусь сам: по тому, когда ты последний раз заходишь вечером и первый — утром."
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
                Text("Выбранное время держится, пока не нажмёшь «Учиться самому».")
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
