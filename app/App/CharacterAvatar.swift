// Аватар своего персонажа в шапке (волна 14). Свой avatar.png из пака — если есть. Нет — один раз снимаем
// морду модели вне экрана (SceneKit, SCNRenderer) и кладём снимок в папку пака (.avatar-snapshot.png):
// дальше шапка берёт его с диска. Новая установка пака подменяет папку целиком — снимок снимется заново.
// У Шибы аватара нет: там рисованная мордочка PetFaceView, она меняется с настроением.

#if canImport(SceneKit) && canImport(UIKit)
import Foundation
import ImageIO
import Metal
import SceneKit
import UIKit

enum CharacterAvatar {
    /// Сторона снимка в пикселях: в шапке круг 40 pt, на 3x — 120 px, с запасом.
    static let side: CGFloat = 192

    /// Готовая картинка: свой avatar.png или снимок из кэша. nil — снимать (image(for:)).
    static func cached(_ e: CharacterStore.Entry) -> UIImage? {
        guard let url = e.avatarURL else { return nil }
        return thumbnail(url)
    }

    /// Картинка для шапки: с диска, а если нет — снимок морды (в фоне) и запись в кэш пака.
    @MainActor
    static func image(for e: CharacterStore.Entry) async -> UIImage? {
        if let img = cached(e) { return img }
        guard e.ok, let model = e.modelURL else { return nil }
        let yaw = e.config?.yaw ?? 0
        let tint = e.config?.color.flatMap(CharacterPack.rgb)
        let out = e.avatarCacheURL
        let data = await Task.detached(priority: .utility) {
            render(model: model, yaw: yaw, tint: tint)
        }.value
        guard let data else { return nil }
        try? data.write(to: out, options: .atomic)
        return thumbnail(out)
    }

    /// Уменьшенная копия без раскрытия большой картинки целиком (avatar.png бывает 2048×2048).
    private static func thumbnail(_ url: URL) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Снимок морды: модель как в комнате (поворот yaw из character.json, морда к +z), камера спереди
    /// чуть сбоку и сверху, в кадре верхняя передняя часть рамки — голова. PNG с прозрачным фоном.
    static func render(model: URL, yaw: Double, tint: UInt32?) -> Data? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let scene = try? SCNScene(url: model, options: [.checkConsistency: false]) else { return nil }
        let turn = SCNNode()
        for c in scene.rootNode.childNodes {
            c.removeFromParentNode()
            turn.addChildNode(c)
        }
        turn.eulerAngles.y = Float(yaw * .pi / 180)
        scene.rootNode.addChildNode(turn)
        if let tint { recolor(turn, tint) }

        let (lo, hi) = scene.rootNode.boundingBox
        let h = hi.y - lo.y, w = hi.x - lo.x, l = hi.z - lo.z
        guard h > 0, h.isFinite, w.isFinite, l.isFinite else { return nil }
        // Голова — сверху и спереди. Кадр — верхние ~60% роста; у вытянутых (собака, кот) сдвигаем к морде.
        let frame = max(h * 0.62, min(w, h) * 0.9)
        let target = SCNVector3((lo.x + hi.x) / 2, lo.y + h * 0.72, hi.z - min(l * 0.22, h * 0.3))
        let reach = max(h, max(w, l)) * 3
        let aside: Float = 18 * .pi / 180, down: Float = 8 * .pi / 180
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Double(frame / 2)
        cam.zNear = Double(reach * 0.01)
        cam.zFar = Double(reach * 4)
        let eye = SCNNode()
        eye.camera = cam
        eye.position = SCNVector3(target.x + reach * sin(aside) * cos(down),
                                  target.y + reach * sin(down),
                                  target.z + reach * cos(aside) * cos(down))
        eye.look(at: target)
        scene.rootNode.addChildNode(eye)

        // Мягкий свет без теней: общий + ключ спереди-сверху.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.6, 0.4, 0)
        scene.rootNode.addChildNode(key)
        scene.background.contents = UIColor.clear

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = eye
        renderer.autoenablesDefaultLighting = false
        // Скелетная анимация не играет: модель в позе привязки (первый кадр), как на витрине.
        let img = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .multisampling4X)
        return img.pngData()
    }

    /// Цвет шерсти из character.json, как в комнате (PetRoom.recolorFur): первый материал каждой модели — шерсть.
    private static func recolor(_ root: SCNNode, _ rgb: UInt32) {
        let c = UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                        blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        root.enumerateHierarchy { node, _ in
            guard let g = node.geometry, let m = g.materials.first else { return }
            m.multiply.contents = c
        }
    }
}
#endif
