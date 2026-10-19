// Комната стиля A «Nintendogs»: клетчатый пол, две стены с плинтусом, круглый ковёр, миска и мяч.
// Свет: тёплый ключевой с тенью, холодный заполняющий, контровой сзади, вечером — лампа. Камера 3/4 чуть сверху.
// Вечер и ночь (цвет света, приглушённые стены, небо в окне) — RoomLighting по RoomLight (app/Shared).
// Пятно-тень под собакой заземляет её, даже если тень от света слабая. Всё матовое, без бликов.
// Размеры в метрах; питомец ростом PetModel.height (0.42) стоит в начале координат, мордой к +z.
// Кадр — экран iPhone во весь рост (узкий, ~0.46), поэтому миска и мяч стоят близко к собаке,
// а левая стена (x = leftWallX) в кадр не попадает: у края кадра видна только задняя.
// Числа вынесены в static let, чтобы править по скриншоту ui-home.

import UIKit
import Metal
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
    /// Крупный план шерсти (ui-71/72, PET_CAMERA=close): тот же наклон, но так, чтобы весь пёс от носа до хвоста
    /// влез по ширине портрета (нос ~-0.73, круп ~+0.74 в NDC) и не залезал под шапку и кнопки.
    /// Раньше (0.05, 0.7, 1.4) резало голову левым краем (волна 16).
    static let closeEye = SIMD3<Float>(0.03, 0.70, 1.67)
    static let closeTarget = SIMD3<Float>(-0.03, 0.22, 0)
    /// Морда крупно для снимков рта (ui-85, PET_CAMERA=face): камера чуть спереди-слева, смотрит на нос.
    static let faceEye = SIMD3<Float>(-0.04, 0.42, 1.2)
    static let faceTarget = SIMD3<Float>(-0.1, 0.3, 0.15)

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
    /// x = -0.30: при x = -0.38 левый край миски на портретном экране (~0.46) уходил за кадр;
    /// теперь до края ~35 pt. Проверка — PetRoomFramingTests.
    nonisolated static let bowlPos = SIMD3<Float>(-0.30, 0.025, -0.75)
    nonisolated static let bowlRadius: Float = 0.09
    nonisolated static let ballPos = SIMD3<Float>(0.15, 0.05, 0.3)
    /// Пятно-тень чуть выше ковра (верх ковра — 0.004) и матраса лежанки (RoomPlan.bedTop = 0.01, стёжка до 0.012):
    /// при 0.006 под лежанкой пятно пряталось. Вне лежанки 13 мм над полом не видно.
    nonisolated static let blobY: Float = 0.013
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
        let bowl = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: bowlRadius),
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
        // На крупном плане шерсти мяч оказался бы у правого края под полупрозрачными кнопками — там он не нужен.
        ball.isEnabled = !(Env.isUITest && Env.value("PET_CAMERA") == "close")
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
        // Тёплая лампа слева над ковром: днём выключена, вечером горит, ночью — ночник (RoomLighting).
        let lamp = PointLight()
        lamp.name = lampName
        lamp.light.color = uiColor(lampColor)
        lamp.light.intensity = 0
        lamp.light.attenuationRadius = 3
        lamp.position = lampPos
        lamp.isEnabled = false
        root.addChild(lamp)
        return root
    }

    static let lampName = "lamp"
    static let lampColor: UInt32 = 0xffc27a
    static let lampPos = SIMD3<Float>(-0.6, 0.9, 0.7)
    /// Полная яркость лампы, люмены: у собаки (~1.2 м) это около 700 лк — вдвое тише вечернего ключа.
    static let lampLumens: Float = 12_000

    static func camera() -> Entity {
        let cam = PerspectiveCamera()
        cam.name = "camera"
        cam.camera.fieldOfViewInDegrees = cameraFov
        // Только UI-тесты: PET_CAMERA=close/face — крупный план спины или морды (в приложении камеры не крутятся).
        let mode = Env.isUITest ? Env.value("PET_CAMERA") : nil
        let (target, eye) = mode == "close" ? (closeTarget, closeEye)
            : mode == "face" ? (faceTarget, faceEye) : (cameraTarget, cameraEye)
        cam.look(at: target, from: eye, relativeTo: nil)
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

    /// Имя пропа находки в обёртке питомца (PetChoreo ищет его по имени).
    static let propName = "findProp"

    /// Находка с прогулки — низкополигональная фигурка из примитивов, цвет из Finds. Начало — внизу (кладётся на пол),
    /// длинная сторона — поперёк морды, как палку несут в зубах. Незнакомый id — шарик цвета «находки».
    static func findProp(_ id: String) -> Entity {
        let root = Entity()
        root.name = propName
        let color = Finds.find(id)?.color ?? 0xC9B27A
        @discardableResult
        func part(_ mesh: MeshResource, _ pos: SIMD3<Float>, scale: SIMD3<Float> = .one, shade: CGFloat = 1) -> ModelEntity {
            let e = ModelEntity(mesh: mesh, materials: [matteMaterial(color, shade: shade)])
            e.position = pos
            e.scale = scale
            root.addChild(e)
            return e
        }
        switch id {
        case "stick":
            // Палка поперёк пасти: цилиндр по x и сучок.
            let r: Float = 0.012
            part(.generateCylinder(height: 0.16, radius: r), SIMD3<Float>(0, r, 0)).orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
            part(.generateCylinder(height: 0.04, radius: 0.007), SIMD3<Float>(0.04, r + 0.015, 0), shade: 0.85).orientation = simd_quatf(angle: -0.7, axis: SIMD3<Float>(0, 0, 1))
        case "cone":
            part(.generateSphere(radius: 0.035), SIMD3<Float>(0, 0.035, 0), scale: SIMD3<Float>(0.7, 1, 0.7))
            part(.generateBox(size: 0.012), SIMD3<Float>(0, 0.072, 0), shade: 0.8)
        case "ball":
            part(.generateSphere(radius: 0.035), SIMD3<Float>(0, 0.035, 0))
        case "sock":
            // Голенище и стопа уголком.
            part(.generateBox(size: SIMD3<Float>(0.11, 0.03, 0.035)), SIMD3<Float>(0, 0.015, 0))
            part(.generateBox(size: SIMD3<Float>(0.035, 0.03, 0.05)), SIMD3<Float>(0.0375, 0.015, 0.03), shade: 0.9)
            part(.generateBox(size: SIMD3<Float>(0.02, 0.031, 0.036)), SIMD3<Float>(-0.05, 0.015, 0), shade: 0.75)
        case "leaf":
            part(.generateBox(size: SIMD3<Float>(0.07, 0.004, 0.05)), SIMD3<Float>(0, 0.002, 0)).orientation = simd_quatf(angle: 0.6, axis: SIMD3<Float>(0, 1, 0))
            part(.generateBox(size: SIMD3<Float>(0.03, 0.004, 0.004)), SIMD3<Float>(0.045, 0.002, 0), shade: 0.7)
        case "pebble":
            part(.generateSphere(radius: 0.03), SIMD3<Float>(0, 0.021, 0), scale: SIMD3<Float>(1.2, 0.7, 1))
        default:
            part(.generateSphere(radius: 0.03), SIMD3<Float>(0, 0.03, 0))
        }
        return root
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

    // MARK: Шерсть (CoatLook)

    /// Цвет грязи, который подмешиваем в шерсть, и предел примеси.
    static let dirtTint: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.62, 0.5, 0.36)
    static let dirtMaxMix: CGFloat = 0.5

    /// Исходные (уже матовые) материалы моделей питомца: красим всегда от них, а не от прошлой покраски.
    private static var coatBase: [Entity.ID: [any Material]] = [:]
    /// Какой вид шерсти уже стоит на питомце (по корню), чтобы не перекрашивать без нужды.
    private static var coatShown: [Entity.ID: CoatLook] = [:]
    /// Модели, у меша которых есть наша развёртка под текстуру шерсти.
    private static var furUV: Set<Entity.ID> = []
    /// «Веко» для моргания (PetRig): шерсть Main плоским цветом с той же грязью, без текстуры. Текстурная шерсть
    /// на крошечных частях глаза ложилась белым пятном (tint у неё почти белый, цвет запечён в текстуру) — волна 16.
    private static var coatLid: [Entity.ID: any Material] = [:]
    /// Меши, которым развёртку уже построили: клоны из PetModel.load делят один меш — второй раз не строим.
    private static var furMeshes: [ObjectIdentifier: MeshResource] = [:]
    /// Текстуры шерсти «стадия-цвет основы»: каждая строится один раз (CoatFur.pixels), дальше из кэша.
    private static var furTextures: [String: TextureResource] = [:]
    /// Текстура повторяется (tiles раз по длине тела) и сглаживается, мипмапы — чтобы издали не рябило.
    private static let furSampler: MaterialParameters.Texture.Sampler = {
        let d = MTLSamplerDescriptor()
        d.sAddressMode = .repeat
        d.tAddressMode = .repeat
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        return MaterialParameters.Texture.Sampler(d)
    }()

    /// Запомнить исходные материалы. Звать сразу после matte, пока глаза открыты.
    static func prepareCoat(_ pet: Entity) {
        if coatBase.count > 64 { coatBase.removeAll() }
        if coatShown.count > 8 { coatShown.removeAll() }
        coatShown[pet.id] = nil
        var queue: [Entity] = [pet]
        while !queue.isEmpty {
            let e = queue.removeFirst()
            if let m = e as? ModelEntity, let mats = m.model?.materials {
                coatBase[m.id] = mats
                coatLid[m.id] = nil
                if !furIndices(mats).isEmpty, prepareFurUV(m) { furUV.insert(m.id) }
            }
            queue += Array(e.children)
        }
    }

    /// Развёртка под текстуру шерсти: у shiba.usdz её нет — строим коробочной проекцией (CoatFur.boxUVs) по рамке
    /// меша и подменяем содержимое меша (скелет и веса те же). Части с готовой развёрткой (коробки заглушки) не трогаем:
    /// у них своя, по граням. true — у меша наша развёртка, можно класть текстуру.
    private static func prepareFurUV(_ m: ModelEntity) -> Bool {
        guard var model = m.model else { return false }
        let mesh = model.mesh
        if furMeshes[ObjectIdentifier(mesh)] != nil { return true }
        let contents = mesh.contents
        let skinned = !m.jointNames.isEmpty
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for mm in contents.models {
            for part in mm.parts {
                for p in part.positions.elements {
                    lo = simd_min(lo, p)
                    hi = simd_max(hi, p)
                }
            }
        }
        guard lo.x < hi.x, lo.y < hi.y, lo.z < hi.z else { return false }
        var changed = false
        var models: [MeshResource.Model] = []
        for var mm in contents.models {
            var parts: [MeshResource.Part] = []
            for var part in mm.parts {
                // Уже с развёрткой или скин без весов (подмена его сломала бы) — как есть.
                if part.textureCoordinates == nil, !(skinned && part.jointInfluences == nil) {
                    let uv = CoatFur.boxUVs(positions: part.positions.elements, normals: part.normals?.elements,
                                            indices: part.triangleIndices?.elements ?? [], lo: lo, hi: hi)
                    part.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
                    changed = true
                }
                parts.append(part)
            }
            mm.parts = MeshPartCollection(parts)
            models.append(mm)
        }
        guard changed else { return false }
        var next = contents
        next.models = MeshModelCollection(models)
        let joints = m.jointNames.count
        do {
            try mesh.replace(with: next)
        } catch {
            // Не дал заменить на месте — новый меш с тем же содержимым.
            guard let fresh = try? MeshResource.generate(from: next) else { return false }
            model.mesh = fresh
            m.model = model
            if m.jointNames.count != joints {
                model.mesh = mesh
                m.model = model
                return false
            }
            furMeshes[ObjectIdentifier(fresh)] = fresh
            return true
        }
        // Скелет должен остаться тем же, иначе шерсть без текстуры, но живая.
        guard m.jointNames.count == joints else {
            try? mesh.replace(with: contents)
            return false
        }
        if furMeshes.count > 8 { furMeshes.removeAll() }
        furMeshes[ObjectIdentifier(mesh)] = mesh
        return true
    }

    /// Текстура шерсти стадии stage для основы base. Из кэша; nil — не собралась (тогда шерсть плоским цветом).
    private static func furTexture(_ stage: CoatStage, base: UInt32) -> TextureResource? {
        let key = "\(stage.rawValue)-\(String(base, radix: 16))"
        if let t = furTextures[key] { return t }
        guard let cg = furImage(stage: stage, base: base),
              let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) else { return nil }
        if furTextures.count > 16 { furTextures.removeAll() }
        furTextures[key] = tex
        return tex
    }

    /// Текстура штрихами по стадии, блеск и грязь на материалах шерсти. Только когда вид поменялся — не каждый кадр.
    /// Цвет основы запечён в текстуру, грязь — множителем tint (грязная / чистая по каналам). Клочки — PetWear.applyTufts.
    static func applyCoat(_ look: CoatLook, to pet: Entity) {
        if coatShown[pet.id] == look { return }
        coatShown[pet.id] = look
        let shine = Float(min(max(look.shine, 0), 1))
        let mix = min(max(CGFloat(look.dirt), 0), 1) * dirtMaxMix
        var queue: [Entity] = [pet]
        while !queue.isEmpty {
            let e = queue.removeFirst()
            queue += Array(e.children)
            guard let m = e as? ModelEntity, let base = coatBase[m.id], var model = m.model,
                  model.materials.count == base.count else { continue }
            var mats = base
            let textured = furUV.contains(m.id)
            for i in furIndices(base) {
                guard var pbr = base[i] as? PhysicallyBasedMaterial else { continue }
                pbr.roughness = .init(floatLiteral: 1 - 0.4 * shine)
                pbr.specular = .init(floatLiteral: 0.3 * shine)
                pbr.metallic = .init(floatLiteral: 0)
                let tint = pbr.baseColor.tint
                if textured, pbr.baseColor.texture == nil, let rgb = hex(tint), let tex = furTexture(look.stage, base: rgb) {
                    pbr.baseColor = .init(tint: ratio(dirtied(tint, mix), over: tint),
                                          texture: MaterialParameters.Texture(tex, sampler: furSampler))
                } else {
                    pbr.baseColor = .init(tint: dirtied(tint, mix), texture: pbr.baseColor.texture)
                }
                mats[i] = pbr
            }
            model.materials = mats
            m.model = model
            if var lid = base.first as? PhysicallyBasedMaterial {
                lid.roughness = .init(floatLiteral: 1 - 0.4 * shine)
                lid.specular = .init(floatLiteral: 0.3 * shine)
                lid.metallic = .init(floatLiteral: 0)
                lid.baseColor = .init(tint: dirtied(lid.baseColor.tint, mix), texture: nil)
                if coatLid.count > 64 { coatLid.removeAll() }
                coatLid[m.id] = lid
            }
            // Глаза моргают подменой материалов — пусть берут новую шерсть.
            PetRig.rig(for: pet)?.recolor(m, mats)
        }
    }

    /// Чем закрыть глаз модели m: шерсть плоским цветом (без текстуры). До первой покраски — исходная шерсть;
    /// не знаем модель — шерсть из mats без текстуры.
    static func eyeLid(_ m: ModelEntity, _ mats: [any Material]) -> (any Material)? {
        if let lid = coatLid[m.id] { return lid }
        guard var fur = (coatBase[m.id]?.first ?? mats.first) as? PhysicallyBasedMaterial else { return mats.first }
        fur.baseColor = .init(tint: fur.baseColor.tint, texture: nil)
        return fur
    }

    /// Сколько подмножеств у Шибы из usdz: шесть, с волны 13 седьмое — язык (Tongue, mouth.py). Порядок прежний,
    /// язык последний: шерсть 0 и 1, глаза 3…5.
    static let shibaMaterials: ClosedRange<Int> = 6...7

    /// Какие материалы — шерсть. У Шибы из usdz: Main и Main_Light; иначе — светлые PBR.
    private static func furIndices(_ mats: [any Material]) -> [Int] {
        if shibaMaterials.contains(mats.count) { return [0, 1] }
        return mats.indices.filter { i in
            guard let p = mats[i] as? PhysicallyBasedMaterial else { return false }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard p.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
            return r + g + b > 1.2
        }
    }

    /// Цвет шерсти своего персонажа (character.json color) — до matte и prepareCoat: от него потом считаются
    /// блеск, грязь и текстура штрихами. У модели как Шиба (шесть подмножеств) — только Main, светлое брюхо
    /// остаётся; у других — все светлые материалы, а нет светлых — первый.
    static func recolorFur(_ root: Entity, _ rgb: UInt32) {
        var queue: [Entity] = [root]
        while !queue.isEmpty {
            let e = queue.removeFirst()
            if let m = e as? ModelEntity, var model = m.model, !model.materials.isEmpty {
                let fur = shibaMaterials.contains(model.materials.count) ? [0] : furIndices(model.materials)
                for i in fur.isEmpty ? [0] : fur {
                    guard var pbr = model.materials[i] as? PhysicallyBasedMaterial else { continue }
                    pbr.baseColor = .init(tint: uiColor(rgb), texture: pbr.baseColor.texture)
                    model.materials[i] = pbr
                }
                m.model = model
            }
            queue += Array(e.children)
        }
    }

    /// Подмешать грязь: k от 0 до dirtMaxMix.
    private static func dirtied(_ c: UIColor, _ k: CGFloat) -> UIColor {
        guard k > 0.001 else { return c }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return c }
        let d = dirtTint
        return UIColor(red: r + (d.r - r) * k, green: g + (d.g - g) * k, blue: b + (d.b - b) * k, alpha: a)
    }

    /// Цвет 0xRRGGBB (sRGB) из UIColor.
    private static func hex(_ c: UIColor) -> UInt32? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func ch(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return ch(r) << 16 | ch(g) << 8 | ch(b)
    }

    /// Множитель по каналам: во сколько раз c темнее base (не больше 1 — tint только темнит).
    private static func ratio(_ c: UIColor, over base: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a),
              base.getRed(&r0, green: &g0, blue: &b0, alpha: &a0) else { return .white }
        func k(_ v: CGFloat, _ v0: CGFloat) -> CGFloat { v0 > 0.01 ? min(1, max(0, v / v0)) : 1 }
        return UIColor(red: k(r, r0), green: k(g, g0), blue: k(b, b0), alpha: 1)
    }

    // MARK: Текстуры (чистые функции, без RealityKit)

    /// Шерсть штрихами (CoatFur.pixels) — в картинку sRGB без альфы.
    nonisolated static func furImage(stage: CoatStage, base: UInt32, size: Int = CoatFur.size) -> CGImage? {
        let px = CoatFur.pixels(stage: stage, base: base, size: size)
        guard size > 0, let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

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

    /// Цвет по hex для других файлов сцены (RoomDecor, RoomLighting).
    static func color(_ hex: UInt32) -> UIColor { uiColor(hex) }

    /// shade < 1 — темнее на (1 − shade).
    private static func uiColor(_ hex: UInt32, shade: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xff) / 255 * shade, green: CGFloat((hex >> 8) & 0xff) / 255 * shade,
                blue: CGFloat(hex & 0xff) / 255 * shade, alpha: 1)
    }

    static func matteMaterial(_ hex: UInt32, shade: CGFloat = 1) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: uiColor(hex, shade: shade), texture: nil)
        m.roughness = .init(floatLiteral: 1)
        m.metallic = .init(floatLiteral: 0)
        m.specular = .init(floatLiteral: 0)
        return m
    }

    /// Пол, стены, ковёр и пятно сами тень не бросают (компонент действует только на свою сущность).
    static func noShadow(_ e: Entity) {
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
