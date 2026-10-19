// Тихий снимок 3D-сцены для «Открытки дня» (волна 10). Камеру телефона не трогаем: снимаем то, что рисует
// RealityView. Своего снимка у RealityView нет (iOS 18/26), поэтому по порядку:
//  1) ARView в иерархии окна — его snapshot (так RealityKit сам отдаёт кадр, без интерфейса);
//  2) вид с CAMetalLayer, в который рисует сцена, — drawHierarchy (на устройстве это кадр с экрана);
//  3) всё окно через drawHierarchy, обрезанное к середине сцены (там только пёс: кнопки и шапка выше и ниже).
// Пустой (одноцветный) кадр считается неудачей и уходит на следующий способ.
// Кадр обрезается к 4:3 вокруг места, где стоит Шиба, ужимается до 512 px и ложится JPEG в Paths.dir/photos.
// Когда снимать и что хранить — чистая логика PostcardPhotos (Shared), тут только пиксели и файлы.

import SwiftUI
import UIKit
@preconcurrency import RealityKit
@preconcurrency import PetCore

@MainActor
enum PostcardCamera {
    /// Где на сцене стоит Шиба по высоте (доля от верха): центр окна 4:3. Сцена во весь экран.
    static let petCenterY = 0.53
    /// Через сколько после действия снимать: реакция успевает начаться, пёс радуется.
    static let actionDelay: Double = 1.6
    /// Возвращение с прогулки: Шиба сначала входит в кадр.
    static let walkDelay: Double = 4.5

    /// Каким способом сняли последний кадр: ar / metal / window / fallback. Для UI-тестов и логов.
    private(set) static var lastSource = ""
    private static var busy = false
    private static let cache = NSCache<NSString, UIImage>()

    static var folder: URL { Paths.dir.appendingPathComponent(PostcardPhotos.folder, isDirectory: true) }
    static func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    /// Кадр открытки с диска (с кэшем). Нет файла — nil, открытка рисует заглушку.
    static func image(_ name: String?) -> UIImage? {
        guard let name, !name.isEmpty, !name.contains("/") else { return nil }
        if let img = cache.object(forKey: name as NSString) { return img }
        guard let data = try? Data(contentsOf: url(name)), let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }

    // MARK: удачный момент

