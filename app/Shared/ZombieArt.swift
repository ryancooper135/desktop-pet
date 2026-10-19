// Картинка «Щенка против зомби» (волна 13, стиль C): коридор старого особняка в тумане, Шиба спиной к нам,
// ковыляющие зомби с большими головами, летящие игрушки. Всё из коробок и пирамидок прямо в коде, без ассетов;
// рисует RetroRaster (низкое разрешение, дрожание вершин, аффинный пол, туман, дизеринг).
// Палитра нарочно не страшная: мятно-кремовая шахматка, вишнёвые обои в полоску, тёплые лампы,
// пастельно-зелёные зомби в цветных футболках. Туман сиреневый — светлый мир остаётся за дверью.

import Foundation

enum ZombieArt {
    // MARK: палитра

    static let fogColor = RVec.hex(0x2A1D3D)
    static let skyTop = RVec.hex(0x1A1228)
    static let fur = RVec.hex(0xE8954A)
    static let cream = RVec.hex(0xF7E6CC)
    static let dark = RVec.hex(0x2B1D18)
    static let pink = RVec.hex(0xFF6FA0)
    static let skin = RVec.hex(0x9BD68A)
    static let skinDark = RVec.hex(0x76B266)
    static let eyeWhite = RVec.hex(0xF5F5EE)
    static let pupil = RVec.hex(0x1A1A22)

    /// Стены коридора по x.
    static let wall = 1.75
    static let ceiling = 2.7

    static let fog = RetroFog(color: fogColor, start: 6, end: 23)
    static let light = RetroLight(dir: RVec(-0.4, 1, -0.6).normalized, ambient: 0.58, diffuse: 0.48)

    /// Сколько точек в ширину у кадра: PS1-зерно на телефоне.
    static let width = 176

    /// Высота кадра под соотношение сторон экрана.
    static func height(for aspect: Double) -> Int {
        Swift.max(120, Swift.min(520, Int((Double(width) * aspect).rounded())))
    }

    // MARK: коридор

