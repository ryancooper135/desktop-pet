// Аватар своего персонажа в шапке (волна 14). Свой avatar.png из пака — если есть. Нет — один раз снимаем
// морду модели вне экрана (SceneKit, SCNRenderer) и кладём снимок в папку пака (.avatar-snapshot.png):
// дальше шапка берёт его с диска. Новая установка пака подменяет папку целиком — снимок снимется заново;
// шапка узнаёт о переустановке в ту же папку по метке установки (CharacterStore.Entry.stamp, волна 15).
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
        let tint = e.config?.color.flatMap(CharacterPack.rgb)
        let head = e.config?.bones?.head?.trimmingCharacters(in: .whitespaces)
        let headBone = (head?.isEmpty ?? true) ? "Head" : head!
        let out = e.avatarCacheURL
        let data = await Task.detached(priority: .utility) {
            render(model: model, headBone: headBone, tint: tint)
        }.value
        guard let data else { return nil }
        // Пока снимали, пак переставили в ту же папку (метка установки другая): снимок старой модели
        // в новую папку не кладём — шапка снимет новую морду сама (ключ задачи в NameCard сменился).
        guard CharacterStore.stamp(of: e.folder) == e.stamp else { return nil }
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

    /// Снимок морды. Куда смотрит модель, по осям не угадать (SceneKit читает usdz не так, как RealityKit,
    /// у чужих паков свои оси), поэтому кадр строится от кости головы: камера стоит со стороны, куда голова
    /// вынесена от центра тела, чуть сбоку и сверху. Нет такой кости — верх рамки, камера спереди по +z.
    /// PNG с прозрачным фоном.
    static func render(model: URL, headBone: String, tint: UInt32?) -> Data? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let scene = try? SCNScene(url: model, options: [.checkConsistency: false]) else { return nil }
        let root = scene.rootNode
        if let tint { recolor(root, tint) }

        let (lo, hi) = root.boundingBox
        let h = hi.y - lo.y, w = hi.x - lo.x, l = hi.z - lo.z
        guard h > 0, h.isFinite, w.isFinite, l.isFinite else { return nil }
        let mid = SIMD3<Float>((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)

        var target: SIMD3<Float>
        var facing = SIMD3<Float>(0, 0, 1)
        var frame: Float
        if let head = bone(headBone, in: root) {
            let p = head.simdWorldPosition
            let flat = SIMD3<Float>(p.x - mid.x, 0, p.z - mid.z)
            if simd_length(flat) > h * 0.05 { facing = simd_normalize(flat) }
            // Кость головы — у затылка: морда впереди неё, уши выше.
            target = p + facing * (h * 0.08) + SIMD3<Float>(0, h * 0.03, 0)
            frame = h * 0.55
        } else {
            frame = max(h * 0.62, min(w, h) * 0.9)
            target = SIMD3<Float>(mid.x, lo.y + h * 0.72, hi.z - min(l * 0.22, h * 0.3))
        }

        let reach = max(h, max(w, l)) * 3
        let aside: Float = 18 * .pi / 180, down: Float = 8 * .pi / 180
        let across = SIMD3<Float>(facing.z, 0, -facing.x)
        let look = simd_normalize(facing * cos(aside) + across * sin(aside)) * cos(down) + SIMD3<Float>(0, sin(down), 0)
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Double(frame / 2)
        cam.zNear = Double(reach * 0.01)
        cam.zFar = Double(reach * 4)
        let eye = SCNNode()
        eye.camera = cam
        eye.simdPosition = target + look * reach
        eye.simdLook(at: target)
        root.addChildNode(eye)

        // Мягкий свет без теней: общий + ключ от камеры сверху-сбоку (едет вместе с камерой).
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        root.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.5, 0.35, 0)
        eye.addChildNode(key)
        scene.background.contents = UIColor.clear

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = eye
        renderer.autoenablesDefaultLighting = false
        // Скелетная анимация не играет: модель в позе привязки (первый кадр), как на витрине.
        let img = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .multisampling4X)
        return img.pngData()
    }

    /// Кость по имени: SceneKit называет суставы из usdz то коротко, то путём («…/Neck3/Head»).
    private static func bone(_ name: String, in root: SCNNode) -> SCNNode? {
        var found: SCNNode?
        root.enumerateHierarchy { node, stop in
            guard let n = node.name else { return }
            if n == name || n.hasSuffix("/" + name) {
                found = node
                stop.pointee = true
            }
        }
        return found
    }

    /// Цвет шерсти из character.json, как в комнате (PetRoom.recolorFur): у Шибы это материал Main
    /// (Main_Light — белые грудь и лапы — не трогаем), у остальных — светлые материалы. Цвет без текстуры
    /// заменяется (как tint в RealityKit), текстура домножается.
    private static func recolor(_ root: SCNNode, _ rgb: UInt32) {
        let c = UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                        blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        var all: [SCNMaterial] = []
        root.enumerateHierarchy { node, _ in
            for m in node.geometry?.materials ?? [] where !all.contains(where: { $0 === m }) { all.append(m) }
        }
        guard !all.isEmpty else { return }
        var fur = all.filter { $0.name == "Main" }
        if fur.isEmpty {
            fur = all.filter { m in
                guard let col = color(m.diffuse.contents) else { return false }
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                return col.getRed(&r, green: &g, blue: &b, alpha: &a) && r + g + b > 1.2
            }
        }
        if fur.isEmpty { fur = [all[0]] }
        for m in fur {
            if m.diffuse.contents == nil || color(m.diffuse.contents) != nil {
                m.diffuse.contents = c
            } else {
                m.multiply.contents = c
            }
        }
    }

    private static func color(_ contents: Any?) -> UIColor? {
        guard let contents else { return nil }
        if let c = contents as? UIColor { return c }
        if CFGetTypeID(contents as CFTypeRef) == CGColor.typeID { return UIColor(cgColor: contents as! CGColor) }
        return nil
    }
}
#endif
