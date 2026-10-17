// Комната стиля A «Nintendogs»: клетчатый пол, две стены с плинтусом, круглый ковёр, миска и мяч.
// Свет: тёплый ключевой с тенью, холодный заполняющий, контровой сзади. Камера 3/4 чуть сверху.
// Пятно-тень под собакой заземляет её, даже если тень от света слабая. Всё матовое, без бликов.
// Размеры в метрах; питомец ростом PetModel.height (0.42) стоит в начале координат, мордой к +z.
// Кадр — экран iPhone во весь рост (узкий, ~0.46), поэтому миска и мяч стоят близко к собаке,
// а левая стена (x = leftWallX) в кадр не попадает: у края кадра видна только задняя.
// Числа вынесены в static let, чтобы править по скриншоту ui-home.

import UIKit
@preconcurrency import RealityKit

@MainActor
enum PetRoom {
    // MARK: Камера

    /// Вертикальный угол обзора, градусы.
    static let cameraFov: Float = 32
    // Наклон ~14°. В портрете кадр упирается в ширину: Шиба в 3/4 (0.58 × 0.17 м) занимает ~0.45 м по ширине,
    // поэтому камера на ~2.45 м: собака ~37% высоты и ±70% ширины кадра. Ближе — морда уходит за левый край.
    static let cameraEye = SIMD3<Float>(0.06, 0.78, 2.4)
    static let cameraTarget = SIMD3<Float>(-0.02, 0.2, 0)

    /// Поворот обёртки питомца по Y для вида 3/4: морда влево к камере, к камере повёрнут левый бок собаки.
    nonisolated static let yaw3q: Float = -0.55

    // MARK: Комната

    static let floorSize: Float = 5
    /// Клеток на всю сторону пола (клетка 0.5 м).
    static let floorCells = 10
    static let wallHeight: Float = 2.2
    static let backWallZ: Float = -1.4
    static let leftWallX: Float = -1.8
    static let rugRadius: Float = 0.45
    /// Миска слева сзади, у морды (за собакой справа её закрывает круп). Мяч справа впереди, у лап.
    nonisolated static let bowlPos = SIMD3<Float>(-0.38, 0.025, -0.75)
    nonisolated static let ballPos = SIMD3<Float>(0.15, 0.05, 0.3)
    /// Пятно-тень чуть выше ковра (верх ковра — 0.004).
    nonisolated static let blobY: Float = 0.006
    /// Ширина (x) и длина (z, вдоль морды) пятна; край градиента прозрачный, поэтому длиннее собаки.
    static let blobWidth: Float = 0.34
    static let blobDepth: Float = 0.7

    // MARK: Свет

    struct LightSpec {
        var name: String
        var color: UInt32
        var intensity: Float
        var from: SIMD3<Float>
        var shadow: Bool
    }

    static let keyLight = LightSpec(name: "key", color: 0xfff3e2, intensity: 2200, from: SIMD3<Float>(0.9, 1.8, 1.2), shadow: true)
    static let fillLight = LightSpec(name: "fill", color: 0xc9d6e6, intensity: 700, from: SIMD3<Float>(-1.2, 0.9, 0.8), shadow: false)
    static let rimLight = LightSpec(name: "rim", color: 0xffe2c4, intensity: 900, from: SIMD3<Float>(0, 1.2, -1.5), shadow: false)

    // MARK: Сборка

