// Дом в комнате (ROADMAP, этап 8): уровни шести линий → что стоит в комнате и где.
// Чистая геометрия на полу (x, z в метрах, как в PetRoom), без RealityKit: RoomDecor (app/App) строит
// по ней примитивы, а тесты на Linux проверяют, что предметы не лезут на собаку, миску, мяч и пути
// прогулки и игры. Уровень 0 — «как было»: в комнате ничего нового.
//
// Где что (кадр узкий, свободны только углы у задней стены, стена над собакой и полоса перед ковром):
//   кухня   — задний левый угол, за миской: холодильник → + бункер-автокормушка → + полка с кастрюлями;
//   ванная  — задний правый угол, правее хвоста: ванна → джакузи с пузырями → спа с уточкой и полотенцем;
//   дворик  — окно на задней стене над собакой: травка → забор и клумба → деревья;
//   будка   — во дворе за окном: будка → тёплая (плед, свет) → домик с трубой и дымом;
//   лежанка — плоская, прямо под собакой: Шиба на ней стоит и спит, ходить не мешает;
//   игры    — низко перед ковром: корзина игрушек → + туннель → батут вместо туннеля и горка.
// Точки хореографии — копия PetChoreo/PetRoom (там RealityKit); RoomDecorTests на macOS сверяет копию.

import Foundation
@preconcurrency import PetCore

enum RoomPlan {
    /// Верхний уровень линии (economy.json: база + 3).
    static let maxLevel = 3

    /// Уровни линий для сцены. Equatable — сцену перестраиваем, только когда что-то поменялось.
    struct Levels: Equatable, Hashable, Sendable {
        var bath = 0, bed = 0, kitchen = 0, kennel = 0, play = 0, yard = 0

        subscript(_ line: HomeLine) -> Int {
            get {
                switch line {
                case .bath: return bath
                case .bed: return bed
                case .kitchen: return kitchen
                case .kennel: return kennel
                case .play: return play
                case .yard: return yard
                }
            }
            set {
                let v = min(max(newValue, 0), RoomPlan.maxLevel)
                switch line {
                case .bath: bath = v
                case .bed: bed = v
                case .kitchen: kitchen = v
                case .kennel: kennel = v
                case .play: play = v
                case .yard: yard = v
                }
            }
        }

        /// Все линии на одном уровне (снимки, тесты).
        static func all(_ level: Int) -> Levels {
            var l = Levels()
            for line in HomeLine.allCases { l[line] = level }
            return l
        }

        /// Окно на задней стене: есть двор или будка (будка стоит во дворе).
        var window: Bool { yard > 0 || kennel > 0 }
    }

    /// Уровни из сейва, обрезанные в 0…maxLevel (битый сейв не рисует несуществующий уровень).
    static func levels(_ f: SaveFile) -> Levels {
        var l = Levels()
        for line in HomeLine.allCases { l[line] = HomeShop.level(f, line) }
        return l
    }

    // MARK: геометрия на полу

    struct P: Equatable, Sendable {
        var x: Float, z: Float
        init(_ x: Float, _ z: Float) { self.x = x; self.z = z }
        static func + (a: P, b: P) -> P { P(a.x + b.x, a.z + b.z) }
        static func - (a: P, b: P) -> P { P(a.x - b.x, a.z - b.z) }
        static func * (a: P, k: Float) -> P { P(a.x * k, a.z * k) }
        var length: Float { (x * x + z * z).squareRoot() }
    }

    /// Прямоугольник на полу по осям комнаты.
    struct Rect: Equatable, Sendable {
        var minX: Float, maxX: Float, minZ: Float, maxZ: Float
        init(x: ClosedRange<Float>, z: ClosedRange<Float>) {
            minX = x.lowerBound; maxX = x.upperBound; minZ = z.lowerBound; maxZ = z.upperBound
        }
        var center: P { P((minX + maxX) / 2, (minZ + maxZ) / 2) }
        var width: Float { maxX - minX }
        var depth: Float { maxZ - minZ }

