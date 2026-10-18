// Дом в комнате (ROADMAP, этап 8): вещи шести линий дома из примитивов RealityKit, стиль A — плоские матовые
// цвета, без ассетов. Где что стоит и почему — RoomPlan (app/Shared), там же тесты на зазоры с собакой,
// миской, мячом и путями прогулки и игры. Здесь только сборка по этим местам.
// Вещи — ребёнок «roomDecor» комнаты; перестраиваются целиком при смене уровней (покупка), не каждый кадр.
// Уровень 0 любой линии — ничего нового: комната как была. Имена bowl/food/ball/room не занимаем —
// по ним PetChoreo ищет миску и мяч.

import UIKit
@preconcurrency import RealityKit

/// Какие уровни сейчас стоят в комнате.
struct RoomDecorShown: Component {
    var levels: RoomPlan.Levels
}

@MainActor
enum RoomDecor {
    static let roomName = "room"
    static let rootName = "roomDecor"
    private static var registered = false

    /// Поставить вещи по уровням. Те же уровни — ничего не делает (зовётся из update на каждый пересчёт вью).
    static func apply(_ levels: RoomPlan.Levels, to room: Entity) {
        if !registered {
            RoomDecorShown.registerComponent()
            registered = true
        }
        let old = room.children.first(where: { $0.name == rootName })
        if old?.components[RoomDecorShown.self]?.levels == levels { return }
        old?.removeFromParent()
        if levels == RoomPlan.Levels() { return }
        let root = build(levels)
        root.components.set(RoomDecorShown(levels: levels))
        room.addChild(root)
    }

    static func build(_ l: RoomPlan.Levels) -> Entity {
        let root = Entity()
        root.name = rootName
        if l.kitchen > 0 { root.addChild(kitchen(l.kitchen)) }
        if l.bath > 0 { root.addChild(bath(l.bath)) }
        if l.window { root.addChild(window(yard: l.yard, kennel: l.kennel)) }
        if l.bed > 0 { root.addChild(bed(l.bed)) }
        if l.play > 0 { root.addChild(play(l.play)) }
        return root
    }

    // MARK: детали