    static let corridor: RetroMesh = {
        var m = RetroMesh()
        let z0 = -6.0, z1 = 26.0
        let floorA = RVec.hex(0x9ED9BE), floorB = RVec.hex(0xF0E2C4)
        // Пол плитками 2×1,75: на длинных треугольниках аффинная шахматка «плывёт», как на PS1.
        var z = z0
        while z < z1 {
            for (xa, xb) in [(-wall, 0.0), (0.0, wall)] {
                let p0 = RVec(xa, 0, z), p1 = RVec(xb, 0, z), p2 = RVec(xb, 0, z + 2), p3 = RVec(xa, 0, z + 2)
                func uv(_ p: RVec) -> RVec { RVec(p.x * 2 + 8, p.z * 2 + 40, 0) }
                m.quad(p0, p1, p2, p3, normal: RVec(0, 1, 0), floorA, color2: floorB, pattern: .checker,
                       uv: (uv(p0), uv(p1), uv(p2), uv(p3)))
            }
            z += 2
        }
        let paperA = RVec.hex(0x9C3D5C), paperB = RVec.hex(0xB9587A)
        let wood = RVec.hex(0x6E4A36), rail = RVec.hex(0x3F2A20)
        let rim = 0.78
        for side in [-1.0, 1.0] {
            let x = side * wall
            let n = RVec(-side, 0, 0)
            var z = z0
            while z < z1 {
                let za = z, zb = z + 2
                func uvz(_ zz: Double) -> RVec { RVec(zz * 3 + 60, 0, 0) }
                m.quad(RVec(x, rim, za), RVec(x, rim, zb), RVec(x, ceiling, zb), RVec(x, ceiling, za), normal: n,
                       paperA, color2: paperB, pattern: .stripes, uv: (uvz(za), uvz(zb), uvz(zb), uvz(za)))
                m.quad(RVec(x, 0, za), RVec(x, 0, zb), RVec(x, rim, zb), RVec(x, rim, za), normal: n, wood)
                z += 2
            }
            // Перила-плинтус посередине стены.
            m.add(.box(RVec(0.08, 0.07, z1 - z0), at: RVec(x - side * 0.04, rim, (z0 + z1) / 2), rail))
        }
        // Торец коридора: он целиком в тумане, но без него в конце виден фон.
        m.quad(RVec(-wall, 0, z1), RVec(wall, 0, z1), RVec(wall, ceiling, z1), RVec(-wall, ceiling, z1),
               normal: RVec(0, 0, -1), RVec.hex(0x3A2C48))
        // Потолок и лампы.
        m.quad(RVec(-wall, ceiling, z0), RVec(wall, ceiling, z0), RVec(wall, ceiling, z1), RVec(-wall, ceiling, z1),
               normal: RVec(0, -1, 0), RVec.hex(0x3A2C48))
        var lz = 4.0
        while lz < z1 {
            m.add(.box(RVec(0.5, 0.08, 0.5), at: RVec(0, ceiling - 0.04, lz), RVec.hex(0xFFE7A3), unlit: true))
            lz += 5
        }
        // Двери и портреты собак в рамках — через раз по сторонам.
        var dz = 2.5, k = 0
        while dz < z1 - 2 {
            let side: Double = k % 2 == 0 ? -1 : 1
            let x = side * (wall - 0.03)
            m.add(.box(RVec(0.06, 1.95, 1.0), at: RVec(x, 0.975, dz), RVec.hex(0x3B2418)))
            m.add(.box(RVec(0.06, 1.8, 0.82), at: RVec(x - side * 0.02, 0.92, dz), RVec.hex(0x7A4B2E)))
            m.add(.box(RVec(0.06, 0.08, 0.08), at: RVec(x - side * 0.06, 0.95, dz + 0.28), RVec.hex(0xF2C14E)))
            // Портрет напротив: рыжий «Шиба» на голубом в золотой раме.
            let px = -side * (wall - 0.03)
            let pz = dz + 1.6
            m.add(.box(RVec(0.05, 0.7, 0.6), at: RVec(px, 1.65, pz), RVec.hex(0xD9A93E)))
            m.add(.box(RVec(0.05, 0.56, 0.46), at: RVec(px + side * 0.02, 1.65, pz), RVec.hex(0x8FB8DE)))
            m.add(.box(RVec(0.05, 0.22, 0.22), at: RVec(px + side * 0.04, 1.6, pz), fur))
            m.add(.box(RVec(0.05, 0.08, 0.06), at: RVec(px + side * 0.04, 1.75, pz - 0.07), fur))
            m.add(.box(RVec(0.05, 0.08, 0.06), at: RVec(px + side * 0.04, 1.75, pz + 0.07), fur))
            dz += 6.5
            k += 1
        }
        return m
    }()

    // MARK: Шиба (смотрит на +z)

    static let shibaBody: RetroMesh = {
        var m = RetroMesh()
        m.add(.box(RVec(0.36, 0.3, 0.6), at: RVec(0, 0.42, 0), fur, top: fur))
        m.add(.box(RVec(0.3, 0.2, 0.06), at: RVec(0, 0.41, 0.3), cream))
        // Светлые «штанишки» сзади — Шибу узнают и со спины.
        m.add(.box(RVec(0.24, 0.13, 0.04), at: RVec(0, 0.34, -0.3), cream))
        for (x, z) in [(-0.12, 0.2), (0.12, 0.2), (-0.12, -0.2), (0.12, -0.2)] {
            m.add(.box(RVec(0.1, 0.16, 0.1), at: RVec(x, 0.2, z), fur))
            m.add(.box(RVec(0.1, 0.12, 0.1), at: RVec(x, 0.06, z), cream))
        }
        return m
    }()