        func intersects(_ o: Rect) -> Bool {
            minX < o.maxX && o.minX < maxX && minZ < o.maxZ && o.minZ < maxZ
        }
        /// Расстояние от точки до прямоугольника (0 — внутри).
        func distance(to p: P) -> Float {
            let dx = max(minX - p.x, 0, p.x - maxX)
            let dz = max(minZ - p.z, 0, p.z - maxZ)
            return (dx * dx + dz * dz).squareRoot()
        }
    }

    /// Прямоугольник на задней стене: x и высота y.
    struct WallRect: Equatable, Sendable {
        var minX: Float, maxX: Float, minY: Float, maxY: Float
        var width: Float { maxX - minX }
        var height: Float { maxY - minY }
    }

    // MARK: места

    /// Задняя стена (PetRoom.backWallZ) и толщина плинтуса: предметы у стены ставим перед плинтусом.
    static let backWallZ: Float = -1.4
    static let wallFront: Float = backWallZ + 0.02

    /// Кухня: холодильник в заднем левом углу кадра, за миской. Левее -0.58 — уже за краем экрана.
    static let kitchen = Rect(x: -0.58...(-0.36), z: (wallFront)...(-1.18))
    /// Полка кухни шефа — на стене над холодильником, левее облачка с репликой.
    static let kitchenShelf = WallRect(minX: -0.58, maxX: -0.36, minY: 0.44, maxY: 0.54)
    /// Ванна: задний правый угол, правее хвоста. Правее 0.42 режет край экрана.
    static let bath = Rect(x: 0.19...0.42, z: (wallFront)...(-1.18))
    /// Полотенце спа на стене над ванной.
    static let bathTowel = WallRect(minX: 0.33, maxX: 0.42, minY: 0.22, maxY: 0.36)
    /// Окно во двор: над собакой, ниже строки с таймером и выше ушей и хвоста. Снаружи рамки.
    static let window = WallRect(minX: -0.15, maxX: 0.30, minY: 0.21, maxY: 0.43)
    /// Ширина рамки окна.
    static let windowFrame: Float = 0.02
    /// Будка во дворе — правая часть окна, двор (кусты, деревья) — левая.
    static let kennelSlot = WallRect(minX: 0.12, maxX: 0.27, minY: 0.23, maxY: 0.38)

    /// Игровой угол — полоса перед ковром (ковёр до z = 0.45) и над кнопками (дальше 0.62 их уже не видно).
    /// Вещи низкие: выше playMaxHeight закроют мяч и лапы. Справа корзина, в середине туннель или батут,
    /// слева горка.
    static let playBasket = Rect(x: 0.10...0.24, z: 0.50...0.60)
    static let playCenter = Rect(x: -0.10...0.04, z: 0.50...0.60)
    static let playSlide = Rect(x: -0.26...(-0.15), z: 0.50...0.60)
    /// Предел высоты предметов перед ковром.
    static let playMaxHeight: Float = 0.07

    /// Что стоит на полу при этих уровнях (лежанка отдельно — она под собакой).
    static func floorItems(_ l: Levels) -> [(line: HomeLine, rect: Rect)] {
        var out: [(HomeLine, Rect)] = []
        if l.kitchen > 0 { out.append((.kitchen, kitchen)) }
        if l.bath > 0 { out.append((.bath, bath)) }
        if l.play > 0 { out.append((.play, playBasket)) }
        if l.play > 1 { out.append((.play, playCenter)) }
        if l.play > 2 { out.append((.play, playSlide)) }
        return out
    }

    // MARK: лежанка

    /// Лежанка — эллипс в осях подставки (повёрнута на yaw3q, морда к +z): сдвинут к хвосту, чтобы миска
    /// у морды (bowlUnderSnout) не наезжала на край. Полуоси — по x (бок) и по z (вдоль собаки).
    static let bedCenterLocal = P(0, -0.07)
    static let bedHalfX: Float = 0.18
    static let bedHalfZ: Float = 0.24
    /// Бортик-рамка вокруг (с уровня 2): ширина и высота. Низкий — через него перешагивают.
    static let bedRim: Float = 0.022
    static let bedRimHeight: Float = 0.02
    /// Верх матраса: лапы утопают на столько — мягкая лежанка.
    static let bedTop: Float = 0.01

