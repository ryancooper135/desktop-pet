// Экран «Свой персонаж» (волна 12): установленные паки, какой в комнате, «Вернуть Шибу», удаление и
// «Добавить из «Файлов»» (fileImporter: папка целиком или character.json + модель). Пак с ошибками в списке
// виден с причинами красным, поставить его нельзя; чего не хватит без необязательных клипов — серым.
// Логика — CharacterPack и CharacterStore (Shared), копирование и выбор — AppModel. Открывается из настроек
// и по pet://characters. Формат папки — DECISIONS.md, «Волна 12».

import SwiftUI
import UniformTypeIdentifiers

struct CharacterPacksScreen: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var deleting: CharacterStore.Entry? = nil

    /// Что можно выбрать в «Файлах»: папку пака или его файлы по отдельности.
    static let types: [UTType] = [.folder, .usdz, .usd, .realityFile, .json]

    var body: some View {
        Form {
            Section {
                ShibaRow(active: model.character == nil) { model.setCharacter(nil) }
                    .listRowBackground(PetPalette.card)
                ForEach(model.characterPacks) { e in
                    PackRow(entry: e, active: e.id == model.character) { model.setCharacter(e.id) }
                        .listRowBackground(PetPalette.card)
                        .swipeActions {
                            Button("Удалить", role: .destructive) { deleting = e }
                        }
                        .contextMenu {
                            Button("Удалить", systemImage: "trash", role: .destructive) { deleting = e }
                        }
                }
            } header: {
                Text("Кто в комнате")
            } footer: {
                Text(model.characterPacks.isEmpty
                     ? "Своих пока нет. Характер, вещи и сохранение у всех общие — меняется только облик."
                     : "Удалить — смахни строку влево. Характер, вещи и сохранение общие — меняется только облик.")
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("Добавить из «Файлов»", systemImage: "folder.badge.plus")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .listRowBackground(PetPalette.card)
                .accessibilityIdentifier("characters.add")
            } footer: {
                Text("Выбери папку целиком или файлы из неё. Такое же имя ещё раз — пак заменится: так его чинят.")
            }

            Section {
                ForEach(Array(Self.howTo.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(PetPalette.card)
                }
            } header: {
                Text("Как собрать папку")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PetPalette.bg.ignoresSafeArea())
        .tint(PetPalette.accent)
        .toolbarBackground(PetPalette.bg, for: .navigationBar)
        .navigationTitle("Свой персонаж")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("characters.screen")
        .onAppear { model.reloadCharacterPacks() }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.types, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.installCharacters(urls)
            case .failure(let error): model.refuse(error.localizedDescription)
            }
        }
        .confirmationDialog("Удалить «\(deleting?.name ?? "")»?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let e = deleting { model.deleteCharacter(e.id) }
                deleting = nil
            }
        } message: {
            Text("Папка удалится из приложения. В «Файлах» оригинал останется.")
        }
    }

    /// Коротко о формате — полный в DECISIONS.md.
    static let howTo = [
        "В папке два файла: model.usdz (модель со скелетом и одной анимацией-таймлайном) и character.json.",
        "character.json: name и clips — куски таймлайна в секундах: \"idle\": {\"start\": 0, \"end\": 3.3}.",
        "Обязательны idle, walk, eat, sit, lie, sleep, death. Остальных нет — пропадёт только своё движение.",
        "Клипы в файле зовутся иначе — rename: {\"idle\": \"Idle_Breath\"}. Ещё можно: scale, lift, yaw, color, bones.",
    ]
}

/// Шиба из коробки: всегда первая, её не удалить.
private struct ShibaRow: View {
    let active: Bool
    let use: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? .white : PetPalette.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(active ? PetPalette.accent : PetPalette.accent.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Шиба")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                Text("Из коробки")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(PetPalette.soft)
            }
            Spacer(minLength: 6)
            if active {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PetPalette.accent)
            } else {
                Button("Вернуть Шибу", action: use)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("characters.shiba")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Пак: имя, автор и лицензия, ошибки (красным) или чего не будет (серым, первые три), кнопка «Сделать активным».
private struct PackRow: View {
    let entry: CharacterStore.Entry
    let active: Bool
    let use: () -> Void

    /// Больше трёх «чего не будет» — хвост одной строкой, чтобы список не тонул в мелочах.
    static let offShown = 3

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.ok ? "figure.walk" : "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? .white : (entry.ok ? PetPalette.accent : PetPalette.red))
                .frame(width: 36, height: 36)
                .background(Circle().fill(active ? PetPalette.accent
                                          : (entry.ok ? PetPalette.accent : PetPalette.red).opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.ink)
                    Spacer(minLength: 6)
                    if active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(PetPalette.accent)
                    } else if entry.ok {
                        Button("Сделать активным", action: use)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("characters.use.\(entry.id)")
                    }
                }
                if let by = byline {
                    Text(by)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                }
                if !entry.ok {
                    ForEach(entry.check.errors, id: \.self) { e in
                        Text(e)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PetPalette.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("characters.error.\(entry.id)")
                }
                ForEach(entry.check.off.prefix(Self.offShown), id: \.self) { o in
                    Text(o)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if entry.check.off.count > Self.offShown {
                    Text("и ещё \(entry.check.off.count - Self.offShown) движ. не будет")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(PetPalette.soft)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("characters.pack.\(entry.id)")
    }

    private var byline: String? {
        let parts = [entry.config?.author, entry.config?.license].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
