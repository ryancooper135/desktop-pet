// Свой персонаж папкой через «Файлы» (волна 12): <папка>/character.json + model.usdz с анимациями.
// Здесь только разбор конфига и проверка: какие клипы есть, чего не хватает (причины по-русски),
// что отключится без необязательных, кости для вещей и цвет шерсти. Формат — DECISIONS.md, «Волна 12».
// Копирует и хранит папки CharacterStore, в сцену ставит PetStage (PetModel.load).

import Foundation

/// character.json. Обязательны только name и clips — остальное со значениями Шибы.
struct CharacterConfig: Codable, Equatable, Sendable {
    /// Кусок таймлайна модели в секундах. loop не задан — цикл ли это, решает наш клип (CharacterPack.loops).
    struct Range: Codable, Equatable, Sendable {
        var start: Double
        var end: Double
        var loop: Bool?
    }

    /// Кости, на которых едут вещи и взгляд: голова (шапка, бантик), шея (шарф), спина (плащ), корень тела.
    /// Не заданы — ищем кости Шибы (Head, Neck2/Neck3, Torso…Torso3, Body).
    struct Bones: Codable, Equatable, Sendable {
        var body: String?
        var head: String?
        var neck: String?
        var back: [String]?
    }

    var format: Int?
    var name: String
    var author: String?
    var license: String?
    /// Файл модели рядом с character.json.
    var model: String?
    /// Множитель к росту Шибы (0,42 м): 0,8 — на пятую часть меньше.
    var scale: Double?
    /// Подъём над полом в метрах (модель с ногами ниже нуля, парящий дух).
    var lift: Double?
    /// Поворот вокруг вертикали в градусах: модель смотрит не на +Z.
    var yaw: Double?
    var fps: Double?
    /// Клипы в файле: имя → кусок единственного таймлайна модели.
    var clips: [String: Range]
    /// Наш клип → клип в файле («idle»: «Idle_Breath»). Без записи ищем клип с нашим именем.
    var rename: [String: String]?
    var bones: Bones?
    /// Основной цвет шерсти «#RRGGBB». Нет — как в модели.
    var color: String?
    /// Сдвиг лёжа на боку в единицах модели (как PetModel.deathShiftX у Шибы). Нет — 0.
    var deathShift: Double?
}

/// Тело персонажа относительно Шибы (CharacterPack.body): во сколько раз выше, длиннее и шире, и подъём над полом.
/// Хореография (ChoreoPath) множит на это свои точки, подобранные под Шибу. У Шибы всё 1 и 0.
struct PetBody: Equatable, Sendable {
    var height: Double = 1
    var length: Double = 1
    var width: Double = 1
    var lift: Double = 0

    static let shiba = PetBody()

    /// Точка на полу в осях питомца (морда к +z): вперёд-назад — по длине, вбок — по ширине, высота та же.
    /// Так миска встаёт под морду, а не в грудь большому и не в метре от маленького.
    func onFloor(_ x: Double, _ y: Double, _ z: Double) -> (x: Double, y: Double, z: Double) {
        (x * width, y, z * length)
    }

    /// Точка на теле (пасть, макушка): ещё и по высоте, плюс подъём над полом.
    func onBody(_ x: Double, _ y: Double, _ z: Double) -> (x: Double, y: Double, z: Double) {
        (x * width, y * height + lift, z * length)
    }
}

/// Ошибка разбора или копирования — текст уже для человека.
struct CharacterPackError: Error, Equatable, LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Итог проверки. errors не пусто — персонажа не ставим; off — что просто не будет работать.
struct CharacterCheck: Equatable, Sendable {
    var errors: [String] = []
    var off: [String] = []
    /// Мелочи без последствий: лишние записи в rename.
    var notes: [String] = []
    /// Наши имена клипов → куски таймлайна, уже с подстановками (idle_2 без своего — как idle).
    var clips: [String: CharacterConfig.Range] = [:]
    var ok: Bool { errors.isEmpty }
}