    /// Голова отдельно: кивает при броске и задирается при лае. Опора — шея (0, 0.6, 0.22).
    static let shibaHead: RetroMesh = {
        var m = RetroMesh()
        let o = RVec(0, -0.6, -0.22)
        m.add(.box(RVec(0.38, 0.34, 0.34), at: RVec(0, 0.72, 0.32) + o, fur))
        m.add(.box(RVec(0.22, 0.14, 0.14), at: RVec(0, 0.65, 0.54) + o, cream))
        m.add(.box(RVec(0.3, 0.08, 0.04), at: RVec(0, 0.6, 0.49) + o, cream))
        m.add(.box(RVec(0.08, 0.05, 0.04), at: RVec(0, 0.7, 0.62) + o, dark))
        for side in [-1.0, 1.0] {
            m.add(.box(RVec(0.06, 0.07, 0.03), at: RVec(side * 0.1, 0.77, 0.495) + o, dark))
            m.add(.box(RVec(0.02, 0.02, 0.02), at: RVec(side * 0.1 - 0.015, 0.79, 0.512) + o, .one, unlit: true))
            m.add(.box(RVec(0.06, 0.03, 0.03), at: RVec(side * 0.1, 0.835, 0.495) + o, cream))
            m.add(.pyramid(RVec(0.13, 0.17, 0.12), at: RVec(side * 0.12, 0.885, 0.3) + o, fur,
                           tip: RVec(side * 0.03, 0, 0)))
            m.add(.pyramid(RVec(0.07, 0.11, 0.03), at: RVec(side * 0.12, 0.89, 0.37) + o, cream,
                           tip: RVec(side * 0.02, 0, -0.01)))
        }
        return m
    }()

    static let shibaTongue = RetroMesh.box(RVec(0.08, 0.025, 0.08), at: RVec(0, 0.57 - 0.6, 0.6 - 0.22), RVec.hex(0xF27C8C))

    /// Хвост-бублик. Опора — круп (0, 0.55, −0.28), виляет креном.
    static let shibaTail: RetroMesh = {
        var m = RetroMesh()
        m.add(.box(RVec(0.11, 0.2, 0.11), at: RVec(0, 0.08, -0.02), fur))
        m.add(.box(RVec(0.11, 0.11, 0.16), at: RVec(0, 0.2, 0.05), fur, top: cream))
        m.add(.box(RVec(0.1, 0.09, 0.08), at: RVec(0, 0.15, 0.14), cream))
        return m
    }()

    // MARK: зомби (смотрит на −z)

    static func zombieShirt(_ kind: ZombieKind) -> RVec {
        switch kind {
        case .walker: return RVec.hex(0x8C6BC2)
        case .small: return RVec.hex(0xF2B94B)
        case .big: return RVec.hex(0xC2506A)
        }
    }

    static let zombieBodies: [RetroMesh] = ZombieKind.allCases.map { kind in
        var m = RetroMesh()
        let pants = RVec.hex(0x4A5A8C)
        let shirt = zombieShirt(kind)
        for side in [-1.0, 1.0] {
            m.add(.box(RVec(0.15, 0.42, 0.17), at: RVec(side * 0.11, 0.21, 0), pants))
            m.add(.box(RVec(0.17, 0.07, 0.24), at: RVec(side * 0.11, 0.035, -0.04), RVec.hex(0x3A2A2A)))
        }
        m.add(.box(RVec(0.48, 0.44, 0.28), at: RVec(0, 0.64, 0), shirt))
        // Дырка на футболке — пятно другого цвета, и заплатка.
        m.add(.box(RVec(0.12, 0.1, 0.02), at: RVec(0.1, 0.56, -0.145), skinDark))
        m.add(.box(RVec(0.1, 0.1, 0.02), at: RVec(-0.12, 0.72, -0.145), shirt.mix(.one, 0.35)))
        // Большая голова.
        m.add(.box(RVec(0.56, 0.5, 0.48), at: RVec(0, 1.12, 0), skin, top: skinDark))
        // Глаза разные: один большой с точкой-зрачком, другой маленький.
        m.add(.box(RVec(0.17, 0.17, 0.03), at: RVec(-0.12, 1.16, -0.25), eyeWhite))
        m.add(.box(RVec(0.07, 0.07, 0.02), at: RVec(-0.1, 1.14, -0.27), pupil))
        m.add(.box(RVec(0.08, 0.08, 0.03), at: RVec(0.14, 1.18, -0.25), pupil))
        // Рот с одним зубом.
        m.add(.box(RVec(0.2, 0.05, 0.02), at: RVec(0.02, 0.99, -0.25), RVec.hex(0x3A1F2A)))
        m.add(.box(RVec(0.05, 0.05, 0.02), at: RVec(0.06, 0.975, -0.265), eyeWhite))
        // Румянец — они же милые.
        m.add(.box(RVec(0.08, 0.04, 0.02), at: RVec(-0.2, 1.04, -0.25), RVec.hex(0xE58A9A)))
        m.add(.box(RVec(0.08, 0.04, 0.02), at: RVec(0.22, 1.06, -0.25), RVec.hex(0xE58A9A)))
        switch kind {
        case .walker:
            // Хохолок.
            m.add(.pyramid(RVec(0.12, 0.16, 0.12), at: RVec(0.06, 1.37, 0.02), RVec.hex(0x3E6B3A), tip: RVec(0.05, 0, 0)))
        case .small:
            // Кепка с пропеллером.
            m.add(.box(RVec(0.5, 0.12, 0.44), at: RVec(0, 1.42, 0.02), RVec.hex(0xE0473F), top: RVec.hex(0x3D7FD9)))
            m.add(.box(RVec(0.3, 0.04, 0.16), at: RVec(0, 1.37, -0.26), RVec.hex(0xE0473F)))
            m.add(.box(RVec(0.04, 0.1, 0.04), at: RVec(0, 1.53, 0.02), RVec.hex(0xF2C14E)))
        case .big:
            // Бинт через лоб.
            m.add(.box(RVec(0.58, 0.07, 0.5), at: RVec(0, 1.27, 0), eyeWhite))
        }
        return m
    }

