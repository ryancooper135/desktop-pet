// Кости шеи и головы Шибы и веки: взгляд, челюсть, моргание (шагает из PetActSystem).
// Перенесено из PetChoreo.swift без изменений (волна 28).

import Foundation
import simd
import UIKit
@preconcurrency import RealityKit

// MARK: - Кости и глаза

/// Шея и голова Шибы и материалы глаз. Ищется один раз на питомца.
@MainActor
final class PetRig {
    private static var rigs: [Entity.ID: PetRig] = [:]

    private weak var skin: ModelEntity?
    /// Кости, которые сцена поворачивает поверх клипа: Neck3 и Head (взгляд и наклон набок), уши и хвост
    /// (отклик на тап, TapWiggle). Своя запись кости в last: если клип кость не перезаписал, основа — прежняя.
    private enum Role {
        /// Шея или голова, доля поворота взгляда и наклона.
        case look(Float)
        /// Ухо, доля «уши назад».
        case ear(Float)
        /// Звено хвоста 0…2.
        case tail(Int)
    }
    private var joints: [Int] = []
    private var roles: [Role] = []
    private var parents: [Int] = []
    private var base: [simd_quatf] = []
    private var last: [simd_quatf?] = []
    /// Кость головы и кончик морды (TongueTip, иначе Jaw): по ним ось «вперёд» для наклона и ушей.
    private var head: Int?
    private var snout: Int?

    /// Челюсть (волна 13, mouth.py): кость Jaw и ось «открыть рот» в её своей системе. Нет Jaw или TongueTip
    /// (старая модель, свой персонаж) — talk ничего не делает.
    private var jaw: Int?
    private var jawAxis = SIMD3<Float>(1, 0, 0)
    private var jawBase = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var jawLast: simd_quatf?

    private weak var eyes: ModelEntity?
    /// Веки: подмножества глаз 3…5 отдельным скинованным мешем на том же скелете, чуть впереди глаз, цвета шерсти.
    /// Глаз закрываем, включая веки, а не подменой материалов глаз: обратная подмена на скинованной Шибе до кадра
    /// не доходила — ModelComponent уже с открытыми глазами, а на экране веко навсегда (волны 15–16, прогоны
    /// 39259023360 и 39266177342; новый ModelComponent, снять-поставить, свежие материалы — то же самое).
    private var lids: ModelEntity?
    private var eyesClosed = false
    static let lidsName = "petEyeLids"
    /// Блики (волна 50, EyeStyle): копии диска глаза на тех же костях, видны, пока глаз открыт.
    private var glints: ModelEntity?
    static let glintsName = "petEyeGlints"

    /// Рост (волна 34 I, Growth.look): голова крупнее, уши висят, хвост не завит. nil или взрослый — как было.
    /// Один на все риги (пёс один): кэш ригов сбрасывается, а рост не должен теряться до следующего update сцены.
    private static var growth: GrowthLook?
    /// Масштаб кости Head из позы покоя: голову растим от него, а не от единицы.
    private var headScale = SIMD3<Float>(repeating: 1)

    static func rig(for pet: Entity) -> PetRig? {
        let id = pet.id
        if let r = rigs[id] { return r }
        guard let body = pet.findEntity(named: PetModel.bodyName) else { return nil }
        if rigs.count > 8 { rigs.removeAll() }
        let r = PetRig(body)
        rigs[id] = r
        return r
    }

    private init(_ body: Entity) {
        var queue: [Entity] = [body]
        while !queue.isEmpty {
            let e = queue.removeFirst()
            if let m = e as? ModelEntity {
                if skin == nil, !m.jointNames.isEmpty { setUpJoints(m) }
                if eyes == nil, let mats = m.model?.materials, PetRoom.shibaMaterials.contains(mats.count) {
                    setUpEyes(m, mats)
                }
            }
            queue += Array(e.children)
        }
    }

