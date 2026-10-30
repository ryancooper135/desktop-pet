// Живые глаза (волна 50). Были сплошь тёмные (style_a: «белок» #5A3B2A, радужка #3B2A22, зрачок #231B1E) —
// Вадим: «глаза мёртвые». Теперь: тёмный ободок, тёплая карая радужка, зрачок и белый блик поверх.
// Блик — не ассет, а меш из самих глаз (PetRig.glintMesh): копия диска глаза, уменьшенная и сдвинутая к краю,
// на тех же костях — двигается с головой, моргает вместе с глазом. Работает на любой модели с глазами-дисками.
// Вариант переключается одной строкой: EyeStyle.variant. Чистая логика без RealityKit, тесты — EyeStyleTests.

import Foundation

enum EyeStyle {
    enum Variant: String, CaseIterable, Sendable {
        /// Один крупный блик сверху слева.
        case a
        /// Два маленьких: крупнее сверху слева, совсем маленький снизу справа (по умолчанию: выбор Вадима 30.10).
        case b
    }

    /// Какой вариант в приложении. Переключать здесь.
    static let variant: Variant = .b

    /// Вариант для этого запуска: в UI-тестах можно PET_EYES=a|b (снимки обоих для Вадима), иначе — variant.
    static var current: Variant {
        guard Env.isUITest, let v = Env.value("PET_EYES").flatMap(Variant.init(rawValue:)) else { return variant }
        return v
    }

    // MARK: цвета (0xRRGGBB, sRGB)

    /// Ободок вокруг радужки (подмножество Eyes_White у Шибы): тёмный, чтобы глаз читался на рыжей шерсти.
    static let rim: UInt32 = 0x2A1D1A
    /// Радужка (Eyes_Pupil): тёплая карая.
    static let iris: UInt32 = 0x8E5A33
    /// Зрачок (Eyes_Black).
    static let pupil: UInt32 = 0x1A1214
    /// Блик: тёплый белый, без освещения (Unlit), чтобы не гас в тени.
    static let glint: UInt32 = 0xFFFDF7
    /// Шов закрытого глаза (веко): тёмная дуга, чтобы закрытый глаз читался закрытым, а не пропавшим.
    static let crease: UInt32 = 0x3A2620

    // MARK: блики

    /// Один блик: размер — доля размера глаза (диаметр диска), сдвиг от центра глаза — в размерах глаза,
    /// up вверх по экрану, left влево по экрану (у обоих глаз в одну сторону, как от одной лампы).
    struct Spot: Equatable, Sendable {
        var scale: Float
        var up: Float
        var left: Float
    }

    static func spots(_ v: Variant) -> [Spot] {
        switch v {
        case .a: return [Spot(scale: 0.36, up: 0.18, left: 0.14)]
        case .b: return [Spot(scale: 0.25, up: 0.2, left: 0.15), Spot(scale: 0.13, up: -0.18, left: -0.17)]
        }
    }

    /// Насколько блик впереди самой выпуклой точки глаза, в размерах глаза: поверх зрачка без мерцания,
    /// но глубже века (PetRig.lidMesh выталкивает веко дальше).
    static let lift: Float = 0.04

    /// Куда встаёт вершина p диска-источника (зрачок: он сплошной, белок и радужка у Шибы — кольца) при блике
    /// spot. Источник с центром source и размером sourceSize сплющиваем в плоскость глаза, уменьшаем до
    /// spot.scale размера глаза и ставим со сдвигом от центра глаза center. normal — наружу из глаза, up и left —
    /// единичные в плоскости глаза. top — насколько самая выпуклая точка глаза впереди center (по normal).
    static func place(_ p: SIMD3<Float>, source: SIMD3<Float>, sourceSize: Float, center c: SIMD3<Float>,
                      normal n: SIMD3<Float>, up: SIMD3<Float>, left: SIMD3<Float>, size: Float, top: Float,
                      spot: Spot) -> SIMD3<Float> {
        let d = p - source
        let flat = d - dot3(d, n) * n
        let k = sourceSize > 0 ? spot.scale * size / sourceSize : 0
        let at = c + (up * spot.up + left * spot.left) * size
        return at + flat * k + n * (top + lift * size)
    }

    /// Плоскость глаза: «вверх» сцены без составляющей вдоль нормали и «влево по экрану». Камера смотрит на морду
    /// навстречу нормали, поэтому влево по экрану — n × up. nil — нормаль вдоль вертикали (глаз смотрит вверх).
    static func axes(normal n: SIMD3<Float>, sceneUp: SIMD3<Float>) -> (up: SIMD3<Float>, left: SIMD3<Float>)? {
        let u = sceneUp - dot3(sceneUp, n) * n
        let lu = len3(u)
        guard lu > 1e-4, lu.isFinite else { return nil }
        let up = u / lu
        let l = cross3(n, up)
        let ll = len3(l)
        guard ll > 1e-4 else { return nil }
        return (up, l / ll)
    }

    // MARK: шов закрытого глаза

    /// Шов: диск, сплющенный по вертикали в тонкую дугу чуть ниже центра — спокойно закрытый глаз.
    /// width — доля ширины глаза, height — доля высоты, drop — сдвиг вниз в размерах глаза.
    static let creaseWidth: Float = 0.92
    static let creaseHeight: Float = 0.16
    static let creaseDrop: Float = 0.06

    /// Вершина шва: источник (как у place) растягиваем до ширины глаза и сплющиваем в тонкую дугу; встаёт
    /// на front впереди центра глаза (впереди века).
    static func creasePoint(_ p: SIMD3<Float>, source: SIMD3<Float>, sourceSize: Float, center c: SIMD3<Float>,
                            normal n: SIMD3<Float>, up: SIMD3<Float>, left: SIMD3<Float>, size: Float,
                            front: Float) -> SIMD3<Float> {
        let d = p - source
        let k = sourceSize > 0 ? size / sourceSize : 0
        let x = dot3(d, left) * k, y = dot3(d, up) * k
        // Края чуть выше середины — закрытое веко полумесяцем.
        let r = max(size / 2, 1e-9)
        let bow = (x / r) * (x / r) * 0.1 * size
        return c + left * (x * creaseWidth) + up * (y * creaseHeight - creaseDrop * size + bow) + n * front
    }

    // MARK: векторы (без simd: логика собирается и под Linux)

    static func dot3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { (a * b).sum() }
    static func len3(_ a: SIMD3<Float>) -> Float { dot3(a, a).squareRoot() }
    static func cross3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}
