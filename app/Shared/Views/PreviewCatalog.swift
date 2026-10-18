// Каталог превью: все виджеты, остров и Live Activity в четырёх состояниях.
// Им пользуются Xcode Previews, экран отладки в приложении и снимки в тестах (SnapshotCatalog).
// Фикстуры детерминированы: фиксированное время, petId и часовой пояс, поза закреплена.

import SwiftUI
@preconcurrency import PetCore

enum PreviewFixtures {
    /// 2026-09-21 14:13 UTC: день, хозяин не спит.
    static let dayT: Double = 1_790_000_000
    static let moods = ["fed", "hungry", "asleep", "critical", "walking"]
    static let families = ["small", "medium", "large", "circular", "rectangular", "inline",
                           "islandCompact", "islandExpanded", "lockActivity"]

    static func file(_ mood: String) -> (file: SaveFile, t: Double) {
        let t = mood == "asleep" ? dayT + 13 * 3600 : dayT   // 03:13 UTC — ночь
        var f = SaveFile.fresh(now: t)
        f.petId = "preview"
        f.deviceId = "preview"
        f.owner.tzOffsetMin = 0
        f.pet.t = t
        f.build = nil
        f.lastAction = nil
        switch mood {
        case "hungry":
            set(&f, food: 12, clean: 70, energy: 60, fun: 55, love: 60)
            f.pet.hearts = min(f.pet.hearts, 3)
        case "asleep":
            set(&f, food: 70, clean: 75, energy: 30, fun: 60, love: 70)
        case "critical":
            set(&f, food: 0, clean: 15, energy: 20, fun: 10, love: 10)
            f.pet.hearts = 1
        case "walking":
            // Гуляет 20 минут, вернётся через 1 ч 10 мин с шишкой.
            set(&f, food: 70, clean: 65, energy: 60, fun: 80, love: 85)
            f.pet.outing = Outing(from: t - 20 * 60, until: t + 70 * 60, find: "cone")
        default:
            set(&f, food: 92, clean: 90, energy: 85, fun: 88, love: 95)
        }
        return (f, t)
    }

    private static func set(_ f: inout SaveFile, food: Double, clean: Double, energy: Double, fun: Double, love: Double) {
        f.pet.needs[.food] = food
        f.pet.needs[.clean] = clean
        f.pet.needs[.energy] = energy
        f.pet.needs[.fun] = fun
        f.pet.needs[.love] = love
    }

    /// Снимок для состояния. Ядро решает всё само; позу и уровень закрепляем, чтобы картинка не зависела от баланса.
    static func snapshot(_ mood: String) -> PetSnapshot {
        let (f, t) = file(mood)
        var s = Presenter.make(f, at: t, upcoming: [])
        switch mood {
        case "hungry":
            s.pose = .hungry
            s.level = max(s.level, 1)
        case "asleep":
            s.pose = .sleep
        case "critical":
            s.pose = .critical
            s.level = 3
            s.urgent = true
            if s.main == .pet { s.main = .feed }
        case "walking":
            s.pose = .away
        default:
            s.pose = .happy
        }
        return s
    }

    /// Снимок для каталога: как snapshot, плюс таймеры — длинный у сытого («через 9 ч 25 мин»)
    /// и короткий у критичного (живой отсчёт). В snapshot их нет: его берёт заглушка виджета,
    /// а там время настоящее, и таймер из прошлого выглядел бы странно.
    static func catalogSnapshot(_ mood: String) -> PetSnapshot {
        var s = snapshot(mood)
        if let fx = timerFixture(mood) {
            s.timer = NeedTimer(kind: fx.kind, start: s.t, end: s.t + fx.left,
                                title: Presenter.timerTitle(kind: fx.kind, need: fx.need))
        }
        return s
    }

    /// Таймер фикстуры: вид, шкала и сколько осталось.
    static func timerFixture(_ mood: String) -> (kind: String, need: String, left: Double)? {
        switch mood {
        case "fed": return ("low", "clean", 9 * 3600 + 25 * 60)
        case "critical": return ("low", "love", 40 * 60)
        default: return nil
        }
    }

    /// Остров: тот же снимок плюс кнопки из плана острова.
    static func islandState(_ mood: String) -> PetAttributes.ContentState {
        let (f, t) = file(mood)
        var st = PetAttributes.ContentState(catalogSnapshot(mood))
        st.timerNeed = timerFixture(mood)?.need
        let pick = IslandPlan.pick(f, at: t)
        st.primary = pick.primary
        st.secondary = pick.secondary
        if mood == "critical" && st.primary == .pet { st.primary = .feed }
        return st
    }
}

