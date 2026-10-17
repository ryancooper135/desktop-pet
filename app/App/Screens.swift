// Второстепенные экраны: шкалы по запросу, «Пока тебя не было», настройки, ошибка сохранения, каталог превью.

import SwiftUI
@preconcurrency import PetCore

// MARK: - Шкалы

struct NeedsSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let snap = model.snap
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
            if let next = nextEvent {
                Text(next)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(PetPalette.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("needs.sheet")
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
                        Text(card.text)
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

            Text(report.cta)
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
                Button("Закрыть") { model.away = nil }
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
                    .font(.system(size: 16, weight: .medium, design: .rounded))
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
    @State private var loaded = false
    @State private var confirmStartOver = false

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

                Section {
                    Toggle("\(name) в островке", isOn: $island)
                        .listRowBackground(PetPalette.card)
                } header: {
                    Text("Островок")
                } footer: {
                    Text("Островок — тёмная область вокруг камеры вверху экрана. Там и на экране блокировки видно питомца и кнопки ухода.")
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
                }
                loaded = true
            }
            .onChange(of: bed) { _, m in
                if loaded, m != model.file?.owner.bedMin { model.setBedtime(minute: m) }
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
