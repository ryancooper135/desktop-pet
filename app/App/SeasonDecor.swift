// Волна 40 F: сезонный акцент — бесплатный и сам по себе. Зима — снеговик, весна — тюльпаны, лето — подсолнух,
// осень — тыква с листьями. Одна модель на двор (подоконник яруса 0, его видно со всех ярусов) и на комнату
// (левый край подоконника окна во двор, без окна — своя полочка там же, в масштабе комнаты).
// Только матовое: ночью акцент тонирует свет двора (YardLight) или комнаты (RoomLighting), как всё остальное.
// Несколько десятков треугольников — под бюджет станции (YardArt.stationBudget) с большим запасом.

import RealityKit

enum SeasonDecor {
    /// Цвета акцентов.
    enum Colors {
        static let snow: UInt32 = 0xf2f4f7
        static let coal: UInt32 = 0x2f3236
        static let carrot: UInt32 = 0xf08a2a
        static let scarf: UInt32 = 0xd9483f
        static let pot: UInt32 = 0xc0643a
        static let stem: UInt32 = 0x5e9e46
        static let tulipRed: UInt32 = 0xe2554b
        static let tulipPink: UInt32 = 0xf2b8c6
        static let tulipYellow: UInt32 = 0xf2cf3a
        static let petal: UInt32 = 0xf5c542
        static let seeds: UInt32 = 0x6b4428
        static let pumpkin: UInt32 = 0xf08a2a
        static let pumpkinSmall: UInt32 = 0xe9a03a
        static let pumpkinStem: UInt32 = 0x6b4428
        static let leafRed: UInt32 = 0x9c3b2a
        static let leafOrange: UInt32 = 0xd9772e
        static let leafYellow: UInt32 = 0xf2b01e
    }

    /// Имя узла акцента в сцене двора и группы в комнате.
    static let yardName = "season.yard"
    static let roomName = "decor.season"

    /// Где акцент стоит на подоконнике двора (верх доски y 0.50): правее сушилки, пёс отдыхает левее.
    static let yardAt = SIMD3<Float>(0.36, 0.5, -1.56)
    /// Масштаб в комнате: двор крупнее раза в три.
    static let roomScale: Float = 0.32

    /// Модель акцента сезона: основание на y = 0, высота около 0.2, след не шире 0.16.
    static func model(_ season: Season) -> YardArtModel {
        var m = YardArtModel(name: "season.\(season.rawValue)")
        switch season {
        case .winter: snowman(&m)
        case .spring: tulips(&m)
        case .summer: sunflower(&m)
        case .autumn: pumpkin(&m)
        }
        return m
    }

    // MARK: модели

    /// Снеговик: три кома, угольки, морковка, шарф и ведро-шапка.
    private static func snowman(_ m: inout YardArtModel) {
        typealias C = Colors
        m.gem(C.snow, sides: 8, r: 0.065, h: 0.11, at: SIMD3(0, 0.055, 0), scale: SIMD3(1, 1, 1))
        m.gem(C.snow, sides: 8, r: 0.048, h: 0.085, at: SIMD3(0, 0.125, 0))
        m.gem(C.snow, sides: 6, r: 0.034, h: 0.065, at: SIMD3(0, 0.185, 0))
        m.box(C.scarf, SIMD3(0.07, 0.014, 0.07), at: SIMD3(0, 0.158, 0), rot: SIMD3(0, 22, 0))
        m.box(C.scarf, SIMD3(0.016, 0.04, 0.008), at: SIMD3(0.02, 0.14, 0.03), rot: SIMD3(0, 0, -10))
        m.prism(C.carrot, sides: 4, r: 0.007, h: 0.035, top: 0, at: SIMD3(0, 0.188, 0.045), rot: SIMD3(90, 0, 0),
                bottom: false)
        for dx: Float in [-0.012, 0.012] {
            m.panel(C.coal, SIMD2(0.008, 0.008), at: SIMD3(dx, 0.198, 0.031))
        }
        m.prism(C.coal, sides: 6, r: 0.022, h: 0.03, top: 0.018, at: SIMD3(0, 0.226, 0), rot: SIMD3(0, 0, -8))
    }

    /// Три тюльпана в горшке: стебли, бутоны и два листа.
    private static func tulips(_ m: inout YardArtModel) {
        typealias C = Colors
        m.prism(C.pot, sides: 6, r: 0.045, h: 0.06, top: 0.055, at: SIMD3(0, 0.03, 0))
        let heads: [(x: Float, z: Float, h: Float, c: UInt32)] = [
            (-0.022, 0.006, 0.15, C.tulipRed), (0.004, -0.012, 0.18, C.tulipPink), (0.026, 0.01, 0.14, C.tulipYellow),
        ]
        for t in heads {
            m.box(C.stem, SIMD3(0.006, t.h - 0.06, 0.006), at: SIMD3(t.x, 0.06 + (t.h - 0.06) / 2, t.z))
            m.prism(t.c, sides: 5, r: 0.012, h: 0.03, top: 0.018, at: SIMD3(t.x, t.h + 0.01, t.z), bottom: true)
        }
        m.box(C.stem, SIMD3(0.012, 0.06, 0.004), at: SIMD3(-0.03, 0.09, 0.02), rot: SIMD3(0, 20, 18))
        m.box(C.stem, SIMD3(0.012, 0.055, 0.004), at: SIMD3(0.034, 0.088, -0.01), rot: SIMD3(0, -25, -20))
    }

