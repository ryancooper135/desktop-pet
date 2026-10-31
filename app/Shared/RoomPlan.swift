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

        /// «bath=0,bed=1,kitchen=0,kennel=0,play=0,yard=0» — признак для UI-тестов (значение pet.stage при PET_UI_TEST).
        var tag: String {
            HomeLine.allCases.map { "\($0.rawValue)=\(self[$0])" }.joined(separator: ",")
        }
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

        /// Точки по периметру (по 5 на сторону): не накрывает ли их пятно питомца.
        func outline() -> [P] {
            var out: [P] = []
            for i in 0...4 {
                let t = Float(i) / 4
                out.append(P(minX + width * t, minZ))
                out.append(P(minX + width * t, maxZ))
                out.append(P(minX, minZ + depth * t))
                out.append(P(maxX, minZ + depth * t))
            }
            return out
        }

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

    /// Кухня: холодильник в заднем левом углу кадра, за миской. Левее -0.54 его режет край экрана,
    /// правее -0.33 трубка кормушки уходит за морду.
    static let kitchen = Rect(x: -0.53...(-0.33), z: (wallFront)...(-1.18))
    /// Полка кухни шефа — на стене над холодильником, левее облачка с репликой.
    static let kitchenShelf = WallRect(minX: -0.53, maxX: -0.36, minY: 0.44, maxY: 0.54)
    /// Ванна: задний правый угол, правее хвоста. Правее 0.42 режет край экрана.
    static let bath = Rect(x: 0.19...0.42, z: (wallFront)...(-1.18))
    /// Полотенце спа на стене над ванной.
    static let bathTowel = WallRect(minX: 0.33, maxX: 0.42, minY: 0.22, maxY: 0.36)
    /// Полка для вещиц из капсулы (волна 11) — над полотенцем, правее полога балдахина;
    /// зеркало кухонной полки по высоте. Уже ванны: правее 0.40 доску на стене режет край экрана (ui-67).
    static let decorShelf = WallRect(minX: 0.328, maxX: 0.398, minY: 0.44, maxY: 0.54)
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
    static let playCenter = Rect(x: -0.085...0.055, z: 0.50...0.60)
    /// Левее -0.235 площадку горки режет край экрана.
    static let playSlide = Rect(x: -0.235...(-0.125), z: 0.50...0.60)
    /// Предел высоты предметов перед ковром (проверка — RoomDecorTests.testPlayIsLow по рамке сцены).
    static let playMaxHeight: Float = 0.07

    /// Что стоит на полу при этих уровнях (лежанка отдельно — она под собакой). Места подобраны под Шибу;
    /// у своего персонажа (body) вещь, на которую он наступал бы или в которую упирался бы мяч, не ставится
    /// (Zone.clear): комната без неё, зато питомец не проходит сквозь холодильник. У Шибы стоит всё.
    static func floorItems(_ l: Levels, body: PetBody = .shiba) -> [(line: HomeLine, rect: Rect)] {
        var out: [(line: HomeLine, rect: Rect)] = []
        if l.kitchen > 0 { out.append((.kitchen, kitchen)) }
        if l.bath > 0 { out.append((.bath, bath)) }
        if l.play > 0 { out.append((.play, playBasket)) }
        if l.play > 1 { out.append((.play, playCenter)) }
        if l.play > 2 { out.append((.play, playSlide)) }
        guard body != .shiba else { return out }
        let zone = Zone(body)
        return out.filter { zone.clear($0.rect) }
    }

    // MARK: лежанка

    /// Лежанка — эллипс в осях подставки (повёрнута на yaw3q, морда к +z): сдвинут к хвосту, чтобы миска
    /// у морды (bowlUnderSnout) не наезжала на край. Полуоси — по x (бок) и по z (вдоль собаки).
    static let bedCenterLocal = P(0, -0.07)
    static let bedHalfX: Float = 0.18
    static let bedHalfZ: Float = 0.24
    /// Бортик-рамка вокруг (с уровня 2): ширина и высота. Низкий — собака уходит с лежанки во все стороны
    /// (прогулка назад и вправо, игра назад), шаг не поднимается: 6 мм над матрасом лапы проходят незаметно.
    static let bedRim: Float = 0.022
    static let bedRimHeight: Float = 0.016
    /// Верх матраса (на всех уровнях один). Шиба на лежанке стоит на нём — подъём petLift. Пятно-тень (PetRoom.blobY) выше.
    static let bedTop: Float = 0.01
    /// Подъём petLift полный, пока середина собаки внутри этой доли эллипса матраса, и спадает в 0 к liftZero:
    /// прогулка и игра уводят Шибу с лежанки — сходит без ступеньки (центр у края — половина лап ещё на матрасе).
    static let liftFull: Float = 0.75
    static let liftZero: Float = 1.35

    /// Балдахин (уровень 2 «Кроватка с балдахином» и 3) — на задней стене за собакой: ламбрекен над окном
    /// и два подхваченных полога по бокам. У самой лежанки ему места нет: стойки встали бы на пути прогулки
    /// и игры, полог над собакой закрыл бы её. Сверху — строка таймера, справа — полотенце ванной,
    /// снизу пологи кончаются выше свечей спа (они у самой стены).
    static let canopy = WallRect(minX: -0.185, maxX: 0.318, minY: 0.19, maxY: 0.462)
    /// Ширина полога вверху; внизу, под подхватом, на canopyFlare шире — расходится к краю комнаты.
    static let canopyDrape: Float = 0.042
    static let canopyFlare: Float = 0.01
    /// Высота подхвата пологов.
    static let canopyTieY: Float = 0.27
    /// Верх ванны со свечами спа (RoomDecor.bath: ножки 0.02 + корпус 0.1 + свеча 0.03 + огонёк) — ниже пологов.
    static let bathTop: Float = 0.17

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

    /// Верх матраса лежанки уровня level; 0 — лежанки нет, лапы на полу. По нему же строит матрас RoomDecor.bed.
    static func mattressTop(bed level: Int) -> Float {
        level > 0 ? bedTop : 0
    }

    /// На сколько поднять Шибу (по y), когда его середина в точке p комнаты: на лежанке — до верха матраса,
    /// чтобы лапы не уходили в него; к краю плавно в 0, вне лежанки и без неё — 0.
    static func petLift(_ l: Levels, at p: P) -> Float {
        let top = mattressTop(bed: l.bed)
        guard top > 0 else { return 0 }
        let q = toStand(p) - bedCenterLocal
        let r = ((q.x * q.x) / (bedHalfX * bedHalfX) + (q.z * q.z) / (bedHalfZ * bedHalfZ)).squareRoot()
        let t = min(max((r - liftFull) / (liftZero - liftFull), 0), 1)
        return top * (1 - t * t * (3 - 2 * t))
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
        /// С волны 53 камера ближе и площадка уже: разворот прижат к середине, пробежка чуть левее.
        static let playTurnAt = P(-0.0357, -0.30)
        static let playRunTo = P(0.0008, -0.5858)
        static let ballFar = P(0.08, -0.88)
        static let knockTo = P(0.0957, -0.9585)
        static let flyCurve = P(0.34, -0.10)
        static let backCurve = P(0.30, -0.35)
    }

    // MARK: зона питомца под его размер (волна 14)

    /// Площадка в кадре — копия ChoreoPath.Area и playArea: трапеция по z, x на краях линейно.
    struct Area: Sendable {
        var nearZ: Float, nearMinX: Float, nearMaxX: Float
        var farZ: Float, farMinX: Float, farMaxX: Float

        func xRange(_ z: Float) -> (min: Float, max: Float) {
            let t = (nearZ - z) / (nearZ - farZ)
            return (nearMinX + (farMinX - nearMinX) * t, nearMaxX + (farMaxX - nearMaxX) * t)
        }

        /// Как ChoreoPath.Area.clamp: z между краями, x не ближе inset к краю (не влезает — середина).
        func clamp(_ p: P, inset: Float) -> P {
            let z = min(max(p.z, farZ), nearZ)
            let r = xRange(z)
            let lo = r.min + inset, hi = r.max - inset
            return P(lo <= hi ? min(max(p.x, lo), hi) : (r.min + r.max) / 2, z)
        }
    }

    static let playArea = Area(nearZ: 0.35, nearMinX: -0.245, nearMaxX: 0.224,
                               farZ: -1.0, farMinX: -0.441, farMaxX: 0.340)

    /// Где ходит питомец с этим телом и куда летает мяч — те же формулы, что в ChoreoPath, с поправкой
    /// на длину и ширину (PetBody из рамки модели). Zone(.shiba) совпадает с Keep (RoomPlanTests),
    /// Zone(body) с ChoreoPath при том же body — RoomDecorTests на macOS. clear — с теми же запасами,
    /// что проверяют тесты Шибы.
    struct Zone: Sendable {
        var halfLength: Float, halfWidth: Float
        var bowlUnderSnoutLocal: P, dropLocal: P
        var playTurnAt: P, playRunTo: P, ballFar: P, knockTo: P

        init(_ body: PetBody = .shiba) {
            let len = Float(body.length), wid = Float(body.width)
            halfLength = Keep.petHalfLength * len
            halfWidth = Keep.petHalfWidth * wid
            bowlUnderSnoutLocal = P(0, 0.30 * len)
            dropLocal = P(0, 0.36 * len)
            let reach = (halfLength * halfLength + halfWidth * halfWidth).squareRoot()
            playTurnAt = RoomPlan.playArea.clamp(P(-0.04, -0.30), inset: reach)
            ballFar = RoomPlan.playArea.clamp(P(0.08, -0.88), inset: Keep.ballRadius)
            let d = ballFar - playTurnAt
            let dir = d.length > 0 ? d * (1 / d.length) : P(0, -1)
            playRunTo = RoomPlan.playArea.clamp(ballFar - dir * (0.30 * len), inset: reach)
            knockTo = RoomPlan.playArea.clamp(ballFar + dir * 0.08, inset: Keep.ballRadius)
        }

        var reachMax: Float { (halfLength * halfLength + halfWidth * halfWidth).squareRoot() }
        var walkTurnAt: P { Keep.walkTurnAt }
        var walkOffstage: P { Keep.walkOffstage }

        /// Путь мяча в игре (центры): вылет, откат, возврат.
        func ballPath(steps: Int = 24) -> [P] {
            var out: [P] = []
            for i in 0...steps {
                let t = Float(i) / Float(steps)
                out.append(RoomPlan.bezier(Keep.ballHome, Keep.flyCurve, ballFar, t))
                out.append(ballFar + (knockTo - ballFar) * t)
                out.append(RoomPlan.bezier(knockTo, Keep.backCurve, Keep.ballHome, t))
            }
            return out
        }

        /// Пятно питомца в p с поворотом yaw содержит точку q с запасом pad (как RoomPlan.petCovers).
        func covers(at p: P, yaw: Float, point q: P, pad: Float) -> Bool {
            let d = q - p
            let fwd = P(sin(yaw), cos(yaw))
            let along = d.x * fwd.x + d.z * fwd.z
            let across = d.x * fwd.z - d.z * fwd.x
            return abs(along) <= halfLength + pad && abs(across) <= halfWidth + pad
        }

        /// Позы (точка и поворот) прогулки и игры по формулам PetChoreo; смягчение не важно — сетка.
        func poses(steps n: Int = 20) -> [(P, Float)] {
            let y0 = Keep.yaw3q
            let yawOut = RoomPlan.yaw(toward: walkOffstage - walkTurnAt)
            let yawIn = RoomPlan.yaw(toward: P(0, 0) - walkOffstage)
            let yawRun = RoomPlan.yaw(toward: ballFar - playTurnAt)
            let yawBack = RoomPlan.yaw(toward: P(0, 0) - playRunTo)
            var out: [(P, Float)] = []
            for i in 0...n {
                let s = Float(i) / Float(n)
                out.append((walkTurnAt * s, y0 + (yawOut - y0) * s))
                out.append((walkTurnAt + (walkOffstage - walkTurnAt) * s, yawOut))
                out.append((walkOffstage * (1 - s), yawIn))
                out.append((P(0, 0), yawIn + (y0 - yawIn) * s))
                out.append((playTurnAt * s, y0 + (yawRun - y0) * s))
                out.append((playTurnAt + (playRunTo - playTurnAt) * s, yawRun))
                out.append((playRunTo, yawRun + (yawBack - yawRun) * s))
                out.append((playRunTo * (1 - s), yawBack))
                out.append((P(0, 0), yawBack + (y0 - yawBack) * s))
            }
            return out
        }

        /// Вещь на полу в r не мешает: не у миски (дома и под мордой), не у мяча и его пути, не там, куда
        /// ложится находка, не под пятном питомца ни в одной позе и не в его размахе там, где он разворачивается.
        func clear(_ r: Rect) -> Bool {
            if r.distance(to: Keep.bowlHome) <= Keep.bowlRadius + 0.04 { return false }
            if r.distance(to: RoomPlan.toRoom(bowlUnderSnoutLocal)) <= Keep.bowlRadius + 0.04 { return false }
            if r.distance(to: Keep.ballHome) <= Keep.ballRadius + 0.1 { return false }
            if r.distance(to: RoomPlan.toRoom(dropLocal)) <= 0.1 { return false }
            for p in ballPath() where r.distance(to: p) <= Keep.ballRadius + 0.03 { return false }
            for turn in [P(0, 0), walkTurnAt, playTurnAt, playRunTo] where r.distance(to: turn) <= reachMax + 0.04 {
                return false
            }
            let edge = r.outline()
            for (p, a) in poses() {
                for q in edge where covers(at: p, yaw: a, point: q, pad: 0.04) { return false }
            }
            return true
        }
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