    /// Пути костей вида «Body/…/Neck3/Head»: родитель — путь без последнего звена.
    private func setUpJoints(_ m: ModelEntity) {
        let names = m.jointNames
        // Свой персонаж — по псевдонимам костей из character.json.
        func find(_ leaf: String) -> Int? { PetModel.boneIndex(names, leaf) }
        guard let neck = find("Neck3"), let head = find("Head"), m.jointTransforms.count == names.count else { return }
        var index: [String: Int] = [:]
        for (i, n) in names.enumerated() { index[n] = i }
        parents = names.map { n in
            guard let cut = n.lastIndex(of: "/") else { return -1 }
            return index[String(n[..<cut])] ?? -1
        }
        skin = m
        joints = [neck, head]
        roles = [.look(0.4), .look(0.6)]
        // Уши и хвост — для отклика на тап; нет какой-то кости (свой персонаж) — без неё.
        let ears: [(String, Float)] = [("Ear1.L", 1), ("Ear1.R", 1), ("Ear2.L", 0.4), ("Ear2.R", 0.4)]
        for (leaf, share) in ears {
            if let j = find(leaf), !joints.contains(j) { joints.append(j); roles.append(.ear(share)) }
        }
        if Env.isUITest { EyeProbe.ears = roles.filter { if case .ear = $0 { return true } else { return false } }.count }
        for (k, leaf) in ["Tail1", "Tail2", "Tail3"].enumerated() {
            if let j = find(leaf), !joints.contains(j) { joints.append(j); roles.append(.tail(k)) }
        }
        base = joints.map { m.jointTransforms[$0].rotation }
        last = joints.map { _ in nil }
        self.head = head
        headScale = m.jointTransforms[head].scale
        snout = find("TongueTip") ?? find("Jaw")
        if snout == head { snout = nil }
        setUpJaw(m)
    }

    /// Ось челюсти: поперёк морды, так чтобы поворот вёл кончик языка вниз (рот открывается). Считаем по
    /// положениям костей Jaw → TongueTip (вперёд) и вертикали модели — не зависим от того, как экспорт повернул кость.
    private func setUpJaw(_ m: ModelEntity) {
        let names = m.jointNames
        guard let jw = PetModel.boneIndex(names, "Jaw"), let tip = PetModel.boneIndex(names, "TongueTip"),
              tip != jw else { return }
        let tr = m.jointTransforms
        let rot = tr.map(\.rotation)
        let fwd = position(tip, tr) - position(jw, tr)
        let up = simd_normalize(m.convert(direction: ChoreoPath.up, from: nil))
        let side = simd_cross(fwd, -up)
        guard simd_length(side) > 1e-6, side.x.isFinite else { return }
        let axis = simd_normalize(global(jw, rot).inverse.act(simd_normalize(side)))
        guard axis.x.isFinite, axis.y.isFinite, axis.z.isFinite else { return }
        jaw = jw
        jawAxis = axis
        jawBase = tr[jw].rotation
        jawLast = nil
    }

    /// Положение кости в системе модели (цепочка родителей, как в global).
    private func position(_ j: Int, _ tr: [Transform]) -> SIMD3<Float> {
        var m = tr[j].matrix
        var p = parents[j]
        var n = 0
        while p >= 0 && n < 64 {
            m = tr[p].matrix * m
            p = parents[p]
            n += 1
        }
        return SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }

    /// Челюсть приоткрыта на angle радиан поверх позы клипа (как look: свою прошлую запись за позу не берём).
    func talk(_ angle: Float) {
        guard let m = skin, let j = jaw else { return }
        if abs(angle) < 1e-4 && jawLast == nil { return }
        var tr = m.jointTransforms
        guard j < tr.count else { return }
        let cur = tr[j].rotation
        if !(jawLast.map { Self.same(cur, $0) } ?? false) { jawBase = cur }
        if abs(angle) < 1e-4 {
            tr[j].rotation = jawBase
            jawLast = nil
        } else {
            let q = jawBase * simd_quatf(angle: angle, axis: jawAxis)
            tr[j].rotation = q
            jawLast = q
        }
        m.jointTransforms = tr
    }

    /// Сцена передаёт реплику с экрана (PetStage): новая — челюсть начинает «говорить» с начала.
    static func say(_ text: String?, to pet: Entity) {
        guard var face = pet.components[PetFace.self], face.talk != text else { return }
        face.talk = text
        face.talkFrom = face.time
        pet.components.set(face)
    }