    static func room() -> Entity {
        let root = Entity()
        root.name = "room"

        // Пол: клетка нарисована прямо в текстуре, UV у плоскости 0…1 на весь пол.
        var floorMat = matteMaterial(RoomColors.checkerLight)
        if let cg = checkerImage(size: 320, cells: floorCells),
           let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {
            floorMat.baseColor = .init(tint: .white, texture: MaterialParameters.Texture(tex))
        }
        let floor = ModelEntity(mesh: .generatePlane(width: floorSize, depth: floorSize), materials: [floorMat])
        floor.name = "floor"
        noShadow(floor)
        root.addChild(floor)

        // Задняя стена смотрит на камеру (+z), левая повёрнута лицом к +x.
        let back = ModelEntity(mesh: .generatePlane(width: floorSize, height: wallHeight),
                               materials: [matteMaterial(RoomColors.wall)])
        back.name = "wallBack"
        back.position = SIMD3<Float>(0, wallHeight / 2, backWallZ)
        noShadow(back)
        root.addChild(back)

        let left = ModelEntity(mesh: .generatePlane(width: floorSize, height: wallHeight),
                               materials: [matteMaterial(RoomColors.wall, shade: 0.96)])
        left.name = "wallLeft"
        left.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        left.position = SIMD3<Float>(leftWallX, wallHeight / 2, backWallZ + floorSize / 2)
        noShadow(left)
        root.addChild(left)

        // Плинтусы
        let plinthMat = matteMaterial(RoomColors.plinth)
        let plinthBack = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(floorSize, 0.06, 0.02)), materials: [plinthMat])
        plinthBack.position = SIMD3<Float>(0, 0.03, backWallZ + 0.01)
        root.addChild(plinthBack)
        let plinthLeft = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.02, 0.06, floorSize)), materials: [plinthMat])
        plinthLeft.position = SIMD3<Float>(leftWallX + 0.01, 0.03, backWallZ + floorSize / 2)
        root.addChild(plinthLeft)

        // Круглый ковёр под собакой
        let rug = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: rugRadius),
                              materials: [matteMaterial(RoomColors.rug)])
        rug.name = "rug"
        rug.position = SIMD3<Float>(0, 0.002, 0)
        noShadow(rug)
        root.addChild(rug)

        // Миска и мяч
        let bowl = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 0.09),
                               materials: [matteMaterial(RoomColors.bowl)])
        bowl.name = "bowl"
        bowl.position = bowlPos
        // Горка корма: видна, только пока миска стоит под мордой (PetChoreo).
        let food = ModelEntity(mesh: .generateSphere(radius: 0.07), materials: [matteMaterial(RoomColors.food)])
        food.name = "food"
        food.position = SIMD3<Float>(0, 0.025, 0)
        food.scale = SIMD3<Float>(1, 0.45, 1)
        food.isEnabled = false
        bowl.addChild(food)
        root.addChild(bowl)

        let ball = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [matteMaterial(RoomColors.ball)])
        ball.name = "ball"
        ball.position = ballPos
        root.addChild(ball)

        return root
    }

    static func lights() -> Entity {
        let root = Entity()
        root.name = "lights"
        for spec in [keyLight, fillLight, rimLight] {
            let l = DirectionalLight()
            l.name = spec.name
            l.light.color = uiColor(spec.color)
            l.light.intensity = spec.intensity
            if spec.shadow {
                l.shadow = DirectionalLightComponent.Shadow(maximumDistance: 4, depthBias: 2)
            }
            l.look(at: .zero, from: spec.from, relativeTo: nil)
            root.addChild(l)
        }
        return root
    }

    static func camera() -> Entity {
        let cam = PerspectiveCamera()
        cam.name = "camera"
        cam.camera.fieldOfViewInDegrees = cameraFov
        cam.look(at: cameraTarget, from: cameraEye, relativeTo: nil)
        return cam
    }

    /// Мягкое пятно под собакой. Длинная сторона — вдоль морды (+z), поэтому кладётся рядом с питомцем
    /// в обёртку с поворотом yaw3q, но не в обёртку с дыханием (иначе пятно будет качаться).
    static func blobShadow() -> ModelEntity {
        var mat = UnlitMaterial()
        if let cg = blobImage(size: 128), let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {
            mat.color = .init(tint: .white, texture: MaterialParameters.Texture(tex))
        } else {
            mat.color = .init(tint: UIColor(white: 0, alpha: 0.25), texture: nil)
        }
        mat.blending = .transparent(opacity: .init(floatLiteral: 1))
        let e = ModelEntity(mesh: .generatePlane(width: blobWidth, depth: blobDepth), materials: [mat])
        e.name = "blobShadow"
        e.position = SIMD3<Float>(0, blobY, 0)
        noShadow(e)
        return e
    }

    /// Матовость: у всех PBR-материалов шероховатость 1, без металла и бликов. Clearcoat не трогаем.
    static func matte(_ root: Entity) {
        if var model = root.components[ModelComponent.self] {
            model.materials = model.materials.map { (m: any Material) -> any Material in
                guard var pbr = m as? PhysicallyBasedMaterial else { return m }
                pbr.roughness = .init(floatLiteral: 1)
                pbr.metallic = .init(floatLiteral: 0)
                pbr.specular = .init(floatLiteral: 0)
                return pbr
            }
            root.components.set(model)
        }
        for child in root.children {
            matte(child)
        }
    }

    // MARK: Текстуры (чистые функции, без RealityKit)

    /// Шахматка cells×cells двух цветов пола, size×size пикселей. nil — если не создался контекст.
    nonisolated static func checkerImage(size: Int, cells: Int) -> CGImage? {
        guard size > 0, cells > 0, let ctx = bitmap(size) else { return nil }
        let a = cgColor(RoomColors.checkerBlue), b = cgColor(RoomColors.checkerLight)
        for row in 0..<cells {
            for col in 0..<cells {
                // Границы клеток округляем до пикселя, чтобы не было швов при size не кратном cells.
                let x0 = (col * size) / cells, x1 = ((col + 1) * size) / cells
                let y0 = (row * size) / cells, y1 = ((row + 1) * size) / cells
                ctx.setFillColor((row + col) % 2 == 0 ? a : b)
                ctx.fill(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
            }
        }
        return ctx.makeImage()
    }

    /// Радиальный градиент чёрного: альфа 0.35 в центре → 0 к краю.
    nonisolated static func blobImage(size: Int) -> CGImage? {
        guard size > 0, let ctx = bitmap(size) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let colors = [CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35),
                      CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)] as CFArray
        let locations: [CGFloat] = [0, 1]
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) else { return nil }
        let c = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2,
                               options: [])
        return ctx.makeImage()
    }

    // MARK: Помощники

    private nonisolated static func bitmap(_ size: Int) -> CGContext? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private nonisolated static func cgColor(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    /// shade < 1 — темнее на (1 − shade).
    private static func uiColor(_ hex: UInt32, shade: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xff) / 255 * shade, green: CGFloat((hex >> 8) & 0xff) / 255 * shade,
                blue: CGFloat(hex & 0xff) / 255 * shade, alpha: 1)
    }

    private static func matteMaterial(_ hex: UInt32, shade: CGFloat = 1) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: uiColor(hex, shade: shade), texture: nil)
        m.roughness = .init(floatLiteral: 1)
        m.metallic = .init(floatLiteral: 0)
        m.specular = .init(floatLiteral: 0)
        return m
    }

    /// Пол, стены, ковёр и пятно сами тень не бросают (компонент действует только на свою сущность).
    private static func noShadow(_ e: Entity) {
        e.components.set(DynamicLightShadowComponent(castsShadow: false))
    }
}

/// Цвета комнаты. Без актора, чтобы чистые функции текстур читали их откуда угодно.
enum RoomColors {
    static let checkerBlue: UInt32 = 0xbcd3ee
    static let checkerLight: UInt32 = 0xf4f1ea
    static let wall: UInt32 = 0xfbefe4
    static let plinth: UInt32 = 0xe3cdb8
    static let rug: UInt32 = 0xe9b8a8
    static let bowl: UInt32 = 0xd9534f
    static let ball: UInt32 = 0xf2c94c
    static let food: UInt32 = 0x9c5b34
}