    /// Пропеллер мелкого — крутится отдельно. Опора — макушка кепки.
    static let propeller: RetroMesh = .box(RVec(0.42, 0.02, 0.07), at: RVec(0, 0, 0), RVec.hex(0x56C26B))

    /// Руки вперёд (рукав, рука, кисть), опора — плечи (0, 0.8, 0).
    static let zombieArmsSleeve: [RetroMesh] = ZombieKind.allCases.map { kind in
        var m = RetroMesh()
        for side in [-1.0, 1.0] {
            m.add(.box(RVec(0.12, 0.12, 0.2), at: RVec(side * 0.29, 0, -0.08), zombieShirt(kind)))
            m.add(.box(RVec(0.1, 0.1, 0.24), at: RVec(side * 0.29, 0, -0.3), skin))
            m.add(.box(RVec(0.13, 0.12, 0.12), at: RVec(side * 0.29, 0, -0.46), skinDark))
        }
        return m
    }

    static let shadow = RetroMesh.disc(0.32, 0.26, RVec.hex(0x4A5868))
    static let heart = RetroMesh.heart(0.11, pink)
    static let star: RetroMesh = .box(RVec(0.07, 0.07, 0.07), at: .zero, RVec.hex(0xFFE26B), unlit: true)

    // MARK: игрушки

    static let toys: [RetroMesh] = ZombieToy.allCases.map { kind in
        switch kind {
        case .ball:
            return .ball(0.12, RVec.hex(0xE8463C), stripe: RVec.hex(0xF7F2E8))
        case .bone:
            var m = RetroMesh.box(RVec(0.08, 0.07, 0.24), at: .zero, RVec.hex(0xF4EEDD))
            for (x, z) in [(-0.05, -0.13), (0.05, -0.13), (-0.05, 0.13), (0.05, 0.13)] {
                m.add(.box(RVec(0.08, 0.08, 0.08), at: RVec(x, 0, z), RVec.hex(0xF4EEDD)))
            }
            return m
        case .duck:
            var m = RetroMesh.box(RVec(0.2, 0.14, 0.24), at: .zero, RVec.hex(0xFFD93B))
            m.add(.box(RVec(0.13, 0.13, 0.12), at: RVec(0, 0.12, -0.08), RVec.hex(0xFFD93B)))
            m.add(.box(RVec(0.08, 0.04, 0.07), at: RVec(0, 0.11, -0.17), RVec.hex(0xF28C28)))
            m.add(.box(RVec(0.03, 0.03, 0.02), at: RVec(0.04, 0.15, -0.14), pupil))
            m.add(.box(RVec(0.03, 0.03, 0.02), at: RVec(-0.04, 0.15, -0.14), pupil))
            return m
        }
    }

    // MARK: кадр игры

