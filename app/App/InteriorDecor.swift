// Волна 41 G: интерьер комнаты в сцене — обои, пол и ковёр по выбору (InteriorShown из AppModel).
// Узоры и размеры — чистые функции InteriorArt (app/Shared/Interior.swift, тесты в WSL); здесь только сборка
// сущностей. Стиль A: плоские матовые цвета, узор — геометрией (стены, ковёр) или пикселями цвета (пол),
// без картинок. Свет комнаты (RoomLighting) красит новое сам: при смене сбрасываем базу тинта и отдаём true.
// Вариант по умолчанию — ровно прежняя комната: с волны 53 это комната стиля B (PetRoom.wallMaterial /
// floorMaterial — лаванда в полоску и ёлочка, ковёр с кольцами), а не цвета образцов «по умолчанию».

import UIKit
@preconcurrency import RealityKit

/// Какой интерьер уже стоит в комнате (метка на сущности «room»): тот же — ничего не перестраиваем.
struct RoomInteriorShown: Component, Equatable {
    var shown: InteriorShown
}

@MainActor
extension RoomDecor {
    private static var interiorRegistered = false
    static let interiorWallName = "interiorWallPattern"
    static let interiorRugName = "interiorRug"

    /// Обои, пол и ковёр в комнату. Тот же выбор — ничего не делает (зовётся из update на каждый пересчёт вью).
    /// true — перекрасили: свету комнаты нужно перекрасить заново.
    @discardableResult
    static func applyInterior(_ s: InteriorShown, to room: Entity) -> Bool {
        if !interiorRegistered {
            RoomInteriorShown.registerComponent()
            RoomLighting.registerOnce()
            interiorRegistered = true
        }
        // Свежая комната (PetRoom.room) собрана в варианте по умолчанию: меняем только отличающиеся части.
        let before = room.components[RoomInteriorShown.self]?.shown ?? .standard
        room.components.set(RoomInteriorShown(shown: s))
        if before == s { return false }
        var changed = false
        if before.walls != s.walls, let st = Interior.style(s.walls), case .walls(let w) = st.look {
            changed = applyWalls(w, isStandard: s.walls == Interior.standard(.walls).id, in: room) || changed
        }
        if before.floor != s.floor, let st = Interior.style(s.floor), case .floor(let f) = st.look {
            changed = applyFloor(f, isStandard: s.floor == Interior.standard(.floor).id, in: room) || changed
        }
        if before.rug != s.rug, let st = Interior.style(s.rug), case .rug(let r) = st.look {
            changed = applyRug(r, isStandard: s.rug == Interior.standard(.rug).id, in: room) || changed
        }
        return changed
    }

    // MARK: стены

    /// Фон обеих стен (левая чуть темнее, как была) и узор на задней — тонкой сеткой поверх, под окном и полками.
    /// По умолчанию (isStandard) — стены комнаты стиля B, без узора поверх.
    private static func applyWalls(_ look: WallLook, isStandard: Bool, in room: Entity) -> Bool {
        guard let back = room.findEntity(named: "wallBack") as? ModelEntity else { return false }
        back.model?.materials = [isStandard ? PetRoom.wallMaterial() : PetRoom.matteMaterial(look.base)]
        back.components.remove(RoomTintBase.self)
        if let left = room.findEntity(named: "wallLeft") as? ModelEntity {
            left.model?.materials = [isStandard ? PetRoom.wallMaterial(shade: 0.96) : PetRoom.matteMaterial(look.base, shade: 0.96)]
            left.components.remove(RoomTintBase.self)
        }
        back.children.filter { $0.name == interiorWallName }.forEach { $0.removeFromParent() }
        if isStandard { return true }
        let shapes = InteriorArt.wallShapes(look)
        guard !shapes.isEmpty else { return true }
        let g = Entity()
        g.name = interiorWallName
        // Своя плоскость стены: x и y от центра, лицом к камере (+z). Чуть перед стеной, но за небом окна
        // (его передняя грань на +0,003) и за всем, что висит на стене.
        let ox = -InteriorArt.wallWidth / 2, oy = -InteriorArt.wallHeight / 2, z: Float = 0.002
        var byColor: [UInt32: [WallShape]] = [:]
        var order: [UInt32] = []
        for s in shapes {
            if byColor[s.color] == nil { order.append(s.color) }
            byColor[s.color, default: []].append(s)
        }
        for color in order {
            var pos: [SIMD3<Float>] = []
            var idx: [UInt32] = []
            for s in byColor[color] ?? [] {
                let c = UInt32(pos.count)
                pos.append(SIMD3(s.center.x + ox, s.center.y + oy, z))
                for p in s.rim { pos.append(SIMD3(p.x + ox, p.y + oy, z)) }
                let n = UInt32(s.rim.count)
                for i in 0..<n { idx += [c, c + 1 + i, c + 1 + (i + 1) % n] }
            }
            var d = MeshDescriptor(name: "interior.wall.\(color)")
            d.positions = MeshBuffers.Positions(pos)
            d.normals = MeshBuffers.Normals(Array(repeating: SIMD3<Float>(0, 0, 1), count: pos.count))
            d.primitives = .triangles(idx)
            guard let mesh = try? MeshResource.generate(from: [d]) else { continue }
            let e = ModelEntity(mesh: mesh, materials: [PetRoom.matteMaterial(color)])
            PetRoom.noShadow(e)
            g.addChild(e)
        }
        back.addChild(g)
        return true
    }

