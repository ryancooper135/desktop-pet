// Миска и мячик комнаты из готовых моделей (волна 58): «Dog bowl» и «Tennis ball», Poly by Google, CC-BY 3.0
// (атрибуция — content/ASSETS_LICENSES.md и экран «Об игре»). Файлы — Resources/Pets/bowl.usdz и ball.usdz,
// собраны tools/assets/props_usdz.py: один меш без скелета, в метрах, центр в нуле, размер как у прежних
// примитивов (миска — радиус 0,09 и высота 0,05; мяч — радиус 0,05), поэтому позиции, хореография
// (PetChoreo по имени "bowl"/"ball"), корм в миске и столкновения (RoomPlan.Keep.ballRadius) не меняются.
// Грузим один раз до сборки комнаты (PetStage), берём только меш и материалы. Не загрузилось — примитивы как раньше.

import Foundation
@preconcurrency import RealityKit

@MainActor
enum PetProps {
    struct Prop {
        var mesh: MeshResource
        var materials: [any Material]
    }

    static let bowlResource = "bowl"
    static let ballResource = "ball"

    private(set) static var bowl: Prop?
    private(set) static var ball: Prop?
    private static var loading: Task<Void, Never>?

    /// Один раз за запуск: комната пересобирается при каждом показе сцены, а файлы те же.
    /// Два показа сцены разом ждут одну и ту же загрузку.
    static func load() async {
        if loading == nil {
            loading = Task { @MainActor in
                bowl = await prop(bowlResource)
                ball = await prop(ballResource)
            }
        }
        await loading?.value
    }

    /// Мячик комнаты в своих материалах (текстура теннисного мяча, матовая) — для сброса после мячика из капсулы.
    static func ballMaterials() -> [any Material] {
        ball?.materials ?? [PetRoom.matteMaterial(RoomColors.ball)]
    }

    private static func prop(_ name: String) async -> Prop? {
        guard let root = try? await Entity(named: name, in: .main),
              let model = firstModel(root)?.model else { return nil }
        let matte = model.materials.map { (m: any Material) -> any Material in
            guard var pbr = m as? PhysicallyBasedMaterial else { return m }
            pbr.roughness = .init(floatLiteral: 1)
            pbr.metallic = .init(floatLiteral: 0)
            pbr.specular = .init(floatLiteral: 0)
            return pbr
        }
        return Prop(mesh: model.mesh, materials: matte)
    }

    private static func firstModel(_ e: Entity) -> ModelEntity? {
        if let m = e as? ModelEntity, m.model != nil { return m }
        for c in e.children {
            if let m = firstModel(c) { return m }
        }
        return nil
    }
}