    /// Удачный момент ухода: через delay, если сцена всё ещё на виду (ready) и правила дня разрешают, снять кадр.
    static func moment(_ kind: MomentKind, delay: Double, ready: @escaping @MainActor () -> Bool) {
        guard !Env.isUnitTest else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard ready(), !busy, UIApplication.shared.applicationState == .active else { return }
            let now = Clock.now()
            guard let f = try? PetStore.shared.read(), f.pet.alive,
                  PostcardPhotos.plan(f, kind: kind, now: now).shoots else { return }
            let day = DayKey.of(now, tzOffsetMin: f.owner.tzOffsetMin)
            let name = PostcardPhotos.fileName(day: day, t: now, kind: kind)
            guard await shoot(to: name) else { return }
            let s = PostcardShot(day: day, kind: kind.rawValue, t: now, score: PostcardPhotos.score(kind), file: name)
            let drop = (try? PetStore.shared.mutate { f in PostcardPhotos.commit(s, in: &f) }) ?? [name]
            delete(drop)
        }
    }

    /// Снять сцену и положить JPEG под именем name. false — не вышло (сцены нет, кадр пустой, диск).
    static func shoot(to name: String) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        guard let img = await capture(), let data = img.jpegData(compressionQuality: PostcardPhotos.jpegQuality) else {
            return false
        }
        Paths.ensureDir(folder)
        do {
            try data.write(to: url(name), options: .atomic)
            cache.setObject(img, forKey: name as NSString)
            return true
        } catch {
            return false
        }
    }

    // MARK: пиксели

    /// Кадр сцены 4:3, длинная сторона ≤ 512 px. nil — ни один способ не дал картинку.
    static func capture() async -> UIImage? {
        guard let window = keyWindow() else { return nil }
        if let ar: ARView = first(in: window), let img = await arSnapshot(ar), let out = frame(img, of: ar, in: window) {
            lastSource = "ar"
            return out
        }
        if let v = metalView(in: window), let img = draw(v), let out = frame(img, of: v, in: window) {
            lastSource = "metal"
            return out
        }
        if let img = draw(window), let out = frame(img, of: window, in: window) {
            lastSource = "window"
            return out
        }
        return nil
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.filter { $0.activationState == .foregroundActive }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? scenes.flatMap(\.windows).first
    }

    private static func first<T: UIView>(in v: UIView) -> T? {
        if let t = v as? T { return t }
        for s in v.subviews { if let t: T = first(in: s) { return t } }
        return nil
    }

    /// Самый большой видимый вид, в чьих слоях есть CAMetalLayer (туда рисует RealityView).
    private static func metalView(in root: UIView) -> UIView? {
        var best: UIView?
        var bestArea: CGFloat = 0
        func hasMetal(_ l: CALayer, depth: Int) -> Bool {
            if l is CAMetalLayer { return true }
            guard depth < 3 else { return false }
            return (l.sublayers ?? []).contains { hasMetal($0, depth: depth + 1) }
        }
        func walk(_ v: UIView) {
            if v.isHidden || v.alpha < 0.01 { return }
            if hasMetal(v.layer, depth: 0) {
                let a = v.bounds.width * v.bounds.height
                if a > bestArea { best = v; bestArea = a }
            }
            v.subviews.forEach(walk)
        }
        walk(root)
        return best
    }

    private static func arSnapshot(_ ar: ARView) async -> UIImage? {
        await withCheckedContinuation { (c: CheckedContinuation<UIImage?, Never>) in
            ar.snapshot(saveToHDR: false) { img in c.resume(returning: img) }
        }
    }

    private static func draw(_ v: UIView) -> UIImage? {
        guard v.bounds.width > 1, v.bounds.height > 1 else { return nil }
        let r = UIGraphicsImageRenderer(bounds: v.bounds)
        var ok = false
        let img = r.image { _ in ok = v.drawHierarchy(in: v.bounds, afterScreenUpdates: false) }
        return ok ? img : nil
    }

    /// Обрезать снимок вида v к 4:3 вокруг Шибы и ужать. Центр — по высоте окна (сцена во весь экран),
    /// пересчитанный в координаты вида. Пустой кадр — nil.
    private static func frame(_ img: UIImage, of v: UIView, in window: UIWindow) -> UIImage? {
        guard let cg = img.cgImage else { return nil }
        let w = Double(cg.width), h = Double(cg.height)
        let inView = v.convert(CGPoint(x: window.bounds.midX, y: window.bounds.height * petCenterY), from: window)
        let cy = v.bounds.height > 0 ? Double(inView.y / v.bounds.height) : petCenterY
        let r = PostcardPhotos.crop(width: w, height: h, centerY: min(1, max(0, cy)))
        guard r.w >= 32, r.h >= 24,
              let cut = cg.cropping(to: CGRect(x: r.x, y: r.y, width: r.w, height: r.h).integral),
              !isBlank(cut) else { return nil }
        let size = PostcardPhotos.fitted(width: Double(cut.width), height: Double(cut.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size.w, height: size.h), format: format).image { _ in
            UIImage(cgImage: cut).draw(in: CGRect(x: 0, y: 0, width: size.w, height: size.h))
        }
    }

    /// Почти одноцветная картинка (чёрная/белая/фон без сцены) — снимок не удался.
    static func isBlank(_ cg: CGImage) -> Bool {
        let n = 16
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard ok else { return true }
        var lo = 255.0, hi = 0.0, alpha = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let l = 0.3 * Double(px[i]) + 0.59 * Double(px[i + 1]) + 0.11 * Double(px[i + 2])
            lo = min(lo, l); hi = max(hi, l)
            alpha += Double(px[i + 3])
        }
        return hi - lo < 12 || alpha / Double(n * n) < 128
    }

    // MARK: уборка

    /// Удалить файлы кадров без ссылки из сейва (открытка пропала, выброшена, удалена из альбома).
    static func sweep() {
        guard let f = try? PetStore.shared.read() else { return }
        let live = PostcardPhotos.liveFiles(f)
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        var files: [String: Double] = [:]
        for n in names {
            let mtime = (try? fm.attributesOfItem(atPath: url(n).path)[.modificationDate] as? Date)?.timeIntervalSince1970
            files[n] = mtime ?? 0
        }
        // Время файлов — настоящее, не Clock.now(): в UI-тестах часы сдвинуты PET_NOW.
        delete(PostcardPhotos.orphans(files, live: live, now: Date().timeIntervalSince1970))
    }

    static func delete(_ names: [String]) {
        for n in names where !n.isEmpty && !n.contains("/") {
            cache.removeObject(forKey: n as NSString)
            try? FileManager.default.removeItem(at: url(n))
        }
    }

    // MARK: UI-тесты

    /// Сид postcard_photo: настоящий снимок сцены для вчерашней открытки. Не вышел — кадр-заглушка
    /// (мордочка на фоне сцены), источник «fallback» виден тесту.
    static func seedPhoto(for id: String) async {
        let name = "seed-\(id).jpg"
        var ok = false
        for _ in 0..<6 where !ok {
            ok = await shoot(to: name)
            if !ok { try? await Task.sleep(for: .seconds(1)) }
        }
        if !ok, let img = fallbackImage(), let data = img.jpegData(compressionQuality: PostcardPhotos.jpegQuality) {
            Paths.ensureDir(folder)
            ok = (try? data.write(to: url(name), options: .atomic)) != nil
            lastSource = "fallback"
        }
        guard ok else { return }
        _ = try? PetStore.shared.mutate { f in Postcards.setImage(name, for: id, in: &f) }
    }

    private static func fallbackImage() -> UIImage? {
        let view = ZStack {
            PetPalette.stageBg
            PetFaceView(pose: .happy).padding(40)
        }
        .frame(width: 512, height: 384)
        .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: view)
        r.scale = 1
        return r.uiImage
    }
}
