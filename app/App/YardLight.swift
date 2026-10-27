// Волна 38 B: свет двора ночью. Сцены двора (YardLive, превью YardArtStage, переезд YardMoveStage) берут свет
// комнаты PetRoom.lights() — днём он как был, и дневные снимки не меняются. Ночью поверх него тот же
// RoomLighting.apply, что красит комнату, но с пресетом двора: key/fill/rim холодные и тихие (луна), матовое —
// множителем тинта, лампа комнаты погашена. Светящееся (RoomGlow: окна, гирлянды, фонари, лампочки станций,
// таблички «+N/ч») без тинта, а у двух главных огней — тёплый точечный свет без теней: пятно на земле и стене.
// Сцена с night собирается заново по ключу экрана (ночью у неё и геометрия своя), поэтому свет ставится при
// сборке и плавного перехода, как в комнате, нет (DECISIONS, волна 38 B).

import RealityKit

/// Тёплый точечный свет ночью: где, какого цвета, сколько люменов и докуда достаёт. Тени нет.
struct YardNightLamp: Equatable {
    var name: String
    var at: SIMD3<Float>
    var hex: UInt32
    var lumens: Float
    var radius: Float
}

@MainActor
enum YardLight {
    /// Ночь двора — ночь комнаты, только светлее тинтом (станции мелкие и далеко: в тинте комнаты сливаются),
    /// чуть ярче луной, без лампы над лежанкой и без луны в окне (их во дворе нет).
    static let night: RoomLight = {
        var l = RoomLight.night
        l.tint = RoomRGB(0.46, 0.50, 0.68)
        l.keyI = 1100
        l.fillI = 300
        l.lamp = 0
        l.moon = 0
        l.vignette = 0
        return l
    }()

    /// Точечных огней на сцене не больше — каждый стоит пиксельного света на всём, до чего достаёт.
    nonisolated static let maxLamps = 2
    nonisolated static let lampPrefix = "yard.night.light"

    /// Огни двора ночью: фонарь двора (плита «Фонарь», слой 1) и главный огонь района — окно дома зимой,
    /// фонарь на мостике у реки, лампочка у будки на крыше. Днём — ничего. bought — купленные плиты по слоям.
    nonisolated static func lamps(_ district: YardDistrict, top: Int, bought: [Int], night: Bool) -> [YardNightLamp] {
        guard night else { return [] }
        var out: [YardNightLamp] = []
        if bought.count > 1, bought[1] >= 4 {
            // Чуть ниже стекла фонаря (YardArtTier.layer 1: столб в (0.3, 0, -0.18), стекло на 0.86).
            out.append(YardNightLamp(name: "\(lampPrefix).yard", at: SIMD3(0.3, 0.8, -0.18),
                                     hex: YardArtColors.lamp, lumens: 9000, radius: 1.3))
        }
        let top = min(max(top, 1), YardArtTier.plates.count - 1)
        let ctx = YardDecorCtx(top: top, bought: bought, night: true, palette: district.palette)
        let wallZ = YardDecorArt.wallZ
        switch district {
        case .street:
            break
        case .winter:
            // Перед окном дома: светит на снег у стены и на саму стену.
            out.append(YardNightLamp(name: "\(lampPrefix).window", at: SIMD3(0, 0.75, wallZ + 0.35),
                                     hex: YardDecorColors.warm, lumens: 7000, radius: 1.2))
        case .river:
            out.append(YardNightLamp(name: "\(lampPrefix).lantern", at: YardDecorArt.lanternAt(ctx) + SIMD3(0, 0, 0.04),
                                     hex: YardDecorColors.lantern, lumens: 5000, radius: 0.9))
        case .roof:
            out.append(YardNightLamp(name: "\(lampPrefix).bulb", at: YardDecorArt.boothBulbAt + SIMD3(0, -0.05, 0.12),
                                     hex: YardArtColors.lamp, lumens: 6000, radius: 1.1))
        }
        return Array(out.prefix(maxLamps))
    }

    /// Огни переезда ночью: фонарь у дороги и лампочка в кузове (она качается с фургоном — свет в её узле).
    /// node — имя узла сцены, в котором стоит свет (nil — в корне мира).
    nonisolated static func moveLamps(night: Bool) -> [(node: String?, lamp: YardNightLamp)] {
        guard night else { return [] }
        return [
            (nil, YardNightLamp(name: "\(lampPrefix).road", at: SIMD3(-1.0, 1.1, -1.0),
                                hex: YardMoveColors.streetLamp, lumens: 9000, radius: 1.5)),
            ("night.cargo", YardNightLamp(name: "\(lampPrefix).cargo", at: SIMD3(-0.3, 0.74, 0),
                                          hex: YardMoveColors.streetLamp, lumens: 2500, radius: 0.7)),
        ]
    }

    /// Ночь — на собранный мир: лунный свет и тинт, затем огни. Днём ничего не делает.
    /// Зовётся после addChild(PetRoom.lights()) и до того, как в мир сядет пёс: питомец без тинта, как в комнате.
    /// gloom (волна 39 D) — пасмурно, дождь или снег: тот же свет, приглушённый RoomLight.weathered. Днём без
    /// погоды (gloom 0) по-прежнему ничего не делает — дневные снимки не меняются.
    static func apply(night: Bool, gloom: Double = 0, lamps: [(node: String?, lamp: YardNightLamp)], to world: Entity) {
        guard night || gloom > 0 else { return }
        RoomLighting.registerOnce()
        RoomLighting.apply(light(night: night, gloom: gloom), to: world)
        guard night else { return }
        for (node, spec) in lamps.prefix(maxLamps) {
            let parent = node.flatMap { world.findEntity(named: $0) } ?? world
            parent.addChild(light(spec))
        }
    }

    static func apply(night: Bool, gloom: Double = 0, lamps: [YardNightLamp], to world: Entity) {
        apply(night: night, gloom: gloom, lamps: lamps.map { (node: String?.none, lamp: $0) }, to: world)
    }

    /// Свет двора: ночь или день, приглушённые погодой. Лампы комнаты и луны в окне во дворе нет.
    static func light(night: Bool, gloom: Double) -> RoomLight {
        var l = (night ? Self.night : RoomLight.day).weathered(gloom)
        l.lamp = 0
        l.moon = 0
        return l
    }

    private static func light(_ spec: YardNightLamp) -> PointLight {
        let l = PointLight()
        l.name = spec.name
        l.light.color = PetRoom.color(spec.hex)
        l.light.intensity = spec.lumens
        l.light.attenuationRadius = spec.radius
        l.position = spec.at
        return l
    }
}