enum CharacterPack {
    static let configName = "character.json"
    static let defaultModel = "model.usdz"
    static let format = 1
    static let scaleRange: ClosedRange<Double> = 0.25...3
    static let liftRange: ClosedRange<Double> = -0.3...0.3
    static let modelExtensions: Set<String> = ["usdz", "usdc", "usda", "reality"]

    /// Без этих клипов пёс не играет основные позы — пак не ставим. Причина — в ошибку.
    static let required: [(clip: String, why: String)] = [
        ("idle", "без него пёс не стоит"),
        ("walk", "без него не уходит гулять"),
        ("eat", "без него не ест из миски"),
        ("sit", "без него не сидит грязным и в ванне"),
        ("lie", "без него не ложится, когда устал"),
        ("sleep", "без него не спит"),
        ("death", "без него не видно, что он умер"),
    ]

    /// Остальные клипы Шибы: нет — шаг пропускается (PetStance.pick), отключается только своё.
    static let optional: [(clip: String, off: String)] = [
        ("idle_2", "радуется в обычной стойке idle"),
        ("idle_headlow", "грустит в обычной стойке idle"),
        ("gallop", "на прогулке не бегает, только идёт"),
        ("gallop_jump", "не прыгает на бегу"),
        ("jump_to_idle", "в игре без прыжка, если нет play_bow и hop"),
        ("attack", "без выпада за мячиком"),
        ("hit_left", "не вздрагивает от тычка слева"),
        ("hit_right", "не вздрагивает от тычка справа"),
        ("sit_in", "садится рывком, без перехода"),
        ("sit_out", "встаёт с места рывком"),
        ("lie_in", "ложится рывком, без перехода"),
        ("lie_out", "встаёт из лёжа рывком"),
        ("sleep_in", "засыпает рывком"),
        ("sleep_out", "просыпается рывком"),
        ("idle_wag", "не виляет в простое"),
        ("happy_wag", "не виляет от радости"),
        ("head_tilt", "не наклоняет голову"),
        ("shake", "не отряхивается после ванны"),
        ("hop", "не подпрыгивает от радости"),
        ("play_bow", "без поклона перед игрой"),
        ("ear_flick", "не дёргает ухом"),
        ("sniff", "не принюхивается"),
        ("look_l", "не оглядывается влево"),
        ("look_r", "не оглядывается вправо"),
        ("yawn", "не зевает"),
        ("bark", "на «Голос» не лает, только подпрыгивает"),
        ("pant", "не дышит с высунутым языком после игры"),
    ]

    /// Чем заменить недостающий цикл позы: радость и грусть стоят в обычной стойке, бег — шагом.
    static let fallbacks: [String: String] = ["idle_2": "idle", "idle_headlow": "idle", "gallop": "walk"]

    /// Циклы среди наших клипов (как loop в shiba.clips.json): для них loop из конфига не обязателен.
    static let loops: Set<String> = ["idle", "idle_2", "idle_headlow", "walk", "gallop", "sit", "lie", "sleep"]

    static var allClips: [String] { required.map(\.clip) + optional.map(\.clip) }

    // MARK: разбор

    /// character.json → конфиг. Ошибка JSON — по-русски, с полем, где сломалось.
    static func parse(_ data: Data) throws -> CharacterConfig {
        do {
            return try JSONDecoder().decode(CharacterConfig.self, from: data)
        } catch let e as DecodingError {
            throw CharacterPackError(describe(e))
        }
    }

