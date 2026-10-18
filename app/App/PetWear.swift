// Надетое на Шибе в 3D. Фигуры — WearMesh (app/Shared, координаты тела shiba.glb), цвета — Wear.table.
// Каждая часть — ребёнок скинованной модели и каждый кадр встаёт по своей кости:
//   часть = J(кость, сейчас) · invBind(кость) · (тело → модель) · (замеры → тело),
// то есть едет так же, как вершины шерсти, целиком привязанные к этой кости (шапка с головой, плащ со спиной).
// Масштаб и сдвиг тела модели подбираются по костям Body и Head и проверяются по остальным: другая модель
// или скелет не сошёлся — вещи просто стоят на теле (по рамке модели). Заглушка без модели — свой перенос.
// Перестраивается только при смене надетого; шерсть (PetRoom.applyCoat) вещи не перекрашивает.

import UIKit
@preconcurrency import RealityKit

@MainActor
enum PetWear {
    static let rootName = "petWear"

    private enum Mode {
        /// По костям скинованной модели skin (части — её дети, pre у каждой своя).
        case bones(ModelEntity)
        /// Без костей: на теле, одной матрицей.
        case still
        /// Заглушка из коробок: вершины перенесены сразу (WearMesh.stubMap).
        case stub
    }

    private final class Shown {
        var key = ""
        weak var root: Entity?
        var parts: [(entity: ModelEntity, joint: Int, pre: simd_float4x4)] = []
    }

    private static var shown: [Entity.ID: Shown] = [:]
    /// Рамка тела до первой вещи (для режима без костей): потом вещи сами попадут в рамку.
    private static var restBounds: [Entity.ID: BoundingBox] = [:]

    /// Надеть на питомца pet (корень из PetModel.load) то, что в worn. То же самое — ничего не делает.
    static func apply(_ worn: [WearSlot: String], to pet: Entity) {
        let key = worn.keys.sorted().map { "\($0.rawValue)=\(worn[$0] ?? "")" }.joined(separator: ",")
        let state = shown[pet.id] ?? Shown()
        if shown[pet.id] == nil {
            if shown.count > 8 { shown.removeAll(); restBounds.removeAll() }
            shown[pet.id] = state
        }
        guard let body = pet.findEntity(named: PetModel.bodyName) else { return }
        if restBounds[pet.id] == nil { restBounds[pet.id] = body.visualBounds(relativeTo: body) }
        if state.key == key, state.root?.parent != nil || worn.isEmpty { return }
        state.key = key
        state.root?.removeFromParent()
        state.root = nil
        state.parts = []
        guard !worn.isEmpty else { return }

        let mode = self.mode(body)
        let root = Entity()
        root.name = rootName
        for slot in worn.keys.sorted() {
            guard let id = worn[slot], let info = Wear.info(id) else { continue }
            for part in WearMesh.parts(info.shape) {
                guard let e = entity(part, info: info, slot: slot, mode: mode) else { continue }
                root.addChild(e)
                switch mode {
                case .bones(let skin):
                    if case let (j, pre)? = bonePre(skin, body: body, joint: part.joint) {
                        state.parts.append((e, j, pre))
                    } else {
                        e.isEnabled = false
                    }
                case .still:
                    if let a = fromBounds(restBounds[pet.id]) { e.transform = Transform(matrix: a) }
                case .stub:
                    break
                }
            }
        }
        switch mode {
        case .bones(let skin): skin.addChild(root)
        case .still, .stub: body.addChild(root)
        }
        state.root = root
        step(pet)
    }

    /// Кадр: части за своими костями. Зовётся из PetActSystem после PetRig (взгляд уже записан в кости).
    static func step(_ pet: Entity) {
        guard let state = shown[pet.id], !state.parts.isEmpty,
              let skin = state.root?.parent as? ModelEntity else { return }
        let tr = skin.jointTransforms
        guard let parents = rigParents[skin.id], tr.count == parents.count else { return }
        var cache: [Int: simd_float4x4] = [:]
        func global(_ j: Int) -> simd_float4x4 {
            if let m = cache[j] { return m }
            var m = tr[j].matrix
            var p = parents[j]
            var n = 0
            while p >= 0 && n < 64 {
                m = tr[p].matrix * m
                p = parents[p]
                n += 1
            }
            cache[j] = m
            return m
        }
        for part in state.parts where part.joint < tr.count {
            let m = global(part.joint) * part.pre
            guard finite(m) else { part.entity.isEnabled = false; continue }
            part.entity.transform = Transform(matrix: m)
        }
    }

    // MARK: режим

    private static var rigParents: [Entity.ID: [Int]] = [:]
    /// Тело модели в замерах: x_тела = s · x_замеров + offset. По костям, на модель один раз.
    private static var fits: [Entity.ID: simd_float4x4?] = [:]

    private static func mode(_ body: Entity) -> Mode {
        if body.findEntity(named: StubDog.markName) != nil { return .stub }
        guard let skin = skinned(body), fit(skin, body: body) != nil else { return .still }
        return .bones(skin)
    }

    private static func skinned(_ body: Entity) -> ModelEntity? {
        var queue: [Entity] = [body]
        while !queue.isEmpty {
            let e = queue.removeFirst()
            if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
            queue += Array(e.children)
        }
        return nil
    }