    /// Подсолнух в горшке: стебель, два листа, лепестки и серединка лицом к камере.
    private static func sunflower(_ m: inout YardArtModel) {
        typealias C = Colors
        m.prism(C.pot, sides: 6, r: 0.04, h: 0.055, top: 0.05, at: SIMD3(0, 0.0275, 0))
        m.box(C.stem, SIMD3(0.008, 0.13, 0.008), at: SIMD3(0, 0.12, 0))
        m.box(C.stem, SIMD3(0.04, 0.004, 0.018), at: SIMD3(-0.02, 0.1, 0.004), rot: SIMD3(0, 0, 25))
        m.box(C.stem, SIMD3(0.036, 0.004, 0.016), at: SIMD3(0.02, 0.13, 0.004), rot: SIMD3(0, 0, -25))
        m.gem(C.petal, sides: 12, r: 0.055, h: 0.012, at: SIMD3(0, 0.195, 0.006), rot: SIMD3(80, 0, 0))
        m.gem(C.seeds, sides: 8, r: 0.026, h: 0.018, at: SIMD3(0, 0.196, 0.012), rot: SIMD3(80, 0, 0))
    }

    /// Тыква с хвостиком, тыковка поменьше и три кленовых листа на земле.
    private static func pumpkin(_ m: inout YardArtModel) {
        typealias C = Colors
        m.gem(C.pumpkin, sides: 10, r: 0.07, h: 0.11, at: SIMD3(-0.01, 0.05, 0), scale: SIMD3(1, 1, 0.9))
        m.prism(C.pumpkinStem, sides: 5, r: 0.008, h: 0.03, top: 0.005, at: SIMD3(-0.008, 0.11, 0), rot: SIMD3(0, 0, -12))
        m.gem(C.pumpkinSmall, sides: 8, r: 0.036, h: 0.055, at: SIMD3(0.07, 0.026, 0.03))
        m.prism(C.pumpkinStem, sides: 4, r: 0.005, h: 0.018, top: 0.003, at: SIMD3(0.07, 0.058, 0.03))
        let leaves: [(x: Float, z: Float, a: Float, c: UInt32)] = [
            (-0.075, 0.035, 20, C.leafRed), (0.03, 0.045, -35, C.leafOrange), (-0.03, 0.048, 70, C.leafYellow),
        ]
        for l in leaves {
            // Лист — плоская пятиконечная «звезда»: двойная пирамида с низкой высотой.
            m.gem(l.c, sides: 5, r: 0.026, h: 0.004, at: SIMD3(l.x, 0.003, l.z), rot: SIMD3(0, l.a, 0))
        }
    }

    // MARK: двор

    /// Акцент на подоконнике двора. Ставить до YardLight.apply: ночной тинт касается и его.
    @MainActor
    static func yard(_ season: Season) -> Entity {
        // Обёртка с постоянным именем, внутри — модель «season.<сезон>» (видно, какой сезон стоит).
        let e = Entity()
        e.name = yardName
        e.position = yardAt
        e.addChild(YardArtStage.entity(model(season)))
        return e
    }

    // MARK: комната

    /// Где в комнате: левый край подоконника окна во двор (верх доски y 0.213), без окна — там же своя полочка.
    static func roomSpot() -> SIMD3<Float> {
        let w = RoomPlan.window
        return SIMD3(w.minX + 0.045, w.minY + 0.003, RoomPlan.backWallZ + 0.026)
    }
}

/// Какой сезон уже стоит в комнате (и с окном ли): тот же — ничего не перестраиваем.
struct RoomSeasonShown: Component, Equatable {
    var season: Season
    var window: Bool
}

@MainActor
extension RoomDecor {
    private static var seasonRegistered = false

    /// Сезонный акцент (волна 40 F) в комнату. Тот же сезон и окно — ничего не делает.
    /// true — перестроили: новым деталям нужен свет комнаты.
    @discardableResult
    static func applySeason(_ season: Season, window: Bool, to room: Entity) -> Bool {
        if !seasonRegistered {
            RoomSeasonShown.registerComponent()
            seasonRegistered = true
        }
        let shown = RoomSeasonShown(season: season, window: window)
        let old = room.children.first(where: { $0.name == SeasonDecor.roomName })
        if old?.components[RoomSeasonShown.self] == shown { return false }
        old?.removeFromParent()
        let g = seasonCorner(season, window: window)
        g.components.set(shown)
        room.addChild(g)
        return true
    }