    static func describe(_ e: DecodingError) -> String {
        func path(_ keys: [CodingKey]) -> String {
            keys.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch e {
        case let .keyNotFound(key, ctx):
            let at = path(ctx.codingPath + [key])
            if at == "name" { return "нет поля name — как зовут персонажа?" }
            if at == "clips" { return "нет поля clips — где в модели какие клипы?" }
            return "нет поля \(at)"
        case let .typeMismatch(type, ctx), let .valueNotFound(type, ctx):
            let want = type == String.self ? "строка" : (type == Bool.self ? "true или false"
                : (type == Double.self || type == Int.self ? "число" : "другой вид значения"))
            return "поле \(path(ctx.codingPath)) — не того вида, нужно: \(want)"
        case let .dataCorrupted(ctx):
            return ctx.codingPath.isEmpty ? "character.json — не JSON (проверь запятые и кавычки)"
                : "поле \(path(ctx.codingPath)) не читается"
        @unknown default:
            return "character.json не читается"
        }
    }

    // MARK: проверка

    /// Проверить конфиг. modelExists — есть ли файл модели (проверяет CharacterStore по диску).
    static func check(_ c: CharacterConfig, modelExists: Bool = true) -> CharacterCheck {
        var out = CharacterCheck()
        if let f = c.format, f > format {
            out.errors.append("формат \(f) — это приложение знает только \(format), обнови его")
        }
        if c.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.errors.append("пустое name — как зовут персонажа?")
        }
        let model = modelName(c)
        if !isSafeFileName(model) {
            out.errors.append("model «\(model)» — нужно имя файла рядом с character.json, без папок")
        } else if !modelExtensions.contains((model as NSString).pathExtension.lowercased()) {
            out.errors.append("model «\(model)» — нужен .usdz (или .usdc, .usda, .reality)")
        } else if !modelExists {
            out.errors.append("нет файла \(model) рядом с character.json")
        }
        if let s = c.scale, !(s.isFinite && scaleRange.contains(s)) {
            out.errors.append("scale \(num(s)) — можно от \(num(scaleRange.lowerBound)) до \(num(scaleRange.upperBound))")
        }
        if let l = c.lift, !(l.isFinite && liftRange.contains(l)) {
            out.errors.append("lift \(num(l)) м — можно от \(num(liftRange.lowerBound)) до \(num(liftRange.upperBound))")
        }
        if let y = c.yaw, !y.isFinite { out.errors.append("yaw — не число") }
        if let f = c.fps, !(f.isFinite && f > 0) { out.errors.append("fps \(num(f)) — нужно больше нуля") }
        if let col = c.color, rgb(col) == nil {
            out.errors.append("color «\(col)» — нужен вид #RRGGBB")
        }
        for (name, r) in c.clips.sorted(by: { $0.key < $1.key }) {
            if !(r.start.isFinite && r.end.isFinite) || r.start < 0 || r.end <= r.start {
                out.errors.append("клип \(name): конец \(num(r.end)) не позже начала \(num(r.start))")
            }
        }

        let rename = c.rename ?? [:]
        let ours = Set(allClips)
        for (our, theirs) in rename.sorted(by: { $0.key < $1.key }) {
            if !ours.contains(our) {
                out.notes.append("rename: «\(our)» — такого нашего клипа нет, пропускаю")
            } else if c.clips[theirs] == nil {
                out.errors.append("rename: \(our) → \(theirs), а клипа \(theirs) в clips нет")
            }
        }

        func range(_ our: String) -> CharacterConfig.Range? {
            guard let r = c.clips[rename[our] ?? our], r.end > r.start, r.start >= 0 else { return nil }
            return CharacterConfig.Range(start: r.start, end: r.end, loop: r.loop ?? loops.contains(our))
        }
        for (clip, why) in required {
            if let r = range(clip) { out.clips[clip] = r } else { out.errors.append("нет клипа \(clip) — \(why)") }
        }
        for (clip, off) in optional {
            if let r = range(clip) {
                out.clips[clip] = r
            } else {
                if let sub = fallbacks[clip], let r = range(sub) { out.clips[clip] = r }
                out.off.append("нет \(clip) — \(off)")
            }
        }
        return out
    }

    static func modelName(_ c: CharacterConfig) -> String {
        let m = c.model?.trimmingCharacters(in: .whitespaces) ?? ""
        return m.isEmpty ? defaultModel : m
    }

    /// Имя файла без папок и «..»: модель только рядом с конфигом.
    static func isSafeFileName(_ s: String) -> Bool {
        !s.isEmpty && !s.contains("/") && !s.contains("\\") && s != "." && s != ".." && !s.hasPrefix(".")
    }

