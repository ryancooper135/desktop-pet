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
        for (k, leaf) in ["Tail1", "Tail2", "Tail3"].enumerated() {
            if let j = find(leaf), !joints.contains(j) { joints.append(j); roles.append(.tail(k)) }
        }
        base = joints.map { m.jointTransforms[$0].rotation }
        last = joints.map { _ in nil }
        self.head = head
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
    /// Веко — шерсть плоским цветом (PetRoom.eyeLid): у текстурной шерсти tint почти белый, и глаз
    /// закрывался белым пятном (ui-55, ui-63 волны 15).
    private func setUpEyes(_ m: ModelEntity, _ mats: [any Material]) {
        guard let lid = PetRoom.eyeLid(m, mats) else { return }
        let light = mats.map(Self.brightness)
        guard let fur = Self.brightness(lid), let white = light[3], let pupil = light[4], let black = light[5],
              Self.looksLikeEyes(fur: fur, white: white, pupil: pupil, black: black),
              let mesh = Self.lidMesh(m) else { return }
        let e = ModelEntity(mesh: mesh, materials: [lid])
        guard e.jointNames == m.jointNames else { return }
        e.name = Self.lidsName
        e.isEnabled = false
        m.addChild(e)
        eyes = m
        lids = e
    }

    /// Меш век: части глаз (3…5) с теми же весами костей, сдвинутые по нормалям наружу на 3% размера глаз —
    /// поверх глаза без мерцания, кайма (Black) вокруг остаётся видна. nil — глаз нет или меш не собрался.
    private static func lidMesh(_ m: ModelEntity) -> MeshResource? {
        guard let contents = m.model?.mesh.contents else { return nil }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        var models: [MeshResource.Model] = []
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
            models[k].parts = MeshPartCollection(parts)
        }
        let ids = Set(models.map(\.id))
        var next = contents
        next.models = MeshModelCollection(models)
        next.instances = MeshInstanceCollection(contents.instances.filter { ids.contains($0.model) })
        return try? MeshResource.generate(from: next)
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
        let moving = abs(angle) >= 1e-4 || abs(w.roll) >= 1e-5 || abs(w.ear) >= 1e-5
            || w.tail.contains { abs($0) >= 1e-5 }
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
            m.jointTransforms = tr
            return
        }
        var rot = tr.map(\.rotation)
        for k in joints.indices { rot[joints[k]] = base[k] }
        let up = simd_normalize(m.convert(direction: ChoreoPath.up, from: nil))
        // «Вперёд» — от головы к морде по позе клипа, без вертикальной части. Нет морды — без наклона и ушей.
        var fwd: SIMD3<Float>?
        if let h = head, let n = snout, w.roll != 0 || w.ear != 0 {
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
                if let sd = side { q = q * spin(j, sd, w.ear * share) }
            case .tail(let i):
                if i < w.tail.count { q = q * spin(j, up, w.tail[i]) }
            }
            tr[j].rotation = q
            last[k] = q
        }
        m.jointTransforms = tr
    }

    /// Шерсть перекрасили (PetRoom.applyCoat): веки берут новую шерсть (ModelComponent целиком, не подменой).
    func recolor(_ m: ModelEntity, _ mats: [any Material]) {
        guard let e = eyes, e === m, let l = lids, let mesh = l.model?.mesh,
              let lid = PetRoom.eyeLid(m, mats) else { return }
        l.components.set(ModelComponent(mesh: mesh, materials: [lid]))
    }

    /// Каждый кадр после взгляда и челюсти: веки включены, пока глаз закрыт, и повторяют позу скелета.
    func setEyes(closed shut: Bool) {
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
        let st = pet.components[ClipState.self]
        if let st, st.stance == .sleep, st.clock >= st.busyUntil - 0.4 {
            shut = true
        } else if face.bliss {
            // Гладят — жмурится от удовольствия.
            shut = true
        } else if !face.still {
            if face.time >= face.nextBlink {
                face.blinkUntil = face.time + 0.13
                // Иногда двойное моргание.
                face.nextBlink = face.time + (Double.random(in: 0..<1) < 0.2 ? 0.3 : Double.random(in: 2.5...6))
            }
            shut = face.time < face.blinkUntil
        }
        // Говорит, пока на экране реплика (моргание не мешает); во сне и при Reduce Motion — молчит.
        var jawGoal: Float = 0
        if let line = face.talk, !face.still, st?.stance != .sleep {
            jawGoal = JawTalk.angle(line, at: face.time - face.talkFrom)
        }
        if face.still {
            face.jaw = 0
            face.jawSpeed = 0
        } else {
            (face.jaw, face.jawSpeed) = PetSpring.step(x: face.jaw, v: face.jawSpeed, target: jawGoal,
                                                       omega: 28, zeta: 0.8, dt: Float(dt))
        }
        pet.components.set(face)
        guard let rig = rig(for: pet) else { return }
        rig.look(face.angle, wiggle: wiggle)
        rig.talk(max(face.jaw, 0))
        rig.setEyes(closed: shut)
    }
}
