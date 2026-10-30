// Глаза Шибы держатся головы (волна 32). Вадим: «глаза закатываются». Причина — в весах скина shiba.usdz:
// вершины глаз на 30–60% привязаны к костям ушей (Ear1/Ear2). Уши двигаются в клипах (ear_flick, sit, yawn, hop,
// сон) и в отклике на тап (TapWiggle, до 16° назад) — и глаз целиком уезжает по голове на четверть-половину
// своего размера, обычно вверх и под шерсть. Зрачок относительно белка почти не сдвигается: «закатывается» весь глаз.
// Лечим весами при загрузке: у глаз вес ушей отдаём Head, у шерсти рядом — плавно (внутри inner размеров глаза —
// целиком, дальше outer — как было). Глаз и шерсть вокруг двигаются с головой как одно целое; уши — как раньше.
// Чистая логика без RealityKit: меш правит PetRig.pinEyes (PetRig.swift), тесты — EyePinTests.

import Foundation

/// Влияние кости на вершину скина (как MeshJointInfluence в RealityKit).
struct BoneWeight: Equatable, Sendable {
    var joint: Int
    var weight: Float
}

enum EyePin {
    /// Ближе этого к центру глаза (в размерах глаза) вес ушей уходит голове целиком.
    static let inner: Float = 1.2
    /// Дальше этого — веса как в модели. Между — плавно (smoothstep).
    static let outer: Float = 2.0

    /// Где глаза: центры (по одному на глаз) и размер одного глаза (наибольшая сторона рамки).
    struct Eyes: Equatable, Sendable {
        var centers: [SIMD3<Float>]
        var size: Float
    }

    /// Глаза по вершинам глаз (белок, радужка, зрачок обоих глаз вместе): делим пополам по оси наибольшего
    /// разброса — глаза стоят рядом поперёк морды. nil — вершин нет или они в одной точке.
    static func eyes(_ points: [SIMD3<Float>]) -> Eyes? {
        guard let first = points.first else { return nil }
        var lo = first, hi = first
        for p in points {
            lo = pointwiseMin(lo, p)
            hi = pointwiseMax(hi, p)
        }
        let ext = hi - lo
        let axis = ext.x >= ext.y && ext.x >= ext.z ? 0 : (ext.y >= ext.z ? 1 : 2)
        let mid = (lo[axis] + hi[axis]) / 2
        var out: [SIMD3<Float>] = []
        var size: Float = 0
        for left in [true, false] {
            let side = points.filter { left ? $0[axis] < mid : $0[axis] >= mid }
            guard let f = side.first else { continue }
            var a = f, b = f
            for p in side {
                a = pointwiseMin(a, p)
                b = pointwiseMax(b, p)
            }
            out.append((a + b) / 2)
            let e = b - a
            size = max(size, e.x, e.y, e.z)
        }
        guard !out.isEmpty, size > 0, size.isFinite else { return nil }
        return Eyes(centers: out, size: size)
    }

    /// Какую долю веса ушей вершина сохраняет на расстоянии distance (в размерах глаза) от ближайшего глаза:
    /// 0 внутри inner, 1 за outer, между — монотонно и гладко.
    static func keep(distance d: Float) -> Float {
        guard d.isFinite else { return 1 }
        if d <= inner { return 0 }
        if d >= outer { return 1 }
        let t = (d - inner) / (outer - inner)
        return t * t * (3 - 2 * t)
    }

    /// Доля для вершины p: часть глаза — всегда 0, остальное — по расстоянию до ближайшего глаза.
    static func keep(at p: SIMD3<Float>, eye: Bool, eyes: Eyes) -> Float {
        if eye { return 0 }
        let d = eyes.centers.map { c -> Float in
            let v = p - c
            return (v * v).sum().squareRoot()
        }.min() ?? .infinity
        return keep(distance: d / eyes.size)
    }

