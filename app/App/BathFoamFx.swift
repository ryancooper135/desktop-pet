// Пена, когда гладят в ванне (волна 50): «помогает мыть». Раскладка пузырей — BathFoam (Shared, тесты
// TouchFaceTests), здесь — только сущности. Пузыри — сферы в коде, без ассетов: белые с лёгким блеском,
// поднимаются, чуть растут и лопаются. Живут в контейнере под пивотом питомца, как шерстинки BrushFx.

import Foundation
import UIKit
@preconcurrency import RealityKit

@MainActor
enum BathFoamFx {
    static let containerName = "bathFoamFx"
    /// Цвет пены: тёплый белый, чтобы не спорил с бликом глаз (EyeStyle.glint).
    static let foam: UInt32 = 0xF7FBFF

    /// Пузыри ласки seed (номер реакции); side — где палец по экрану, -1…1.
    static func burst(on pet: Entity, seed: Int, side: Float) {
        let pivot = pet.children.first { $0.name == PetModel.pivotName } ?? pet
        let box: Entity
        if let found = pivot.children.first(where: { $0.name == containerName }) {
            box = found
        } else {
            box = Entity()
            box.name = containerName
            pivot.addChild(box)
        }
        let b = bounds(in: pivot)
        let half = b.extents / 2
        func point(_ f: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(b.center.x + f.x * half.x, b.min.y + f.y * b.extents.y, b.center.z + f.z * half.z)
        }
        let mat = SimpleMaterial(color: PetRoom.color(foam), roughness: 0.35, isMetallic: false)
        var made: [Entity] = []
        for bubble in BathFoam.bubbles(seed: seed, side: side) {
            let r = max(bubble.radius * b.extents.y, 0.004)
            let e = ModelEntity(mesh: .generateSphere(radius: r), materials: [mat])
            e.position = point(bubble.start)
            e.scale = SIMD3<Float>(repeating: 0.01)
            e.isEnabled = false
            box.addChild(e)
            made.append(e)
            let end = point(bubble.start + bubble.drift)
            Task { @MainActor [weak e] in
                try? await Task.sleep(for: .milliseconds(Int(bubble.delay * 1000)))
                guard let e, e.parent != nil else { return }
                e.isEnabled = true
                // Вспух за пятую часть жизни, потом плывёт вверх и чуть растёт; в конце — лопается (убираем).
                var grow = e.transform
                grow.scale = SIMD3<Float>(repeating: 0.85)
                _ = e.move(to: grow, relativeTo: box, duration: bubble.life * 0.2, timingFunction: .easeOut)
                try? await Task.sleep(for: .milliseconds(Int(bubble.life * 200)))
                guard e.parent != nil else { return }
                var to = e.transform
                to.translation = end
                to.scale = SIMD3<Float>(repeating: 1.1)
                _ = e.move(to: to, relativeTo: box, duration: bubble.life * 0.8, timingFunction: .easeInOut)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(BathFoam.total * 1000) + 50))
            for e in made { e.removeFromParent() }
        }
    }

    private static func bounds(in pivot: Entity) -> BoundingBox {
        let body = pivot.children.first { $0.name == PetModel.bodyName }
        let b = (body ?? pivot).visualBounds(relativeTo: pivot)
        if b.extents.y > 0 { return b }
        return BoundingBox(min: SIMD3<Float>(-0.1, 0, -0.22), max: SIMD3<Float>(0.1, 0.45, 0.3))
    }
}