    /// Матовая деталь в parent. flat — плоская накладка (окно, лежанка): тень не отбрасывает.
    @discardableResult
    private static func part(_ mesh: MeshResource, _ hex: UInt32, _ pos: SIMD3<Float>, in parent: Entity,
                             scale: SIMD3<Float> = .one, shade: CGFloat = 1, flat: Bool = false) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [PetRoom.matteMaterial(hex, shade: shade)])
        e.position = pos
        e.scale = scale
        if flat { PetRoom.noShadow(e) }
        parent.addChild(e)
        return e
    }

    private static func box(_ x: Float, _ y: Float, _ z: Float) -> MeshResource {
        .generateBox(size: SIMD3<Float>(x, y, z))
    }

    private static func cyl(_ h: Float, _ r: Float) -> MeshResource { .generateCylinder(height: h, radius: r) }
    private static func ball(_ r: Float) -> MeshResource { .generateSphere(radius: r) }

    private static func turn(_ angle: Float, _ axis: SIMD3<Float>) -> simd_quatf { simd_quatf(angle: angle, axis: axis) }
    private static let axisX = SIMD3<Float>(1, 0, 0)
    private static let axisY = SIMD3<Float>(0, 1, 0)
    private static let axisZ = SIMD3<Float>(0, 0, 1)

    private static func group(_ name: String, in parent: Entity? = nil) -> Entity {
        let e = Entity()
        e.name = name
        parent?.addChild(e)
        return e
    }

    // MARK: кухня — задний левый угол

    /// 1 — холодильник, 2 — + бункер автокормушки с трубкой к лотку, 3 — + полка шефа с кастрюлей и банками.
    static func kitchen(_ level: Int) -> Entity {
        let g = group("decor.kitchen")
        let r = RoomPlan.kitchen
        let C = DecorColors.self
        // Холодильник у стены, справа от него место под лоток кормушки.
        let w: Float = 0.16, d: Float = 0.15, h: Float = 0.32
        let cx = r.minX + w / 2, cz = r.minZ + d / 2
        let front = r.minZ + d
        part(box(w, h, d), C.fridge, [cx, h / 2, cz], in: g)
        // Шов морозилки и ручки справа.
        part(box(w, 0.004, 0.002), C.fridgeSeam, [cx, h * 0.66, front + 0.001], in: g)
        for (y, hh) in [(h * 0.80, Float(0.05)), (h * 0.42, Float(0.08))] {
            part(box(0.008, hh, 0.012), C.steel, [cx + w / 2 - 0.018, y, front + 0.006], in: g)
        }
        // Магнитик — чтобы было видно, что это кухня, а не шкаф.
        part(cyl(0.004, 0.012), C.magnet, [cx - 0.03, h * 0.5, front + 0.002], in: g).orientation = turn(.pi / 2, axisX)
        if level >= 2 {
            // Бункер на холодильнике: прозрачный низ не сделать матовым — корм видно сверху.
            let top = h
            part(cyl(0.06, 0.042), C.hopper, [cx - 0.03, top + 0.03, cz], in: g)
            part(cyl(0.004, 0.036), DecorColors.kibble, [cx - 0.03, top + 0.061, cz], in: g)
            part(cyl(0.016, 0.045), C.steel, [cx - 0.03, top + 0.008, cz], in: g, shade: 0.9)
            // Трубка вправо и вниз к лотку на полу.
            let tx = r.maxX - 0.02
            part(box(tx - (cx + 0.01), 0.012, 0.012), C.steel, [(cx + 0.01 + tx) / 2, top + 0.02, front - 0.02], in: g)
            part(cyl(top + 0.01, 0.006), C.steel, [tx, (top + 0.02) / 2 + 0.01, front - 0.02], in: g)
            part(cyl(0.014, 0.02), C.tray, [tx, 0.007, front - 0.02], in: g)
            part(ball(0.014), DecorColors.kibble, [tx, 0.012, front - 0.02], in: g, scale: [1, 0.4, 1])
        }
        if level >= 3 {
            // Полка на стене над холодильником: кастрюля, ковшик, банки.
            let s = RoomPlan.kitchenShelf
            let sx = (s.minX + s.maxX) / 2, wallZ = RoomPlan.backWallZ
            part(box(s.width, 0.012, 0.06), C.wood, [sx, s.minY, wallZ + 0.03], in: g)
            for bx in [s.minX + 0.02, s.maxX - 0.02] {
                part(box(0.008, 0.03, 0.04), C.wood, [bx, s.minY - 0.02, wallZ + 0.02], in: g, shade: 0.85)
            }
            let base = s.minY + 0.006
            part(cyl(0.05, 0.034), C.copper, [s.minX + 0.05, base + 0.025, wallZ + 0.03], in: g)
            part(cyl(0.006, 0.036), C.copper, [s.minX + 0.05, base + 0.053, wallZ + 0.03], in: g, shade: 0.8)
            part(ball(0.006), C.steel, [s.minX + 0.05, base + 0.06, wallZ + 0.03], in: g)
            for (i, lid) in [C.jarLidRed, C.jarLidGreen].enumerated() {
                let jx = s.maxX - 0.07 + Float(i) * 0.032
                part(cyl(0.04, 0.013), C.jar, [jx, base + 0.02, wallZ + 0.03], in: g)
                part(cyl(0.008, 0.014), lid, [jx, base + 0.044, wallZ + 0.03], in: g)
            }
            // Колпак шефа на холодильнике — сразу ясно, чья кухня.
            part(cyl(0.03, 0.022), C.white, [cx + 0.05, h + 0.015, cz + 0.02], in: g)
            part(ball(0.03), C.white, [cx + 0.05, h + 0.04, cz + 0.02], in: g, scale: [1, 0.6, 1])
        }
        return g
    }

    // MARK: ванная — задний правый угол

    /// 1 — ванна на ножках, 2 — джакузи с пузырями, 3 — спа: уточка, свечи, полотенце на стене.
    static func bath(_ level: Int) -> Entity {
        let g = group("decor.bath")
        let r = RoomPlan.bath
        let C = DecorColors.self
        let c = r.center
        // Овал: цилиндр, сплюснутый по z.
        let oval = SIMD3<Float>(1.05, 1, 0.9)
        let feet: Float = 0.02, body: Float = 0.1
        for (fx, fz) in [(-0.07, -0.05), (0.07, -0.05), (-0.07, 0.05), (0.07, 0.05)] as [(Float, Float)] {
            part(ball(0.014), C.gold, [c.x + fx, 0.012, c.z + fz], in: g)
        }
        part(cyl(body, 0.1), C.tub, [c.x, feet + body / 2, c.z], in: g, scale: oval)
        part(cyl(0.012, 0.104), C.tubRim, [c.x, feet + body - 0.004, c.z], in: g, scale: oval)
        let top = feet + body + 0.002
        let water = level >= 2 ? C.jacuzzi : C.water
        part(cyl(0.004, 0.084), water, [c.x, top, c.z], in: g, scale: oval, flat: true)
        if level >= 2 {
            let bubbles: [(Float, Float, Float)] = [(-0.05, 0.02, 0.016), (-0.02, -0.03, 0.012), (0.03, 0.01, 0.018),
                                                    (0.06, -0.02, 0.011), (0.0, 0.04, 0.013), (-0.065, -0.015, 0.01)]
            for (bx, bz, br) in bubbles {
                part(ball(br), C.white, [c.x + bx, top + br * 0.4, c.z + bz], in: g)
            }
            // Пара пузырей поднимается.
            part(ball(0.008), C.white, [c.x + 0.01, top + 0.04, c.z + 0.01], in: g)
            part(ball(0.006), C.white, [c.x - 0.03, top + 0.065, c.z - 0.01], in: g)
        }
        if level >= 3 {
            // Уточка плывёт, клювом влево — к собаке.
            let dx = c.x - 0.035, dz = c.z + 0.035
            part(ball(0.022), C.duck, [dx, top + 0.012, dz], in: g, scale: [1.2, 0.8, 1])
            part(ball(0.014), C.duck, [dx - 0.014, top + 0.034, dz], in: g)
            part(.generateCone(height: 0.014, radius: 0.007), C.beak, [dx - 0.03, top + 0.032, dz], in: g)
                .orientation = turn(.pi / 2, axisZ)
            // Свечи на дальнем бортике.
            for (i, sx) in [Float(-0.05), -0.025, 0.05].enumerated() {
                let ch: Float = i == 1 ? 0.03 : 0.022
                part(cyl(ch, 0.008), C.candle, [c.x + sx, top + ch / 2, c.z - 0.07], in: g)
                part(ball(0.005), C.flame, [c.x + sx, top + ch + 0.005, c.z - 0.07], in: g, scale: [1, 1.5, 1])
            }
            // Полотенце на перекладине у стены.
            let t = RoomPlan.bathTowel
            let tx = (t.minX + t.maxX) / 2, wallZ = RoomPlan.backWallZ
            part(cyl(t.width + 0.01, 0.004), C.gold, [tx, t.maxY, wallZ + 0.012], in: g).orientation = turn(.pi / 2, axisZ)
            part(box(t.width - 0.012, t.height - 0.006, 0.006), C.towel, [tx, (t.minY + t.maxY) / 2 - 0.003, wallZ + 0.012],
                 in: g)
            part(box(t.width - 0.012, 0.012, 0.007), C.towelStripe, [tx, t.minY + 0.03, wallZ + 0.012], in: g)
        }
        return g
    }

    // MARK: окно — двор и будка

    /// Окно на задней стене: небо и травка всегда; двор 1 — кусты, 2 — + забор и клумба, 3 — + деревья.
    /// Будка в правой части окна: 1 — будка, 2 — тёплая (свет в окошке, плед), 3 — домик с трубой и дымом.
    /// Слои — тонкие плашки от стены к раме; рама глубже слоёв, поэтому вид «за окном».
    static func window(yard: Int, kennel: Int) -> Entity {
        let g = group("decor.window")
        let w = RoomPlan.window, f = RoomPlan.windowFrame
        let C = DecorColors.self
        let wallZ = RoomPlan.backWallZ
        let cx = (w.minX + w.maxX) / 2, cy = (w.minY + w.maxY) / 2
        let inX = (w.minX + f)...(w.maxX - f), inY = (w.minY + f)...(w.maxY - f)
        let inW = inX.upperBound - inX.lowerBound, inH = inY.upperBound - inY.lowerBound
        // Слой по глубине: 0 — небо у стены.
        func z(_ layer: Int) -> Float { wallZ + 0.002 + Float(layer) * 0.003 }
        func plate(_ wd: Float, _ ht: Float, _ hex: UInt32, _ x: Float, _ y: Float, _ layer: Int) {
            part(box(wd, ht, 0.002), hex, [x, y, z(layer)], in: g, flat: true)
        }
        // Плоский кружок лицом к камере (куст, крона, цветок, дым).
        func blob(_ r: Float, _ hex: UInt32, _ x: Float, _ y: Float, _ layer: Int, sx: Float = 1, sy: Float = 1) {
            part(cyl(0.002, r), hex, [x, y, z(layer)], in: g, scale: [sx, 1, sy], flat: true).orientation = turn(.pi / 2, axisX)
        }
        plate(inW, inH, C.sky, cx, cy, 0)
        // Облачко.
        blob(0.018, C.cloud, inX.lowerBound + 0.07, inY.upperBound - 0.035, 1, sx: 1.8)
        blob(0.014, C.cloud, inX.lowerBound + 0.095, inY.upperBound - 0.03, 1, sx: 1.4)
        let grassH: Float = 0.045
        let grassTop = inY.lowerBound + grassH
        if yard >= 3 {
            // Деревья за забором.
            for (tx, tr) in [(inX.lowerBound + 0.05, Float(0.04)), (inX.lowerBound + 0.15, Float(0.032))] {
                plate(0.012, 0.05, C.trunk, tx, grassTop + 0.02, 1)
                blob(tr, C.tree, tx, grassTop + 0.045 + tr * 0.6, 2, sy: 1.1)
            }
        }
        plate(inW, grassH, C.grass, cx, inY.lowerBound + grassH / 2, 3)
        if yard >= 2 {
            // Забор вдоль двора — левее будки.
            let fenceTo = RoomPlan.kennelSlot.minX - 0.005
            var px = inX.lowerBound + 0.012
            while px < fenceTo {
                plate(0.01, 0.04, C.fence, px, grassTop + 0.008, 4)
                px += 0.024
            }
            plate(fenceTo - inX.lowerBound, 0.007, C.fence, (inX.lowerBound + fenceTo) / 2, grassTop + 0.018, 5)
        }
        if yard >= 1 {
            blob(0.024, C.bush, inX.lowerBound + 0.03, grassTop - 0.004, 6, sx: 1.4, sy: 0.8)
            blob(0.02, C.bush, inX.lowerBound + 0.13, grassTop - 0.006, 6, sx: 1.4, sy: 0.8)
        }
        if yard >= 2 {
            // Клумба: цветы у травки.
            let flowers: [UInt32] = [C.flowerPink, C.flowerYellow, C.flowerPink, C.flowerWhite, C.flowerYellow]
            for (i, hex) in flowers.enumerated() {
                blob(0.007, hex, inX.lowerBound + 0.06 + Float(i) * 0.012, inY.lowerBound + 0.018 + Float(i % 2) * 0.008, 7)
            }
        }
        if yard >= 3 {
            for (i, hex) in [C.flowerYellow, C.flowerPink, C.flowerWhite].enumerated() {
                blob(0.006, hex, inX.lowerBound + 0.17 + Float(i) * 0.014, inY.lowerBound + 0.014 + Float(i % 2) * 0.007, 7)
            }
        }
        if kennel > 0 { kennelHouse(kennel, in: g, z: z(8), zStep: 0.003) }
        // Рама толще слоёв, подоконник выступает.
        let depth: Float = 0.035
        let fz = wallZ + depth / 2
        part(box(w.width, f, depth), C.frame, [cx, w.maxY - f / 2, fz], in: g)
        part(box(w.width, f, depth), C.frame, [cx, w.minY + f / 2, fz], in: g)
        part(box(f, w.height, depth), C.frame, [w.minX + f / 2, cy, fz], in: g)
        part(box(f, w.height, depth), C.frame, [w.maxX - f / 2, cy, fz], in: g)
        part(box(w.width + 0.04, 0.014, 0.05), C.frame, [cx, w.minY - 0.004, wallZ + 0.025], in: g, shade: 0.92)
        return g
    }

    /// Будка в kennelSlot; z — слой фасада, дальше вперёд шагами zStep.
    private static func kennelHouse(_ level: Int, in g: Entity, z: Float, zStep: Float) {
        let s = RoomPlan.kennelSlot
        let C = DecorColors.self
        let cx = (s.minX + s.maxX) / 2
        let wd: Float = level >= 3 ? 0.11 : 0.09
        let ht: Float = level >= 3 ? 0.07 : 0.06
        let base = s.minY + 0.012
        let bodyHex = level >= 3 ? C.cottage : C.kennel
        func plate(_ w: Float, _ h: Float, _ hex: UInt32, _ x: Float, _ y: Float, _ dz: Int, turnZ: Float = 0) {
            let e = part(box(w, h, 0.002), hex, [x, y, z + Float(dz) * zStep], in: g, flat: true)
            if turnZ != 0 { e.orientation = turn(turnZ, axisZ) }
        }
        func disk(_ r: Float, _ hex: UInt32, _ x: Float, _ y: Float, _ dz: Int, sx: Float = 1) {
            part(cyl(0.002, r), hex, [x, y, z + Float(dz) * zStep], in: g, scale: [sx, 1, 1], flat: true)
                .orientation = turn(.pi / 2, axisX)
        }
        // Труба — за крышей.
        if level >= 3 {
            plate(0.016, 0.04, C.chimney, cx + wd * 0.28, base + ht + 0.03, 0)
            for (i, r) in [Float(0.008), 0.011, 0.013].enumerated() {
                disk(r, C.smoke, cx + wd * 0.28 + Float(i) * 0.012, base + ht + 0.06 + Float(i) * 0.016, 0)
            }
        }
        plate(wd, ht, bodyHex, cx, base + ht / 2, 1)
        // Двускатная крыша: две доски под углом, сходятся над серединой.
        let roofLen = wd * 0.62, tilt: Float = 0.55
        let roofY = base + ht + sin(tilt) * roofLen / 2 - 0.004
        plate(roofLen, 0.014, C.roof, cx - cos(tilt) * roofLen / 2 + 0.004, roofY, 2, turnZ: tilt)
        plate(roofLen, 0.014, C.roof, cx + cos(tilt) * roofLen / 2 - 0.004, roofY, 2, turnZ: -tilt)
        // Лаз: прямоугольник с полукругом сверху. В домике с камином внутри огонь.
        let doorHex = level >= 3 ? C.fire : C.door
        let doorW: Float = 0.03, doorH: Float = 0.026
        plate(doorW, doorH, doorHex, cx, base + doorH / 2, 2)
        disk(doorW / 2, doorHex, cx, base + doorH, 2)
        if level >= 2 {
            // Тёплая: свет в окошке и плед у лаза.
            plate(0.014, 0.014, C.lamp, cx + wd * 0.3, base + ht * 0.6, 2)
            plate(0.012, 0.012, C.lamp, cx - wd * 0.3, base + ht * 0.6, 2)
            plate(doorW + 0.014, 0.008, C.plaid, cx, base + 0.004, 3)
        }
    }

    // MARK: лежанка — под собакой

    /// 1 — лежанка с кантом, 2 — + деревянный бортик и стёжка, 3 — королевская перина: фиолетовая, золото, кисти.
    /// Плоская (верх bedTop): Шиба стоит и спит на ней, ходить не мешает. Оси — как у подставки (yaw3q).
    static func bed(_ level: Int) -> Entity {
        let g = group("decor.bed")
        g.orientation = turn(PetRoom.yaw3q, axisY)
        let C = DecorColors.self
        let c = RoomPlan.bedCenterLocal
        let ax = RoomPlan.bedHalfX, az = RoomPlan.bedHalfZ
        let top = RoomPlan.bedTop
        let (pad, edge, rim): (UInt32, UInt32, UInt32) = switch level {
        case 1: (C.bedBlue, C.bedBlueEdge, C.wood)
        case 2: (C.bedPink, C.bedPinkEdge, C.wood)
        default: (C.bedRoyal, C.bedRoyalEdge, C.gold)
        }
        // Кант чуть шире и ниже матраса — тёмная обводка.
        part(cyl(top * 0.8, 1), edge, [c.x, top * 0.4, c.z], in: g, scale: [ax + 0.012, 1, az + 0.012], flat: true)
        part(cyl(top, 1), pad, [c.x, top / 2, c.z], in: g, scale: [ax, 1, az], flat: true)
        guard level >= 2 else { return g }
        // Стёжка: точки по кольцу внутри, середину всё равно закрывает собака.
        for k in 0..<12 {
            let a = Float(k) / 12 * 2 * .pi
            part(cyl(0.002, 0.006), edge, [c.x + cos(a) * ax * 0.7, top + 0.001, c.z + sin(a) * az * 0.7], in: g, flat: true)
        }
        // Бортик — кольцо коротких брусков по эллипсу.
        let n = 36
        let rx = ax + RoomPlan.bedRim / 2, rz = az + RoomPlan.bedRim / 2
        func at(_ i: Int) -> SIMD2<Float> {
            let a = Float(i) / Float(n) * 2 * .pi
            return [c.x + cos(a) * rx, c.z + sin(a) * rz]
        }
        for i in 0..<n {
            let p0 = at(i), p1 = at(i + 1)
            let d = p1 - p0
            let len = simd_length(d) + 0.004
            let mid = (p0 + p1) / 2
            part(box(len, RoomPlan.bedRimHeight, RoomPlan.bedRim), rim, [mid.x, RoomPlan.bedRimHeight / 2, mid.y], in: g)
                .orientation = turn(atan2(-d.y, d.x), axisY)
        }
        if level >= 3 {
            // Кисти по диагоналям.
            for k in 0..<4 {
                let a = Float.pi / 4 + Float(k) * .pi / 2
                part(ball(0.012), C.gold, [c.x + cos(a) * rx, RoomPlan.bedRimHeight + 0.006, c.z + sin(a) * rz], in: g)
            }
        }
        return g
    }

    // MARK: игровой угол — перед ковром

    /// 1 — корзина игрушек, 2 — + туннель, 3 — батут вместо туннеля и горка. Всё ниже playMaxHeight.
    static func play(_ level: Int) -> Entity {
        let g = group("decor.play")
        let C = DecorColors.self
        // Корзина справа: плетёная, игрушки торчат.
        let b = RoomPlan.playBasket.center
        part(cyl(0.042, 0.045), C.wicker, [b.x, 0.021, b.z], in: g)
        part(cyl(0.008, 0.048), C.wicker, [b.x, 0.04, b.z], in: g, shade: 0.8)
        part(ball(0.018), C.toyRed, [b.x - 0.016, 0.048, b.z - 0.006], in: g)
        part(ball(0.015), C.toyBlue, [b.x + 0.02, 0.046, b.z + 0.008], in: g)
        let bone = group("bone", in: g)
        bone.position = [b.x + 0.004, 0.056, b.z - 0.012]
        bone.orientation = turn(0.5, axisZ)
        part(box(0.036, 0.009, 0.009), C.bone, .zero, in: bone)
        for ex: Float in [-0.019, 0.019] {
            part(ball(0.007), C.bone, [ex, 0, 0], in: bone)
        }
        let m = RoomPlan.playCenter.center
        if level == 2 {
            // Туннель вдоль x: цилиндр наполовину в полу, полосатый, тёмные лазы по концам.
            let r: Float = 0.042, seg: Float = 0.045
            for (i, hex) in [C.tunnelBlue, C.tunnelYellow, C.tunnelBlue].enumerated() {
                part(cyl(seg, r), hex, [m.x + Float(i - 1) * seg, 0, m.z], in: g).orientation = turn(.pi / 2, axisZ)
            }
            for ex: Float in [-1.5, 1.5] {
                part(cyl(0.002, r - 0.006), C.hole, [m.x + ex * seg + (ex > 0 ? 0.001 : -0.001), 0, m.z], in: g, flat: true)
                    .orientation = turn(.pi / 2, axisZ)
            }
        }
        if level >= 3 {
            // Батут: ножки, синяя рама, тёмная сетка.
            for k in 0..<4 {
                let a = Float.pi / 4 + Float(k) * .pi / 2
                part(cyl(0.036, 0.004), C.trampFrame, [m.x + cos(a) * 0.05, 0.018, m.z + sin(a) * 0.05], in: g)
            }
            part(cyl(0.01, 0.064), C.trampFrame, [m.x, 0.04, m.z], in: g)
            part(cyl(0.012, 0.052), C.trampMat, [m.x, 0.041, m.z], in: g)
            part(ball(0.012), C.toyRed, [m.x + 0.012, 0.059, m.z - 0.01], in: g)
            // Горка слева: площадка-лесенка и скат к собаке.
            let s = RoomPlan.playSlide
            let sz = s.center.z
            let platW: Float = 0.03, platH: Float = 0.062
            let px = s.minX + platW / 2
            part(box(platW, platH, 0.055), C.slideStep, [px, platH / 2, sz], in: g)
            for k in 1...2 {
                part(box(platW + 0.004, 0.004, 0.058), C.slideStep, [px, Float(k) * platH / 3, sz], in: g, shade: 0.8)
            }
            let x0 = s.minX + platW, x1 = s.maxX
            let dx = x1 - x0, dy = platH - 0.004
            let ramp = group("slide", in: g)
            ramp.position = [(x0 + x1) / 2, platH / 2, sz]
            ramp.orientation = turn(-atan2(dy, dx), axisZ)
            let len = (dx * dx + dy * dy).squareRoot()
            part(box(len, 0.008, 0.045), C.slide, .zero, in: ramp)
            for ez: Float in [-0.025, 0.025] {
                part(box(len, 0.014, 0.005), C.slide, [0, 0.005, ez], in: ramp, shade: 0.82)
            }
        }
        return g
    }
}