    /// Камера за спиной Шибы, чуть сверху; при обнимашках кадр трясётся.
    static func camera(_ r: ZombieRound) -> RetroCamera {
        let px = r.puppyX
        var eye = RVec(px * 0.6, 1.45, -2.6)
        let shake = r.t - r.hugT
        if shake >= 0, shake < 0.35 {
            eye.x += sin(shake * 70) * 0.07 * (1 - shake / 0.35)
            eye.y += cos(shake * 55) * 0.04 * (1 - shake / 0.35)
        }
        return RetroCamera(eye: eye, target: RVec(px * 0.3, 0.8, 6), fovY: 0.98)
    }

    static func render(_ r: ZombieRound, into c: inout RetroCanvas) {
        c.fog = fog
        c.light = light
        c.begin(camera(r), top: skyTop, bottom: fogColor)
        c.draw(corridor)
        drawPuppy(&c, x: r.puppyX, t: r.t, facingCamera: false, barkAge: r.t - r.barkT,
                  throwAge: (r.t - 0.35).truncatingRemainder(dividingBy: ZombieRound.throwEvery), happy: false)
        for zb in r.zombies { drawZombie(&c, zb, t: r.t) }
        for toy in r.toys {
            let fly = Swift.min(1, (toy.z - toy.fromZ) / ZombieRound.toyRange)
            let y = 0.45 + 0.55 * sin(fly * .pi) - 0.3 * fly
            c.draw(toys[toy.kind.rawValue], [RetroPose(RVec(toy.x, y, toy.z), yaw: r.t * 9 + Double(toy.id), pitch: r.t * 5)])
            c.draw(shadow, [RetroPose(RVec(toy.x, 0, toy.z), scale: RVec(0.35, 1, 0.35))])
        }
    }

    // MARK: постер (карточка «Играть» и итог)

    /// Мем-кадр: Шиба смотрит на нас, за спиной в тумане бредут зомби. happy — итог: зомби стали друзьями,
    /// стоят рядом с игрушками и сердечками, Шиба высунул язык.
    static func poster(into c: inout RetroCanvas, happy: Bool, t: Double = 0.4) {
        c.fog = RetroFog(color: fogColor, start: 2.6, end: 13)
        c.light = light
        c.begin(RetroCamera(eye: RVec(0.25, 0.78, -1.75), target: RVec(-0.05, 0.85, 4), fovY: 1.05), top: skyTop, bottom: fogColor)
        c.draw(corridor)
        drawPuppy(&c, x: 0, t: t, facingCamera: true, barkAge: happy ? 0.12 : 10, throwAge: 1, happy: happy)
        let spots: [(Double, Double, ZombieKind, Double)] = happy
            ? [(-0.95, 1.5, .walker, 0.1), (0.9, 2.1, .big, 0.6), (-0.25, 3.4, .small, 0.3), (0.55, 5.6, .walker, 0.8)]
            : [(-0.7, 2.4, .walker, 0.1), (0.85, 3.6, .big, 0.6), (0.05, 5.4, .small, 0.3), (-0.95, 7.5, .walker, 0.8),
               (0.9, 9.5, .walker, 0.45)]
        for (i, s) in spots.enumerated() {
            var zb = Zombie(id: i, kind: s.2, x: s.0, z: s.1, baseX: s.0, hp: 1, wobble: s.3)
            zb.walked = t * 1.7 + s.3 * 3
            if happy {
                zb.state = .friend(since: t - 0.3 - Double(i) * 0.2)
                zb.toy = ZombieToy.allCases[i % 3]
            }
            drawZombie(&c, zb, t: t, lookAt: happy ? RVec(0, 0, 0) : nil)
        }
    }

    // MARK: части