    /// Порядок подмножеств: Main, Main_Light, Black, Eyes_White, Eyes_Pupil, Eyes_Black. Проверяем по цвету,
    /// что 4 и 5 темнее шерсти, а 3 на шерсть не похож; не сошлось — не моргаем. С волны 16 «белок» у Шибы
    /// тёмно-карий (style_a: белые серпы по бокам радужки читались как закатанные глаза), поэтому 3 может быть
    /// и светлее шерсти (свои персонажи Quaternius), и темнее.
    /// Волна 50: цвет — не единственный признак. Тёмный окрас темнее карей радужки (EyeStyle.iris), и по цвету
    /// глаза «не глаза» — без век и бликов. Поэтому глаза узнаём и по форме (EyePin.plausible): пара мелких дисков.
    /// Веко — шерсть плоским цветом (PetRoom.eyeLid): у текстурной шерсти tint почти белый, и глаз
    /// закрывался белым пятном (ui-55, ui-63 волны 15).
    private func setUpEyes(_ m: ModelEntity, _ mats: [any Material]) {
        guard let lid = PetRoom.eyeLid(m, mats) else { return }
        let light = mats.map(Self.brightness)
        let byColor = Self.brightness(lid).flatMap { fur -> Bool? in
            guard let white = light[3], let pupil = light[4], let black = light[5] else { return nil }
            return Self.looksLikeEyes(fur: fur, white: white, pupil: pupil, black: black)
        } ?? false
        guard byColor || Self.eyesByShape(m) else { return }
        if let mesh = Self.lidMesh(m) {
            let e = ModelEntity(mesh: mesh, materials: [lid, Self.creaseMaterial])
            if e.jointNames == m.jointNames {
                e.name = Self.lidsName
                e.isEnabled = false
                m.addChild(e)
                lids = e
            }
        }
        if let mesh = Self.glintMesh(m, spots: EyeStyle.spots(EyeStyle.current)) {
            let g = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: PetRoom.color(EyeStyle.glint))])
            if g.jointNames == m.jointNames {
                g.name = Self.glintsName
                g.jointTransforms = m.jointTransforms
                m.addChild(g)
                glints = g
            }
        }
        guard lids != nil || glints != nil else { return }
        eyes = m
        if Env.isUITest {
            EyeProbe.eyes = true
            EyeProbe.glints = glints == nil ? 0 : 1
        }
    }

    /// Шов закрытого глаза (EyeStyle.crease): второй материал век.
    private static var creaseMaterial: any Material {
        SimpleMaterial(color: PetRoom.color(EyeStyle.crease), roughness: 0.9, isMetallic: false)
    }

    /// Пара глаз по форме: вершины подмножеств 3…5 — два мелких диска рядом (EyePin.plausible), без цвета.
    private static func eyesByShape(_ m: ModelEntity) -> Bool {
        guard let mesh = m.model?.mesh else { return false }
        var points: [SIMD3<Float>] = []
        for mm in mesh.contents.models {
            for part in mm.parts where (3...5).contains(part.materialIndex) { points += part.positions.elements }
        }
        let ext = mesh.bounds.extents
        guard let eyes = EyePin.eyes(points) else { return false }
        return EyePin.plausible(eyes, extent: max(ext.x, ext.y, ext.z))
    }

    /// Рамка глаза в системе меша: центр, нормаль наружу, «вверх» и «влево по экрану», насколько самая выпуклая
    /// точка впереди центра (top), и диск-источник (Eyes_Black, иначе 4, иначе 3): его центр и размер у этого глаза.
    private struct EyeFrame {
        var center: SIMD3<Float>
        var normal: SIMD3<Float>
        var up: SIMD3<Float>
        var left: SIMD3<Float>
        var top: Float
        var source: SIMD3<Float>
        var sourceSize: Float
    }

    /// Рамки глаз одной модели меша и диск-источник. nil — глаз нет, нет нормалей или глаз смотрит вверх.
    private static func eyeFrames(_ parts: [MeshResource.Part], sceneUp: SIMD3<Float>)
        -> (frames: [EyeFrame], size: Float, source: MeshResource.Part)? {
        let eyeParts = parts.filter { (3...5).contains($0.materialIndex) && $0.jointInfluences != nil }
        guard let eyes = EyePin.eyes(eyeParts.flatMap { $0.positions.elements }),
              let src = [5, 4, 3].lazy.compactMap({ i in eyeParts.first { $0.materialIndex == i } }).first
        else { return nil }
        let n = eyes.centers.count
        var sum = [SIMD3<Float>](repeating: .zero, count: n)
        for part in eyeParts {
            guard let normals = part.normals?.elements, normals.count == part.positions.elements.count else { continue }
            for (p, nv) in zip(part.positions.elements, normals) { sum[nearest(p, eyes.centers)] += nv }
        }
        var normal = [SIMD3<Float>](repeating: .zero, count: n)
        for k in 0..<n {
            let l = simd_length(sum[k])
            guard l > 1e-6, l.isFinite else { return nil }
            normal[k] = sum[k] / l
        }
        var top = [Float](repeating: 0, count: n)
        for part in eyeParts {
            for p in part.positions.elements {
                let k = nearest(p, eyes.centers)
                top[k] = max(top[k], simd_dot(p - eyes.centers[k], normal[k]))
            }
        }
        var lo = [SIMD3<Float>](repeating: SIMD3(repeating: .greatestFiniteMagnitude), count: n)
        var hi = [SIMD3<Float>](repeating: SIMD3(repeating: -.greatestFiniteMagnitude), count: n)
        for p in src.positions.elements {
            let k = nearest(p, eyes.centers)
            lo[k] = simd_min(lo[k], p)
            hi[k] = simd_max(hi[k], p)
        }
        var frames: [EyeFrame] = []
        for k in 0..<n {
            guard lo[k].x <= hi[k].x, let ax = EyeStyle.axes(normal: normal[k], sceneUp: sceneUp) else { return nil }
            let e = hi[k] - lo[k]
            let size = max(e.x, e.y, e.z)
            guard size > 0 else { return nil }
            frames.append(EyeFrame(center: eyes.centers[k], normal: normal[k], up: ax.up, left: ax.left,
                                   top: top[k], source: (lo[k] + hi[k]) / 2, sourceSize: size))
        }
        return (frames, eyes.size, src)
    }

    private static func nearest(_ p: SIMD3<Float>, _ centers: [SIMD3<Float>]) -> Int {
        var best = 0
        var d = Float.greatestFiniteMagnitude
        for (i, c) in centers.enumerated() {
            let v = simd_length_squared(p - c)
            if v < d { d = v; best = i }
        }
        return best
    }

    /// Копия диска-источника, каждая вершина которой встала по map (кадр её глаза). Веса костей — те же.
    private static func copy(_ src: MeshResource.Part, id: String, material: Int, frames: [EyeFrame],
                             map: (SIMD3<Float>, EyeFrame) -> SIMD3<Float>) -> MeshResource.Part {
        var part = src
        part.id = src.id + id
        part.materialIndex = material
        let centers = frames.map(\.center)
        part.positions = MeshBuffers.Positions(src.positions.elements.map { p in map(p, frames[nearest(p, centers)]) })
        if let normals = src.normals?.elements, normals.count == src.positions.elements.count {
            part.normals = MeshBuffers.Normals(src.positions.elements.map { frames[nearest($0, centers)].normal })
        }
        return part
    }

    /// Меш бликов (волна 50): на каждый глаз и каждое пятно варианта — уменьшенная копия диска глаза поверх
    /// зрачка, сдвинутая вверх-влево (EyeStyle.place). Из геометрии самой модели — работает на любой модели
    /// с глазами-дисками, не нужен ни ассет, ни правка shiba.usdz.
    private static func glintMesh(_ m: ModelEntity, spots: [EyeStyle.Spot]) -> MeshResource? {
        guard let contents = m.model?.mesh.contents, !spots.isEmpty else { return nil }
        let up = simd_normalize(m.convert(direction: ChoreoPath.up, from: nil))
        var models: [MeshResource.Model] = []
        for var mm in contents.models {
            guard let f = eyeFrames(Array(mm.parts), sceneUp: up) else { continue }
            var parts: [MeshResource.Part] = []
            for (s, spot) in spots.enumerated() {
                parts.append(copy(f.source, id: "-glint\(s)", material: 0, frames: f.frames) { p, e in
                    EyeStyle.place(p, source: e.source, sourceSize: e.sourceSize, center: e.center, normal: e.normal,
                                   up: e.up, left: e.left, size: f.size, top: e.top, spot: spot)
                })
            }
            mm.parts = MeshPartCollection(parts)
            models.append(mm)
        }
        guard !models.isEmpty else { return nil }
        let ids = Set(models.map(\.id))
        var next = contents
        next.models = MeshModelCollection(models)
        next.instances = MeshInstanceCollection(contents.instances.filter { ids.contains($0.model) })
        return try? MeshResource.generate(from: next)
    }

    /// Меш век: части глаз (3…5) с теми же весами костей, сдвинутые по нормалям наружу на 3% размера глаз —
    /// поверх глаза без мерцания, кайма (Black) вокруг остаётся видна. Волна 50: плюс шов (материал 1) — тёмная
    /// дуга поверх века, чтобы закрытый глаз читался закрытым, а не пропавшим. nil — глаз нет или меш не собрался.
    private static func lidMesh(_ m: ModelEntity) -> MeshResource? {
        guard let contents = m.model?.mesh.contents else { return nil }
        let up = simd_normalize(m.convert(direction: ChoreoPath.up, from: nil))
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        var models: [MeshResource.Model] = []
        var frames: [String: (frames: [EyeFrame], size: Float, source: MeshResource.Part)] = [:]
        for var mm in contents.models {
            let parts = mm.parts.filter {
                (3...5).contains($0.materialIndex) && $0.jointInfluences != nil
                    && $0.normals?.elements.count == $0.positions.elements.count
            }
            guard !parts.isEmpty else { continue }
            for part in parts {
                for p in part.positions.elements {
                    lo = simd_min(lo, p)
                    hi = simd_max(hi, p)
                }
            }
            frames[mm.id] = eyeFrames(parts, sceneUp: up)
            mm.parts = MeshPartCollection(parts)
            models.append(mm)
        }
        guard !models.isEmpty, lo.x < hi.x else { return nil }
        let push = 0.03 * max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
        for k in models.indices {
            var parts: [MeshResource.Part] = []
            for var part in models[k].parts {
                let normals = part.normals?.elements ?? []
                let moved = zip(part.positions.elements, normals).map { p, n -> SIMD3<Float> in
                    let l = simd_length(n)
                    return l > 1e-6 ? p + n / l * push : p
                }
                part.positions = MeshBuffers.Positions(moved)
                part.materialIndex = 0
                parts.append(part)
            }
            if let f = frames[models[k].id] {
                parts.append(copy(f.source, id: "-crease", material: 1, frames: f.frames) { p, e in
                    EyeStyle.creasePoint(p, source: e.source, sourceSize: e.sourceSize, center: e.center,
                                         normal: e.normal, up: e.up, left: e.left, size: f.size,
                                         front: e.top + push + 0.05 * f.size)
                })
            }
            models[k].parts = MeshPartCollection(parts)
        }
        let ids = Set(models.map(\.id))
        var next = contents
        next.models = MeshModelCollection(models)
        next.instances = MeshInstanceCollection(contents.instances.filter { ids.contains($0.model) })
        return try? MeshResource.generate(from: next)
    }

    /// Живые глаза (волна 50, EyeStyle): ободок, карая радужка, зрачок — на Шибе из usdz (подмножества 3…5).
    /// Звать при загрузке модели, после pinEyes; свои персонажи (character.json) — не трогаем, у них свои глаза.
    /// Окрас (PetRoom.applyCoat) перекрашивает только шерсть 0 и 1 — глаза остаются.
    static func styleEyes(_ body: Entity) {
        var queue: [Entity] = [body]
        while !queue.isEmpty {
            let e = queue.removeFirst()
            queue += Array(e.children)
            guard let m = e as? ModelEntity, var model = m.model,
                  PetRoom.shibaMaterials.contains(model.materials.count), eyesByShape(m) else { continue }
            for (i, hex) in [(3, EyeStyle.rim), (4, EyeStyle.iris), (5, EyeStyle.pupil)] {
                guard var p = model.materials[i] as? PhysicallyBasedMaterial else { continue }
                p.baseColor = .init(tint: PetRoom.color(hex), texture: nil)
                model.materials[i] = p
            }
            m.model = model
        }
    }

    /// Глаза держатся головы (волна 32, EyePin): у вершин глаз и шерсти рядом вес ушей отходит Head — глаз больше
    /// не уезжает вверх под шерсть, когда клип или тап двигает уши. Звать при загрузке модели (PetModel.assemble),
    /// до rig и prepareCoat: веки (lidMesh) и развёртка шерсти берут уже новые веса. Не вышло — модель как была.
    static func pinEyes(_ body: Entity) {
        var queue: [Entity] = [body]
        while !queue.isEmpty {
            let e = queue.removeFirst()
            queue += Array(e.children)
            guard let m = e as? ModelEntity, !m.jointNames.isEmpty, let mats = m.model?.materials,
                  PetRoom.shibaMaterials.contains(mats.count) else { continue }
            let light = mats.map(Self.brightness)
            let byColor = light[0].flatMap { fur -> Bool? in
                guard let white = light[3], let pupil = light[4], let black = light[5] else { return nil }
                return looksLikeEyes(fur: fur, white: white, pupil: pupil, black: black)
            } ?? false
            // Волна 50: и по форме — окрас или своя раскраска глаз не должны оставлять глаз на ушах.
            guard byColor || eyesByShape(m) else { continue }
            pinEyes(m)
        }
    }

    private static func pinEyes(_ m: ModelEntity) {
        guard var model = m.model else { return }
        let mesh = model.mesh
        let contents = mesh.contents
        // Индексы влияний — в скелете части; нет его — порядок костей сущности.
        func names(_ part: MeshResource.Part) -> [String] {
            if let sid = part.skeletonID {
                for s in contents.skeletons where s.id == sid { return s.joints.map(\.name) }
            }
            return m.jointNames
        }
        // Кто тянет глаз с головы — EyePin.movingBones: уши под любым именем и прочее под головой, кроме лица.
        func bones(_ names: [String]) -> (moving: Set<Int>, head: Int)? {
            guard let head = PetModel.boneIndex(names, "Head"),
                  let moving = EyePin.movingBones(names, head: head) else { return nil }
            return (moving, head)
        }
        func weights(_ part: MeshResource.Part) -> [BoneWeight] {
            (part.jointInfluences?.influences.elements ?? []).map { BoneWeight(joint: $0.jointIndex, weight: $0.weight) }
        }
        var changed = false
        var models: [MeshResource.Model] = []
        for var mm in contents.models {
            // Глаза ищем в своей модели меша: у частей одной модели общая система координат.
            let eyeParts = mm.parts.filter { (3...5).contains($0.materialIndex) && $0.jointInfluences != nil }
            let need = eyeParts.contains { part in
                bones(names(part)).map { EyePin.needed(eyeInfluences: weights(part), moving: $0.moving) } ?? false
            }
            guard need, let eyes = EyePin.eyes(eyeParts.flatMap { $0.positions.elements }) else {
                models.append(mm)
                continue
            }
            var parts: [MeshResource.Part] = []
            for var part in mm.parts {
                // У JointInfluences нет геттера «влияний на вершину» — считаем по числу вершин.
                let verts = part.positions.elements.count
                if let ji = part.jointInfluences, verts > 0, ji.influences.elements.count % verts == 0,
                   let b = bones(names(part)),
                   let next = EyePin.pin(weights(part), perVertex: ji.influences.elements.count / verts,
                                         positions: part.positions.elements,
                                         eye: (3...5).contains(part.materialIndex), eyes: eyes,
                                         moving: b.moving, anchor: b.head) {
                    part.jointInfluences = MeshResource.JointInfluences(
                        influences: MeshBuffers.JointInfluences(
                            next.map { MeshJointInfluence(jointIndex: $0.joint, weight: $0.weight) }),
                        influencesPerVertex: ji.influences.elements.count / verts)
                    changed = true
                }
                parts.append(part)
            }
            mm.parts = MeshPartCollection(parts)
            models.append(mm)
        }
        guard changed else { return }
        if Env.isUITest { EyeProbe.pinned = true }
        var next = contents
        next.models = MeshModelCollection(models)
        let joints = m.jointNames.count
        do {
            try mesh.replace(with: next)
        } catch {
            // Не дал заменить на месте — новый меш с тем же содержимым (как PetRoom.prepareFurUV).
            guard let fresh = try? MeshResource.generate(from: next) else { return }
            model.mesh = fresh
            m.model = model
            if m.jointNames.count != joints {
                model.mesh = mesh
                m.model = model
            }
            return
        }
        if m.jointNames.count != joints { try? mesh.replace(with: contents) }
    }

    /// Подмножества 3…5 — глаза, а не часть шерсти: радужка и зрачок темнее шерсти, «белок» заметно отличается от неё.
    nonisolated static func looksLikeEyes(fur: CGFloat, white: CGFloat, pupil: CGFloat, black: CGFloat) -> Bool {
        pupil < fur && black < fur && abs(white - fur) > 0.1
    }

    private static func brightness(_ m: any Material) -> CGFloat? {
        guard let p = m as? PhysicallyBasedMaterial else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard p.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return r + g + b
    }

    /// Поворот шеи и головы вокруг вертикали сцены (взгляд), наклон набок вокруг оси морды, уши и хвост
    /// (TapWiggle). Анимация пишет кости каждый кадр — добавку кладём поверх её позы; если кость не перезаписали
    /// (стоит наша прошлая запись), берём прошлую основу, а не копим поворот. Оси считаются по позе клипа
    /// в системе модели и переводятся в систему каждой кости — не зависим от того, как экспорт повернул кости.
    func look(_ angle: Float, wiggle w: TapWiggle.Pose = .zero) {
        guard let m = skin, joints.count >= 2 else { return }
        // Рост держит кости каждый кадр (клип их перезаписывает), как и взгляд.
        let g = Self.growth.flatMap { Self.grown($0) ? $0 : nil }
        let moving = abs(angle) >= 1e-4 || abs(w.roll) >= 1e-5 || abs(w.ear) >= 1e-5
            || w.tail.contains { abs($0) >= 1e-5 } || g != nil
        if !moving && last.allSatisfy({ $0 == nil }) { return }
        var tr = m.jointTransforms
        guard tr.count == parents.count else { return }
        for k in joints.indices {
            let cur = tr[joints[k]].rotation
            if let l = last[k], Self.same(cur, l) { continue }
            base[k] = cur
        }
        if !moving {
            // Всё вернулось: кладём позу клипа и больше не пишем, пока снова не позовут.
            for k in joints.indices {
                tr[joints[k]].rotation = base[k]
                last[k] = nil
            }
            if let h = head { tr[h].scale = headScale }
            m.jointTransforms = tr
            return
        }
        var rot = tr.map(\.rotation)
        for k in joints.indices { rot[joints[k]] = base[k] }
        let up = simd_normalize(m.convert(direction: ChoreoPath.up, from: nil))
        // «Вперёд» — от головы к морде по позе клипа, без вертикальной части. Нет морды — без наклона и ушей.
        var fwd: SIMD3<Float>?
        // Уши щенка висят вперёд, хвост раскручен назад-вниз (доля от взрослого завитка).
        let droop = Float(g?.earDroop ?? 0) * 0.55
        let uncurl = Float(1 - (g?.tailCurl ?? 1)) * 0.35
        if let h = head, let n = snout, w.roll != 0 || w.ear != 0 || droop != 0 || uncurl != 0 {
            var pose = tr
            for j in joints { pose[j].rotation = rot[j] }
            let d = position(n, pose) - position(h, pose)
            let flat = d - simd_dot(d, up) * up
            if simd_length(flat) > 1e-6, flat.x.isFinite { fwd = simd_normalize(flat) }
        }
        // Поворот вокруг side = fwd × up ведёт вертикаль назад: уши прижимаются (+).
        let side = fwd.map { simd_normalize(simd_cross($0, up)) }
        let none = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        func spin(_ j: Int, _ axis: SIMD3<Float>, _ a: Float) -> simd_quatf {
            guard abs(a) >= 1e-6 else { return none }
            let local = simd_normalize(global(j, rot).inverse.act(axis))
            guard local.x.isFinite, local.y.isFinite, local.z.isFinite else { return none }
            return simd_quatf(angle: a, axis: local)
        }
        for k in joints.indices {
            let j = joints[k]
            var q = base[k]
            switch roles[k] {
            case .look(let share):
                q = q * spin(j, up, angle * share)
                if let f = fwd { q = q * spin(j, f, w.roll * share) }
            case .ear(let share):
                if let sd = side { q = q * spin(j, sd, (w.ear - droop) * share) }
            case .tail(let i):
                if uncurl != 0, let sd = side { q = q * spin(j, sd, uncurl) }
                if i < w.tail.count { q = q * spin(j, up, w.tail[i]) }
            }
            tr[j].rotation = q
            last[k] = q
        }
        // Голова щенка крупнее тела: масштаб кости Head (шапка и веки идут за ней — PetWear, setEyes).
        if let h = head { tr[h].scale = headScale * Float(g?.head ?? 1) }
        m.jointTransforms = tr
    }

    /// Шерсть перекрасили (PetRoom.applyCoat): веки берут новую шерсть (ModelComponent целиком, не подменой).
    func recolor(_ m: ModelEntity, _ mats: [any Material]) {
        guard let e = eyes, e === m, let l = lids, let mesh = l.model?.mesh,
              let lid = PetRoom.eyeLid(m, mats) else { return }
        l.components.set(ModelComponent(mesh: mesh, materials: [lid, Self.creaseMaterial]))
    }

    /// Каждый кадр после взгляда и челюсти: веки включены, пока глаз закрыт, и повторяют позу скелета.
    /// Блики — наоборот: видны, пока глаз открыт, и тогда же повторяют позу.
    func setEyes(closed shut: Bool) {
        if let e = eyes, let g = glints {
            if !shut { g.jointTransforms = e.jointTransforms }
            if g.isEnabled == shut { g.isEnabled = !shut }
        }
        guard let e = eyes, let l = lids else { return }
        if shut { l.jointTransforms = e.jointTransforms }
        guard shut != eyesClosed else { return }
        l.isEnabled = shut
        eyesClosed = shut
    }

    private func global(_ j: Int, _ rot: [simd_quatf]) -> simd_quatf {
        var q = rot[j]
        var p = parents[j]
        var n = 0
        while p >= 0 && n < 64 {
            q = rot[p] * q
            p = parents[p]
            n += 1
        }
        return q
    }

    private static func same(_ a: simd_quatf, _ b: simd_quatf) -> Bool {
        let d = a.vector - b.vector
        return max(abs(d.x), abs(d.y), abs(d.z), abs(d.w)) < 1e-5
    }

    // MARK: рост (волна 34 I)

    /// Вид отличим от взрослого: иначе кости не трогаем вовсе.
    private static func grown(_ g: GrowthLook) -> Bool {
        abs(g.head - 1) > 0.005 || g.earDroop > 0.005 || g.tailCurl < 0.995
    }

    /// Рост на сцене: размер обёртки (короткие лапы — чуть ниже по вертикали, морду выравнивает голова), пятно-тень
    /// и миска под размер, кости — в look. Надетое растёт само: оно на костях. nil — взрослый вид.
    static func setGrowth(_ look: GrowthLook?, on pet: Entity) {
        let s = Float(look?.scale ?? 1)
        let legs = Float(1 + ((look?.legs ?? 1) - 1) * 0.35)
        pet.scale = SIMD3<Float>(s, s * legs, s)
        if let blob = pet.parent?.children.first(where: { $0.name == "blobShadow" }) {
            blob.scale = SIMD3<Float>(Float(ChoreoPath.body.width) * s, 1, Float(ChoreoPath.body.length) * s)
        }
        PetChoreo.growth = s
        growth = look
    }

    /// Кадр лица: пружина взгляда, моргание, во сне глаза закрыты.
    static func step(_ pet: Entity, dt: Double) {
        guard var face = pet.components[PetFace.self] else { return }
        face.time += dt
        let goal = face.follow ?? face.target
        if face.still {
            face.angle = goal
            face.speed = 0
        } else if face.follow != nil {
            // За мячом — бодро, как раньше.
            (face.angle, face.speed) = PetSpring.step(x: face.angle, v: face.speed, target: goal,
                                                      omega: 10, zeta: 0.9, dt: Float(dt))
        } else {
            // К пальцу и обратно — мягко, с разгоном и без перелёта (волна 18).
            (face.angle, face.speed) = PetSpring.step(x: face.angle, v: face.speed, target: goal,
                                                      omega: SoftLook.omega, zeta: SoftLook.zeta, dt: Float(dt))
        }
        // Отклик на тап: наклон, уши, хвост. При Reduce Motion — ничего.
        if face.still { face.wiggle = TapWiggle() }
        let wiggle = face.still ? TapWiggle.Pose.zero : face.wiggle.step(dt: dt)
        var shut = false
        var blinked = false
        let smiling = !face.still && face.time < face.smileUntil
        let st = pet.components[ClipState.self]
        if let st, st.stance == .sleep, st.clock >= st.busyUntil - 0.4 {
            shut = true
        } else if face.bliss || smiling {
            // Гладят — жмурится от удовольствия; в ванне — довольная морда (волна 50, HappyFace).
            shut = true
        } else if !face.still {
            if face.time >= face.nextBlink {
                face.blinkUntil = face.time + 0.13
                // Иногда двойное моргание.
                face.nextBlink = face.time + (Double.random(in: 0..<1) < 0.2 ? 0.3 : Double.random(in: 2.5...6))
            }
            shut = face.time < face.blinkUntil
            blinked = shut
        }
        // Говорит, пока на экране реплика (моргание не мешает); во сне и при Reduce Motion — молчит.
        var jawGoal: Float = 0
        if let line = face.talk, !face.still, st?.stance != .sleep {
            jawGoal = JawTalk.angle(line, at: face.time - face.talkFrom)
        }
        if smiling { jawGoal = max(jawGoal, HappyFace.jaw) }
        if face.still {
            face.jaw = 0
            face.jawSpeed = 0
        } else {
            (face.jaw, face.jawSpeed) = PetSpring.step(x: face.jaw, v: face.jawSpeed, target: jawGoal,
                                                       omega: 28, zeta: 0.8, dt: Float(dt))
        }
        pet.components.set(face)
        guard let rig = rig(for: pet) else { return }
        if Env.isUITest { EyeProbe.frame(touched: face.time < face.touchUntil, shut: shut, blinked: blinked) }
        rig.look(face.angle, wiggle: wiggle)
        rig.talk(max(face.jaw, 0))
        rig.setEyes(closed: shut)
    }
}