    private static func leafIndex(_ names: [String], _ leaf: String) -> Int? {
        names.firstIndex { $0 == leaf || $0.hasSuffix("/" + leaf) }
    }

    /// invBind кости из скелета меша (по имени: пути у скелета и у модели могут отличаться префиксом).
    private static func invBind(_ skin: ModelEntity, _ leaf: String) -> simd_float4x4? {
        guard let skeletons = skin.model?.mesh.contents.skeletons else { return nil }
        for s in skeletons {
            if let i = leafIndex(s.jointNames, leaf), i < s.inverseBindPoseMatrices.count {
                return s.inverseBindPoseMatrices[i]
            }
        }
        return nil
    }

    private static func fit(_ skin: ModelEntity, body: Entity) -> simd_float4x4? {
        if let f = fits[skin.id] { return f }
        if fits.count > 8 { fits.removeAll(); rigParents.removeAll() }
        let names = skin.jointNames
        var index: [String: Int] = [:]
        for (i, n) in names.enumerated() { index[n] = i }
        rigParents[skin.id] = names.map { n in
            guard let cut = n.lastIndex(of: "/") else { return -1 }
            return index[String(n[..<cut])] ?? -1
        }
        let f = computeFit(skin, body: body)
        fits[skin.id] = f
        return f
    }

    private static func computeFit(_ skin: ModelEntity, body: Entity) -> simd_float4x4? {
        guard skin.jointTransforms.count == skin.jointNames.count else { return nil }
        let skinToBody = skin.transformMatrix(relativeTo: body)
        // Где кость в позе покоя в координатах тела.
        func bindPos(_ leaf: String) -> SIMD3<Float>? {
            guard let ib = invBind(skin, leaf), abs(ib.determinant) > 1e-12 else { return nil }
            let p = skinToBody * ib.inverse * SIMD4<Float>(0, 0, 0, 1)
            return SIMD3(p.x, p.y, p.z) / p.w
        }
        guard let gBody = WearMesh.bindJoints["Body"], let gHead = WearMesh.bindJoints["Head"],
              let pBody = bindPos("Body"), let pHead = bindPos("Head") else { return nil }
        let dg = gHead - gBody, dp = pHead - pBody
        let s = simd_length(dp) / simd_length(dg)
        guard s.isFinite, s > 1e-6, simd_dot(simd_normalize(dp), simd_normalize(dg)) > 0.97 else { return nil }
        let offset = pHead - gHead * s
        // Остальные кости должны лечь на свои места (10% роста Шибы).
        let tol = 0.1 * WearMesh.restMax.y * s
        for (leaf, g) in WearMesh.bindJoints where leaf != "Body" && leaf != "Head" {
            guard let p = bindPos(leaf), simd_length(p - (g * s + offset)) < tol else { return nil }
        }
        return affine(scale: s, offset: offset)
    }

    /// pre для части на кости leaf: invBind · (тело → модель) · (замеры → тело).
    private static func bonePre(_ skin: ModelEntity, body: Entity, joint leaf: String)
        -> (Int, simd_float4x4)? {
        guard let j = leafIndex(skin.jointNames, leaf), let ib = invBind(skin, leaf),
              let f = fits[skin.id] ?? nil else { return nil }
        let bodyToSkin = body.transformMatrix(relativeTo: skin)
        return (j, ib * bodyToSkin * f)
    }

    /// Без скелета: рамку Шибы из замеров — в рамку модели.
    private static func fromBounds(_ b: BoundingBox?) -> simd_float4x4? {
        guard let b, b.extents.y > 0 else { return nil }
        let size = WearMesh.restMax - WearMesh.restMin
        let s = b.extents.y / size.y
        let gCenter = (WearMesh.restMax + WearMesh.restMin) / 2
        let offset = SIMD3<Float>(b.center.x - gCenter.x * s, b.min.y - WearMesh.restMin.y * s,
                                  b.center.z - gCenter.z * s)
        return affine(scale: s, offset: offset)
    }

    private static func affine(scale s: Float, offset o: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(SIMD4(s, 0, 0, 0), SIMD4(0, s, 0, 0), SIMD4(0, 0, s, 0), SIMD4(o.x, o.y, o.z, 1))
    }

    private static func finite(_ m: simd_float4x4) -> Bool {
        for c in [m.columns.0, m.columns.1, m.columns.2, m.columns.3] {
            if !(c.x.isFinite && c.y.isFinite && c.z.isFinite && c.w.isFinite) { return false }
        }
        return true
    }

    // MARK: меш

    private static func entity(_ part: WearPart, info: WearInfo, slot: WearSlot, mode: Mode) -> ModelEntity? {
        var positions = part.positions
        if case .stub = mode {
            let map = WearMesh.stubMap(slot)
            positions = positions.map { map.to + ($0 - map.from) * map.scale }
        }
        var d = MeshDescriptor(name: "wear")
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(part.normals)
        d.primitives = .triangles(part.indices)
        guard let mesh = try? MeshResource.generate(from: [d]) else { return nil }
        let e = ModelEntity(mesh: mesh, materials: [PetRoom.matteMaterial(part.accent ? info.accent : info.color)])
        e.name = "wear.\(slot.rawValue)"
        return e
    }
}
