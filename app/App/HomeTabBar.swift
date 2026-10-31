// Волна 53 «B · Стекло»: таб-бар главного экрана вместо ряда из пяти кругов и боковых «Двор»/«Гулять».
// Стеклянная капсула «Дом · Двор · Игры · Шкаф · Команды» и справа белый стеклянный круг «Гулять» (WalkButton circle).
// Id прежние — тесты и подсказки ведут туда же: open.yard, open.games (меню open.<игра>), open.tricks, act.walk;
// «Шкаф» (tab.wardrobe) — меню «Дом» (open.house), «Альбом» (open.album), «Автомат» (act.capsule).
// Подписи фиксированного кегля, как у системного таб-бара; при крупном шрифте долгое нажатие показывает
// увеличенный пункт (Large Content Viewer).

import SwiftUI
@preconcurrency import PetCore

struct HomeTabBar: View {
    @Environment(AppModel.self) private var model
    let snap: PetSnapshot
    @State private var taps: [String: Int] = [:]

    var body: some View {
        let gate = model.file.map { WalkPlan.gate($0, at: snap.t) }
        let tricks = model.file.map { Tricks.gate($0, at: snap.t) } ?? Tricks.loadingReason
        let total = Finds.total(albumFinds(model.file, at: snap.t))
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                homeTab
                yardTab
                gamesTab
                wardrobeTab(total: total)
                tricksTab(tricks)
            }
            .padding(.horizontal, 5)
            .frame(height: BMetrics.tabBar)
            .bGlass(Capsule())
            if let gate {
                WalkButton(gate: gate, circle: true)
            }
        }
    }

    private func bump(_ k: String) { taps[k, default: 0] += 1 }

    // MARK: пункты

    /// «Дом» — где мы есть: выделен, нажатие ничего не открывает.
    private var homeTab: some View {
        BTabItem(icon: "house.fill", title: "Дом", active: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Дом"))
            .accessibilityAddTraits([.isButton, .isSelected])
            .accessibilityShowsLargeContentViewer { Label("Дом", systemImage: "house.fill") }
            .accessibilityIdentifier("tab.home")
    }

    /// «Двор» — как прежний круг YardButton: точка, когда копилка полная или плита по карману.
    private var yardTab: some View {
        let badge = model.yardBadge(now: snap.t)
        return Button {
            bump("yard")
            model.showYard = true
        } label: {
            BTabItem(icon: "tree.fill", title: "Двор", badge: badge, bounce: taps["yard", default: 0])
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(Text("Двор"))
        .accessibilityValue(Text(badge ? "есть что собрать или купить" : ""))
        .accessibilityHint(Text("Станции, копилка, ярусы"))
        .accessibilityShowsLargeContentViewer { Label("Двор", systemImage: "tree.fill") }
        .accessibilityIdentifier("open.yard")
    }

    /// «Игры» — меню мини-игр, как прежний GamesButton (пункты open.<MiniGame.rawValue>).
    private var gamesTab: some View {
        let busy = model.file.flatMap { MiniGames.busy($0, at: snap.t) }
        return Menu {
            ForEach(MiniGame.allCases, id: \.self) { g in
                Button {
                    switch g {
                    case .ball: model.showCatch = true
                    case .blockduo: model.showBlockDuo = true
                    case .runner: model.showRunner = true
                    }
                } label: {
                    Label(g.name, systemImage: g.icon)
                }
                .accessibilityIdentifier("open.\(g.rawValue)")
            }
        } label: {
            BTabItem(icon: "gamecontroller.fill", title: "Игры")
        }
        .accessibilityLabel(Text("Мини-игры"))
        .accessibilityValue(Text(busy.map { MiniGames.noteText($0, name: model.snap.name) } ?? ""))
        .accessibilityHint(Text(PetNames.adapt(MiniGames.menuHint(), name: model.snap.name)))
        .accessibilityShowsLargeContentViewer { Label("Игры", systemImage: "gamecontroller.fill") }
        .accessibilityIdentifier("open.games")
    }

    /// «Шкаф» — вещи и комната: дом с интерьером, альбом находок и автомат с капсулами.
    private func wardrobeTab(total: Int) -> some View {
        Menu {
            Button {
                model.showHouse = true
            } label: {
                Label("Дом и комната", systemImage: "house.fill")
            }
            .accessibilityHint(Text("Улучшения дома за монеты"))
            .accessibilityIdentifier("open.house")
            Button {
                model.showAlbum = true
            } label: {
                Label(total > 0 ? "Альбом · \(total > 99 ? "99+" : "\(total)")" : "Альбом", systemImage: "books.vertical.fill")
            }
            .accessibilityLabel(Text("Альбом находок"))
            .accessibilityValue(Text(total > 0 ? "Находок: \(total)" : "Пока пусто"))
            .accessibilityIdentifier("open.album")
            Button {
                model.showCapsule = true
            } label: {
                Label("Автомат", systemImage: "gift.fill")
            }
            .accessibilityHint(Text("Капсулы за билетики и монеты"))
            .accessibilityIdentifier("act.capsule")
        } label: {
            BTabItem(icon: "tshirt.fill", title: "Шкаф")
        }
        .accessibilityLabel(Text("Шкаф"))
        .accessibilityHint(Text("Дом и комната, альбом находок, автомат"))
        .accessibilityShowsLargeContentViewer { Label("Шкаф", systemImage: "tshirt.fill") }
        .accessibilityIdentifier("tab.wardrobe")
    }

    /// «Команды» — лист TricksScreen (волна 57) открывается всегда; когда нельзя — пункт бледнее, причина в VoiceOver.
    private func tricksTab(_ gate: String?) -> some View {
        Button {
            bump("tricks")
            model.showTricks = true
        } label: {
            BTabItem(icon: "pawprint.fill", title: "Команды", dim: gate != nil, bounce: taps["tricks", default: 0])
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(Text("Команды"))
        .accessibilityValue(Text(gate.map { Tricks.reasonText($0) } ?? ""))
        .accessibilityHint(Text("Научить пса командам"))
        .accessibilityShowsLargeContentViewer { Label("Команды", systemImage: "pawprint.fill") }
        .accessibilityIdentifier("open.tricks")
    }
}