    // MARK: пол

    /// Пол — та же плоскость, новая текстура из пикселей узора; по умолчанию — ёлочка стиля B (PetRoom.floorMaterial).
    private static func applyFloor(_ look: FloorLook, isStandard: Bool, in room: Entity) -> Bool {
        guard let floor = room.findEntity(named: "floor") as? ModelEntity else { return false }
        if isStandard {
            floor.model?.materials = [PetRoom.floorMaterial()]
            floor.components.remove(RoomTintBase.self)
            return true
        }
        var mat = PetRoom.matteMaterial(look.colors.last ?? RoomColors.checkerLight)
        if let cg = floorImage(look), let tex = try? TextureResource(image: cg, options: .init(semantic: .color)) {
            mat.baseColor = .init(tint: .white, texture: MaterialParameters.Texture(tex))
        }
        floor.model?.materials = [mat]
        floor.components.remove(RoomTintBase.self)
        return true
    }

    /// 512 px на 5 м: шов досок (1,5 см) — полтора пикселя, клетки по 51 px.
    private static func floorImage(_ look: FloorLook) -> CGImage? {
        let size = 512
        let px = InteriorArt.floorPixels(look, size: size)
        guard px.count == size * size * 4, let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: ковёр

    /// По умолчанию — прежний диск «rug»; другой — группа плоских кусков на его месте, прежний прячем.
    private static func applyRug(_ look: RugLook, isStandard: Bool, in room: Entity) -> Bool {
        room.children.filter { $0.name == interiorRugName }.forEach { $0.removeFromParent() }
        let old = room.findEntity(named: "rug")
        old?.isEnabled = isStandard
        guard !isStandard else { return true }
        let g = Entity()
        g.name = interiorRugName
        g.position = old?.position.withY(0) ?? .zero
        let h = InteriorArt.rugThickness
        for p in InteriorArt.rugPieces(look) {
            let mesh: MeshResource
            var scale = SIMD3<Float>(repeating: 1)
            switch p.shape {
            case .disc(let r):
                mesh = .generateCylinder(height: h, radius: r)
            case .ellipse(let rx, let rz):
                mesh = .generateCylinder(height: h, radius: rx)
                scale = [1, 1, rz / rx]
            case .box(let w, let d):
                mesh = .generateBox(size: [w, h, d])
            }
            let e = ModelEntity(mesh: mesh, materials: [PetRoom.matteMaterial(p.color)])
            e.position = [p.x, p.top - h / 2, p.z]
            e.scale = scale
            PetRoom.noShadow(e)
            g.addChild(e)
        }
        room.addChild(g)
        return true
    }
}

private extension SIMD3 where Scalar == Float {
    func withY(_ y: Float) -> SIMD3<Float> { SIMD3(x, y, z) }
}