/// Цвета вещей дома: пастель стиля A, рядом с RoomColors. Красный миски и жёлтый мяча не повторяем крупно.
enum DecorColors {
    // кухня
    static let fridge: UInt32 = 0xcfe6dc
    static let fridgeSeam: UInt32 = 0x9cbfb2
    static let steel: UInt32 = 0x9aa6ad
    static let magnet: UInt32 = 0xf2a65a
    static let hopper: UInt32 = 0xe8eef0
    static let kibble: UInt32 = 0x9c5b34
    static let tray: UInt32 = 0x7fa7c9
    static let wood: UInt32 = 0xc9a27e
    static let copper: UInt32 = 0xd08a5a
    static let jar: UInt32 = 0xf1ebe0
    static let jarLidRed: UInt32 = 0xe07a6a
    static let jarLidGreen: UInt32 = 0x7cbf6a
    static let white: UInt32 = 0xfdfbf7
    // ванная
    static let tub: UInt32 = 0xeef3f7
    static let tubRim: UInt32 = 0xd9e5ee
    static let gold: UInt32 = 0xe3c46a
    static let water: UInt32 = 0xa9d8f0
    static let jacuzzi: UInt32 = 0x72d0d2
    static let duck: UInt32 = 0xf6d34a
    static let beak: UInt32 = 0xf08a3c
    static let candle: UInt32 = 0xfff1d6
    static let flame: UInt32 = 0xffb347
    static let towel: UInt32 = 0xf2b5c4
    static let towelStripe: UInt32 = 0xe08aa0
    // окно и двор
    static let frame: UInt32 = 0xd9bfa3
    static let sky: UInt32 = 0xcfe9f7
    static let cloud: UInt32 = 0xffffff
    static let grass: UInt32 = 0xa6d48f
    static let bush: UInt32 = 0x77b864
    static let tree: UInt32 = 0x5fa860
    static let trunk: UInt32 = 0x9c6b45
    static let fence: UInt32 = 0xf6ead6
    static let flowerPink: UInt32 = 0xf28fb0
    static let flowerYellow: UInt32 = 0xf6d34a
    static let flowerWhite: UInt32 = 0xffffff
    // будка
    static let kennel: UInt32 = 0xd9a066
    static let cottage: UInt32 = 0xead0ae
    static let roof: UInt32 = 0xc8553d
    static let door: UInt32 = 0x5a3a28
    static let fire: UInt32 = 0xf0a04b
    static let lamp: UInt32 = 0xffd36b
    static let plaid: UInt32 = 0xd96a5a
    static let chimney: UInt32 = 0xa65a48
    static let smoke: UInt32 = 0xf2f2f2
    // лежанка
    static let bedBlue: UInt32 = 0xa9bfdc
    static let bedBlueEdge: UInt32 = 0x7f97bb
    static let bedPink: UInt32 = 0xf4cdd6
    static let bedPinkEdge: UInt32 = 0xd99aab
    static let bedRoyal: UInt32 = 0x9b7fd1
    static let bedRoyalEdge: UInt32 = 0x6f55a8
    // игры
    static let wicker: UInt32 = 0xd6a86a
    static let toyRed: UInt32 = 0xe86a6a
    static let toyBlue: UInt32 = 0x6aa5e8
    static let bone: UInt32 = 0xf6ead6
    static let tunnelBlue: UInt32 = 0x7fc4e8
    static let tunnelYellow: UInt32 = 0xf6d34a
    static let hole: UInt32 = 0x3d4b66
    static let trampFrame: UInt32 = 0x4a90d9
    static let trampMat: UInt32 = 0x3a3f4a
    static let slideStep: UInt32 = 0xf2a65a
    static let slide: UInt32 = 0x5bbf8a
}