    /// Вершина: веса костей moving умножаются на keep, снятое отходит anchor. Сумма весов, число влияний и
    /// неотрицательность сохраняются. Нет слота anchor — берём пустой (или обнулённый) слот, а если все заняты —
    /// самый лёгкий (его вес тоже отходит anchor).
    static func reweight(_ w: [BoneWeight], keep: Float, moving: Set<Int>, anchor: Int) -> [BoneWeight] {
        let k = min(max(keep.isFinite ? keep : 1, 0), 1)
        guard k < 1, !moving.contains(anchor) else { return w }
        var out = w
        var moved: Float = 0
        for i in out.indices where moving.contains(out[i].joint) && out[i].weight > 0 {
            let cut = out[i].weight * (1 - k)
            out[i].weight -= cut
            moved += cut
        }
        guard moved > 0 else { return w }
        if let i = out.firstIndex(where: { $0.joint == anchor && $0.weight > 0 })
            ?? out.firstIndex(where: { $0.joint == anchor }) {
            out[i].weight += moved
        } else if let i = out.indices.min(by: { out[$0].weight < out[$1].weight }) {
            out[i] = BoneWeight(joint: anchor, weight: out[i].weight + moved)
        }
        return out
    }

    /// Нужно ли править меш: у вершин глаз (их влияния) есть вес ушей. После правки — нет, поэтому второй раз
    /// тот же меш не трогаем (переходное кольцо иначе ослабло бы ещё раз).
    static func needed(eyeInfluences: [BoneWeight], moving: Set<Int>) -> Bool {
        eyeInfluences.contains { moving.contains($0.joint) && $0.weight > 1e-6 }
    }

    /// Весь буфер влияний части меша (perVertex подряд на вершину). nil — менять нечего (рядом с глазами нет
    /// весов ушей) или размеры не сходятся. Звать один раз на меш, после needed.
    static func pin(_ influences: [BoneWeight], perVertex: Int, positions: [SIMD3<Float>], eye: Bool,
                    eyes: Eyes, moving: Set<Int>, anchor: Int) -> [BoneWeight]? {
        guard perVertex > 0, influences.count == positions.count * perVertex, !moving.isEmpty,
              !moving.contains(anchor) else { return nil }
        var out = influences
        var changed = false
        for (v, p) in positions.enumerated() {
            let range = v * perVertex ..< (v + 1) * perVertex
            let slice = Array(influences[range])
            guard slice.contains(where: { moving.contains($0.joint) && $0.weight > 1e-6 }) else { continue }
            let k = keep(at: p, eye: eye, eyes: eyes)
            guard k < 1 else { continue }
            let next = reweight(slice, keep: k, moving: moving, anchor: anchor)
            if next != slice {
                out.replaceSubrange(range, with: next)
                changed = true
            }
        }
        return changed ? out : nil
    }

    // MARK: любая модель (волна 50)

    /// Похоже ли на пару глаз, по одной геометрии (без цвета): два центра, глаз мелкий по сравнению с моделью,
    /// глаза не слиплись и не разнесены на полмодели. extent — наибольшая сторона рамки всей модели.
    /// Нужно, когда цвет не подсказывает (свой окрас глаз, другая модель волны 58): закрепить глаза всё равно надо.
    static func plausible(_ eyes: Eyes, extent: Float) -> Bool {
        guard eyes.centers.count == 2, extent > 0, extent.isFinite, eyes.size > 0 else { return false }
        let d = eyes.centers[1] - eyes.centers[0]
        let gap = (d * d).sum().squareRoot()
        return eyes.size <= 0.1 * extent && gap >= eyes.size && gap <= 0.5 * extent
    }

    /// Какие кости тянут глаз с головы: уши (любое имя, начинающееся с «ear») и всё прочее под головой, кроме
    /// челюсти, языка, рта, век, бровей и самих глаз — они либо лицо, либо двигаются вместе с глазом намеренно.
    /// Имена — пути костей «…/Neck3/Head/Ear1_L». nil — головы нет или тянуть некому.
    static func movingBones(_ names: [String], head: Int) -> Set<Int>? {
        guard names.indices.contains(head) else { return nil }
        let face = ["jaw", "tongue", "mouth", "lip", "eye", "lid", "brow", "teeth", "nose"]
        var out = Set<Int>()
        for i in BoneName.descendants(names, of: head) {
            let leaf = BoneName.normalized(BoneName.leaf(names[i]))
            if leaf.hasPrefix("ear") { out.insert(i); continue }
            if face.contains(where: { leaf.contains($0) }) { continue }
            // Под ухом всё — ухо (кончик, серёжка).
            out.insert(i)
        }
        // Уши не под головой (бывает: прицеплены к шее).
        for (i, n) in names.enumerated() where BoneName.normalized(BoneName.leaf(n)).hasPrefix("ear") {
            out.insert(i)
        }
        out.remove(head)
        return out.isEmpty ? nil : out
    }
}