// MARK: - Проба глаз для UI-тестов (волна 50)

/// Что видно на глазах: UI-тест «10 тапов подряд» читает это из скрытой подписи pet.eyes (HomeScreen).
/// Пишется только в UI-тестах (Env.isUITest).
@MainActor
enum EyeProbe {
    /// Глаза найдены (веки или блики собраны).
    static var eyes = false
    /// Сколько ушных костей взял отклик на тап (BoneName: «Ear1.L» → «Ear1_L»).
    static var ears = 0
    /// Веса глаз перевешены на голову (EyePin) в этом запуске.
    static var pinned = false
    /// Блики собраны (1) или нет (0).
    static var glints = 0
    /// Кадров всего и кадров «под пальцем» (EyeBlink.touchHold после касания).
    static var frames = 0
    static var touched = 0
    /// Кадров под пальцем, когда глаз закрыт обычным морганием — должно быть 0.
    static var blinkShut = 0
    /// Сколько раз под пальцем глаз закрылся-открылся (по любой причине, в том числе ласка).
    static var flips = 0
    private static var lastShut = false

    static func frame(touched t: Bool, shut: Bool, blinked: Bool) {
        frames += 1
        if t {
            touched += 1
            if blinked { blinkShut += 1 }
            if shut != lastShut { flips += 1 }
        }
        lastShut = shut
    }

    static var text: String {
        "eyes=\(eyes ? 1 : 0) ears=\(ears) pin=\(pinned ? 1 : 0) glints=\(glints) variant=\(EyeStyle.current.rawValue) "
            + "frames=\(frames) touched=\(touched) blinkShut=\(blinkShut) flips=\(flips)"
    }
}