    /// «#RRGGBB» или «RRGGBB» → 0xRRGGBB.
    static func rgb(_ s: String) -> UInt32? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, t.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(t, radix: 16)
    }

    /// Наши кости (как у Шибы: PetWear, PetRig) → кости модели. Только те, что отличаются.
    /// Спина у Шибы из трёх костей: короче список — последняя повторяется.
    static func boneAliases(_ b: CharacterConfig.Bones?) -> [String: String] {
        guard let b else { return [:] }
        var out: [String: String] = [:]
        func set(_ ours: String, _ theirs: String?) {
            guard let t = theirs?.trimmingCharacters(in: .whitespaces), !t.isEmpty, t != ours else { return }
            out[ours] = t
        }
        set("Body", b.body)
        set("Head", b.head)
        set("Neck2", b.neck)
        set("Neck3", b.neck)
        let back = (b.back ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let last = back.last {
            for (i, ours) in ["Torso", "Torso2", "Torso3"].enumerated() {
                set(ours, i < back.count ? back[i] : last)
            }
        }
        return out
    }

    /// Рост в метрах сцены с поправкой scale (Шиба — base).
    static func height(_ c: CharacterConfig?, base: Double) -> Double {
        base * (c?.scale ?? 1)
    }

    // MARK: размер тела для хореографии

    /// Шиба после нормировки на рост 0,42 м: длина (морда…хвост) и ширина пятна на полу — по мешу shiba.usdz.
    static let shibaLength = 0.53
    static let shibaWidth = 0.15

    /// Насколько тело персонажа больше Шибы: по росту, по длине и по ширине (1 — как у Шибы), плюс подъём над полом.
    /// Им хореография двигает точки «от морды»: миска под мордой, находка в пасти, где он встаёт перед мячом.
    /// length и width — замер рамки модели после нормировки на рост, а не scale: у таксы рост маленький,
    /// а морда далеко. Замера нет (модель пустая, Шиба) — как рост.
    static func body(height: Double, base: Double, length: Double?, width: Double?, lift: Double = 0) -> PetBody {
        let k = base > 0 && height.isFinite && height > 0 ? height / base : 1
        func ratio(_ v: Double?, _ ref: Double) -> Double {
            guard let v, v.isFinite, v > 0 else { return k }
            // Рамка с хвостом торчком или лапами в стороны бывает вдвое больше тела — не даём уйти совсем далеко.
            return min(max(v / ref, k * 0.5), k * 2)
        }
        return PetBody(height: k, length: ratio(length, shibaLength),
                       width: ratio(width, shibaWidth), lift: lift.isFinite ? lift : 0)
    }

    private static func num(_ x: Double) -> String {
        guard x.isFinite else { return "\(x)" }
        let s = x == x.rounded() ? String(Int(x)) : String(format: "%.2f", x)
        return s.replacingOccurrences(of: ".", with: ",")
    }

    // MARK: тестовый пак

    /// Таймлайн в формате shiba.clips.json (лишние поля — frames, source — пропускаются).
    struct Timeline: Decodable, Sendable {
        var fps: Double
        var clips: [String: CharacterConfig.Range]
    }

    /// Пак из таймлайна Шибы для UI-тестов и примера в DECISIONS: клипы в файле под другими именами
    /// (sit_in → SitIn) и rename обратно, рост 0,8, серая шерсть. without — каких наших клипов не класть.
    static func sample(_ t: Timeline, name: String = "Серый Шиба", without: Set<String> = []) -> CharacterConfig {
        var clips: [String: CharacterConfig.Range] = [:]
        var rename: [String: String] = [:]
        for (our, r) in t.clips where !without.contains(our) {
            let theirs = camel(our)
            clips[theirs] = r
            rename[our] = theirs
        }
        return CharacterConfig(format: format, name: name, author: "Питомец (тест)", license: "CC0",
                               model: defaultModel, scale: 0.8, lift: 0, yaw: 0, fps: t.fps, clips: clips,
                               rename: rename, bones: nil, color: "#8B8F99", deathShift: -1.36)
    }

    /// sit_in → SitIn.
    static func camel(_ s: String) -> String {
        s.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
}