    /// Точка в осях подставки → комната (поворот yaw3q вокруг y).
    static func toRoom(_ local: P) -> P {
        let c = cos(Keep.yaw3q), s = sin(Keep.yaw3q)
        return P(local.x * c + local.z * s, -local.x * s + local.z * c)
    }

    /// Комната → оси подставки.
    static func toStand(_ p: P) -> P {
        let c = cos(Keep.yaw3q), s = sin(Keep.yaw3q)
        return P(p.x * c - p.z * s, p.x * s + p.z * c)
    }

    /// Насколько точка (комната) внутри эллипса лежанки с бортиком: < 1 — внутри.
    static func bedEllipse(_ p: P, grow: Float = 0) -> Float {
        let q = toStand(p) - bedCenterLocal
        let ax = bedHalfX + bedRim + grow, az = bedHalfZ + bedRim + grow
        return (q.x * q.x) / (ax * ax) + (q.z * q.z) / (az * az)
    }

    // MARK: копия хореографии (сверка — RoomDecorTests на macOS)

    enum Keep {
        static let yaw3q: Float = -0.55
        static let bowlHome = P(-0.30, -0.75)
        static let bowlRadius: Float = 0.09
        static let ballHome = P(0.15, 0.30)
        static let ballRadius: Float = 0.05
        /// Миска у морды на время еды (PetChoreo.bowlUnderSnout, в осях подставки).
        static let bowlUnderSnoutLocal = P(0, 0.30)
        /// Куда кладётся находка с прогулки (PetChoreo.Walk.dropped, в осях подставки).
        static let dropLocal = P(0, 0.36)
        static let petHalfLength: Float = 0.29
        static let petHalfWidth: Float = 0.09
        static var petReachMax: Float { (petHalfLength * petHalfLength + petHalfWidth * petHalfWidth).squareRoot() }
        /// Прогулка: разворот у walkTurnAt, уход за правый край к walkOffstage и обратно в начало координат.
        static let walkTurnAt = P(0, -0.30)
        static let walkOffstage = P(0.95, -0.15)
        /// Игра: разворот у playTurnAt, пробежка до playRunTo, мяч дугами (квадратичные Безье) через ballFar.
        static let playTurnAt = P(-0.04, -0.30)
        static let playRunTo = P(0.019, -0.586)
        static let ballFar = P(0.08, -0.88)
        static let knockTo = P(0.096, -0.958)
        static let flyCurve = P(0.34, -0.10)
        static let backCurve = P(0.30, -0.35)
    }

    /// Квадратичная Безье — как PetChoreo.bezier.
    static func bezier(_ a: P, _ c: P, _ b: P, _ t: Float) -> P {
        let u = 1 - t
        return a * (u * u) + c * (2 * u * t) + b * (t * t)
    }

    /// Точки пути мяча в игре (центры): вылет, откат, возврат.
    static func ballPath(steps: Int = 24) -> [P] {
        var out: [P] = []
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            out.append(bezier(Keep.ballHome, Keep.flyCurve, Keep.ballFar, t))
            out.append(Keep.ballFar + (Keep.knockTo - Keep.ballFar) * t)
            out.append(bezier(Keep.knockTo, Keep.backCurve, Keep.ballHome, t))
        }
        return out
    }

    /// Пятно Шибы (прямоугольник полудлина × полуширина) в позиции p с поворотом yaw: содержит ли точку q
    /// с запасом pad. yaw — как в PetChoreo: 0 — мордой к камере (+z).
    static func petCovers(at p: P, yaw: Float, point q: P, pad: Float) -> Bool {
        let d = q - p
        let fwd = P(sin(yaw), cos(yaw))
        let along = d.x * fwd.x + d.z * fwd.z
        let across = d.x * fwd.z - d.z * fwd.x
        return abs(along) <= Keep.petHalfLength + pad && abs(across) <= Keep.petHalfWidth + pad
    }

    /// Поворот «мордой к точке» — как ChoreoPath.yaw(toward:).
    static func yaw(toward d: P) -> Float { atan2(d.x, d.z) }
}