    /// Группа акцента: модель в масштабе комнаты, без окна — под ней полочка на двух кронштейнах.
    static func seasonCorner(_ season: Season, window: Bool) -> Entity {
        let g = Entity()
        g.name = SeasonDecor.roomName
        let at = SeasonDecor.roomSpot()
        if !window {
            let wood = PetRoom.matteMaterial(DecorColors.wood)
            let board = ModelEntity(mesh: .generateBox(size: [0.085, 0.01, 0.05]), materials: [wood])
            board.position = [at.x, at.y - 0.005, at.z]
            g.addChild(board)
            for dx: Float in [-0.03, 0.03] {
                let arm = ModelEntity(mesh: .generateBox(size: [0.006, 0.022, 0.03]), materials: [wood])
                arm.position = [at.x + dx, at.y - 0.021, RoomPlan.backWallZ + 0.016]
                g.addChild(arm)
            }
        }
        let accent = YardArtStage.entity(SeasonDecor.model(season))
        accent.position = at
        accent.scale = SIMD3(repeating: SeasonDecor.roomScale)
        g.addChild(accent)
        return g
    }
}

// MARK: - сезонные вещи на полке

@MainActor
extension RoomDecor {
    private enum SeasonShelfColors {
        static let wood: UInt32 = 0x7a5a3a
        static let glass: UInt32 = 0xbfe3f2
        static let fir: UInt32 = 0x4e8a5a
        static let snow: UInt32 = 0xf2f4f7
        static let bucket: UInt32 = 0x3fa7d6
        static let rim: UInt32 = 0x2e86b0
        static let sand: UInt32 = 0xe9cf94
        static let shell: UInt32 = 0xf6c7b6
        static let basket: UInt32 = 0xb07a3e
        static let capRed: UInt32 = 0xc8323c
        static let capBrown: UInt32 = 0x8a5a2e
        static let stalk: UInt32 = 0xf4ecd8
    }

    @discardableResult
    private static func seasonPart(_ mesh: MeshResource, _ hex: UInt32, _ pos: SIMD3<Float>, in parent: Entity,
                                   scale: SIMD3<Float> = .one) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [PetRoom.matteMaterial(hex)])
        e.position = pos
        e.scale = scale
        parent.addChild(e)
        return e
    }

    /// Сезонная вещь на полке: sx — середина, y — верх доски, z — глубина. false — id не наш.
    static func seasonShelf(_ id: String, sx: Float, y: Float, z: Float, in g: Entity) -> Bool {
        typealias C = SeasonShelfColors
        typealias D = SeasonDecor.Colors
        switch id {
        case "season_snow_globe":
            // Снежный шар: подставка, стеклянный шар, ёлочка и снег на дне.
            seasonPart(.generateCylinder(height: 0.012, radius: 0.018), C.wood, [sx, y + 0.006, z], in: g)
            seasonPart(.generateSphere(radius: 0.022), C.glass, [sx, y + 0.032, z], in: g)
            seasonPart(.generateCone(height: 0.026, radius: 0.01), C.fir, [sx, y + 0.034, z + 0.012], in: g)
            seasonPart(.generateCylinder(height: 0.004, radius: 0.016), C.snow, [sx, y + 0.016, z], in: g)
        case "season_tulip_pot":
            // Горшок и два тюльпана на стеблях.
            seasonPart(.generateCylinder(height: 0.022, radius: 0.014), D.pot, [sx, y + 0.011, z], in: g)
            for (dx, h, c) in [(-0.006, 0.028, D.tulipRed), (0.007, 0.022, D.tulipPink)] as [(Float, Float, UInt32)] {
                seasonPart(.generateBox(size: [0.003, h, 0.003]), D.stem, [sx + dx, y + 0.022 + h / 2, z], in: g)
                seasonPart(.generateSphere(radius: 0.007), c, [sx + dx, y + 0.024 + h, z], in: g, scale: [1, 1.3, 1])
            }
        case "season_sand_bucket":
            // Ведёрко: синее, с ободком, песок горкой и ракушка спереди.
            seasonPart(.generateCylinder(height: 0.03, radius: 0.017), C.bucket, [sx, y + 0.015, z], in: g)
            seasonPart(.generateCylinder(height: 0.004, radius: 0.019), C.rim, [sx, y + 0.03, z], in: g)
            seasonPart(.generateSphere(radius: 0.015), C.sand, [sx, y + 0.032, z], in: g, scale: [1, 0.5, 1])
            seasonPart(.generateSphere(radius: 0.006), C.shell, [sx + 0.02, y + 0.004, z + 0.01], in: g,
                       scale: [1, 0.5, 1])
        case "season_mushroom_basket":
            // Корзинка с двумя грибами: красный и бурый.
            seasonPart(.generateBox(size: [0.05, 0.018, 0.03]), C.basket, [sx, y + 0.009, z], in: g)
            for (dx, c) in [(-0.01, C.capRed), (0.012, C.capBrown)] as [(Float, UInt32)] {
                seasonPart(.generateCylinder(height: 0.012, radius: 0.003), C.stalk, [sx + dx, y + 0.022, z], in: g)
                seasonPart(.generateSphere(radius: 0.009), c, [sx + dx, y + 0.029, z], in: g, scale: [1, 0.6, 1])
            }
        default:
            return false
        }
        return true
    }
}