/// Рамка размера виджета и фон, как на домашнем экране.
private struct WidgetFrame<Content: View>: View {
    var size: CGSize
    var radius: CGFloat = 22
    var padding: CGFloat = 14
    var background: Color = PetPalette.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(width: size.width, height: size.height)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(background))
    }
}

/// Одно превью: семейство × состояние. nil — неизвестное имя.
@MainActor
func previewView(family: String, mood: String) -> AnyView? {
    guard PreviewFixtures.moods.contains(mood) else { return nil }
    guard let view = previewBody(family: family, mood: mood) else { return nil }
    // Таймеры в снимках не тикают: «сейчас» — время фикстуры.
    return AnyView(view.environment(\.petFrozenNow, PreviewFixtures.file(mood).t))
}

/// Живой отсчёт для снимка: критичный питомец («Затоскует через 40:00»), но таймер не застывает
/// фразой, а рисуется как в виджете — жадный Text(timerInterval:) на паузе в момент фикстуры.
/// Только семейства, где под таймер мало места.
@MainActor
func previewLiveView(family: String) -> AnyView? {
    guard ["small", "medium", "large", "rectangular", "islandExpanded", "lockActivity"].contains(family),
          let view = previewBody(family: family, mood: "critical") else { return nil }
    return AnyView(view.environment(\.petPausedNow, PreviewFixtures.file("critical").t))
}

@MainActor
private func previewBody(family: String, mood: String) -> AnyView? {
    let snap = PreviewFixtures.catalogSnapshot(mood)
    let state = PreviewFixtures.islandState(mood)
    let lockBg = Color(hex: 0x2a2320)
    switch family {
    case "small":
        return AnyView(WidgetFrame(size: CGSize(width: 170, height: 170)) { WidgetSmallView(snap: snap) })
    case "medium":
        return AnyView(WidgetFrame(size: CGSize(width: 364, height: 170)) { WidgetMediumView(snap: snap) })
    case "large":
        return AnyView(WidgetFrame(size: CGSize(width: 364, height: 382)) { WidgetLargeView(snap: snap) })
    case "circular":
        return AnyView(WidgetFrame(size: CGSize(width: 76, height: 76), radius: 38, padding: 0, background: lockBg) {
            AccessoryCircularView(snap: snap).foregroundStyle(Color.white)
        })
    case "rectangular":
        return AnyView(WidgetFrame(size: CGSize(width: 172, height: 76), radius: 12, padding: 4, background: lockBg) {
            AccessoryRectangularView(snap: snap).foregroundStyle(Color.white)
        })
    case "inline":
        return AnyView(WidgetFrame(size: CGSize(width: 250, height: 24), radius: 6, padding: 2, background: lockBg) {
            AccessoryInlineView(snap: snap).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
        })
    case "islandCompact":
        return AnyView(IslandCompactPreview(state: state).frame(width: 250).padding(8).background(Color.black.opacity(0.85)))
    case "islandExpanded":
        return AnyView(IslandExpandedPreview(state: state).frame(width: 380).padding(8).background(Color.black.opacity(0.85)))
    case "lockActivity":
        return AnyView(WidgetFrame(size: CGSize(width: 364, height: 140), radius: 24, padding: 0) {
            LockScreenActivityView(name: snap.name, state: state)
        })
    default:
        return nil
    }
}

/// Весь каталог: «семейство/состояние» → вид. Порядок стабильный.
@MainActor
public func previewCatalog() -> [(name: String, view: AnyView)] {
    var out: [(name: String, view: AnyView)] = []
    for fam in PreviewFixtures.families {
        for mood in PreviewFixtures.moods {
            if let v = previewView(family: fam, mood: mood) {
                out.append((name: "\(fam)_\(mood)", view: v))
            }
        }
    }
    // Мордочка во всех позах — для проверки стиля.
    for p in Pose.allCases {
        out.append((name: "face_\(p.rawValue)", view: AnyView(
            PetFaceView(pose: p).frame(width: 120, height: 120).padding(8).background(PetPalette.bg))))
    }
    return out
}

#Preview("Каталог") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(previewCatalog().enumerated()), id: \.offset) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.element.name).font(.caption.monospaced())
                    item.element.view
                }
            }
        }
        .padding()
    }
    .background(PetPalette.bg)
}