    static func drawPuppy(_ c: inout RetroCanvas, x: Double, t: Double, facingCamera: Bool, barkAge: Double,
                          throwAge: Double, happy: Bool) {
        let yaw = facingCamera ? Double.pi : 0
        let bark = barkAge >= 0 && barkAge < 0.45
        let hop = bark ? sin(barkAge / 0.45 * .pi) * 0.16 : abs(sin(t * 7)) * 0.015
        let body = RetroPose(RVec(x, hop, 0), yaw: yaw)
        c.draw(shadow, [RetroPose(RVec(x, 0, 0), scale: RVec(0.85, 1, 1.1))])
        c.draw(shibaBody, [body])
        // Кивок при броске, задранная голова при лае.
        let nod = throwAge < 0.15 ? -sin(throwAge / 0.15 * .pi) * 0.25 : 0
        let headPitch = bark ? 0.45 : nod
        let tilt = happy ? 0.18 : sin(t * 1.3) * 0.05
        let head = RetroPose(RVec(0, 0.6, 0.22), pitch: headPitch, roll: tilt)
        c.draw(shibaHead, [head, body])
        if happy || bark { c.draw(shibaTongue, [head, body]) }
        let wag = sin(t * (happy ? 22 : 12)) * 0.45
        c.draw(shibaTail, [RetroPose(RVec(0, 0.55, -0.28), pitch: 0.25, roll: wag), body])
    }

    static func drawZombie(_ c: inout RetroCanvas, _ zb: Zombie, t: Double, lookAt: RVec? = nil) {
        let size = zb.kind.size
        let phase = zb.walked * 3.2 + zb.wobble * 6.283
        var roll = sin(phase) * 0.12
        var bob = abs(sin(phase)) * 0.05
        var yaw = sin(phase * 0.5) * 0.12
        var armPitch = sin(phase) * 0.08
        var hearts = 0.0
        var leaving = false
        switch zb.state {
        case .walking:
            break
        case .stunned:
            roll = sin(t * 9 + zb.wobble * 6) * 0.2
            bob = 0
            armPitch = 0.5
        case .friend(let since), .hug(let since):
            let age = t - since
            hearts = age
            armPitch = -0.75
            roll = sin(t * 6 + zb.wobble * 6) * 0.08
            bob = abs(sin(t * 8)) * 0.06
            if age > ZombieRound.friendStay {
                leaving = true
                yaw = (zb.x >= 0 ? -1 : 1) * 1.2
                roll = sin(zb.walked * 6) * 0.14
            }
        }
        if let lookAt { yaw = atan2(-(lookAt.x - zb.x), -(lookAt.z - zb.z)) * 0.6 + sin(t + zb.wobble) * 0.05 }
        let flash = t - zb.hitT
        let tintK = flash >= 0 && flash < 0.14 ? 0.75 : 0
        let base = RetroPose(RVec(zb.x, bob, zb.z), yaw: yaw, roll: roll, size: size)
        c.draw(shadow, [RetroPose(RVec(zb.x, 0, zb.z), scale: RVec(size, 1, size))])
        c.draw(zombieBodies[zb.kind.rawValue], [base], tint: .one, tintK: tintK)
        c.draw(zombieArmsSleeve[zb.kind.rawValue], [RetroPose(RVec(0, 0.8, 0), pitch: armPitch), base], tint: .one, tintK: tintK)
        if zb.kind == .small {
            c.draw(propeller, [RetroPose(RVec(0, 1.6, 0.02), yaw: t * (zb.isActive ? 14 : 30)), base])
        }
        if let toy = zb.toy, !zb.isActive {
            c.draw(toys[toy.rawValue], [RetroPose(RVec(0, 0.62, -0.42), yaw: 0.4), base])
        }
        if case .stunned = zb.state {
            for i in 0..<3 {
                let a = t * 5 + Double(i) * 2.094
                c.draw(star, [RetroPose(RVec(cos(a) * 0.34, 1.5, sin(a) * 0.3), yaw: a), base])
            }
        }
        if hearts > 0 && !leaving || hearts > 0 && hearts < 1.6 {
            for i in 0..<2 {
                let rise = (hearts * 0.5 + Double(i) * 0.35).truncatingRemainder(dividingBy: 0.7)
                let hx = zb.x + (i == 0 ? -0.18 : 0.2) * size
                let hy = (1.55 + rise) * size
                let s = 1 - rise / 0.7 * 0.4
                c.draw(heart, [RetroPose(RVec(hx, hy, zb.z - 0.1), roll: sin(t * 4 + Double(i)) * 0.25, size: s)], cull: false)
            }
        }
    }
}
