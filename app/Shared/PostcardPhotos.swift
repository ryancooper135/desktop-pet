// Кадры для «Открытки дня» (RESEARCH/06 #8, волна 10). В удачный момент ухода (поел, поиграл, погладили,
// трюк вышел, вернулся с находкой) приложение тихо снимает 3D-сцену (PostcardCamera) и кладёт маленький JPEG
// в Paths.dir/photos. В сейве только имя файла: кадры дня — SaveFile.shots, кадр открытки — Postcard.image.
//
// Правила (чистая логика, тесты в PostcardPhotosTests):
//  • за местные сутки не больше shotsPerDay снимков и не больше keepPerDay лежащих кадров;
//  • между снимками не меньше minGap; внутри этого окна лучший момент заменяет только что снятый;
//  • тип момента уже есть — второй такой же не снимаем (кадры дня разные);
//  • места нет — новый кадр вытесняет худший (меньше очков, при равных — старший), если сам лучше.
// Когда после полуночи собирается открытка (Postcards.refresh), ей достаётся кадр того же момента
// (ближайший по времени), иначе лучший кадр дня. Остальные кадры прошедших дней выбрасываются.
// Файлы, на которые больше никто не ссылается (открытка пропала, удалена, выброшена), приложение удаляет
// по orphans — так кадры чистятся вместе с открытками.
//
// Только Foundation и PetCore: гоняется на Linux (app/Package.swift).

import Foundation
@preconcurrency import PetCore

/// Кадр дня: снят в момент kind, лежит файлом file в каталоге кадров.
struct PostcardShot: Codable, Hashable, Sendable {
    /// Местный день снимка (Postcards.day по поясу хозяина).
    let day: Int
    /// MomentKind.rawValue строкой: тип из будущей версии не теряется.
    let kind: String
    let t: Double
    let score: Int
    /// Имя файла в Paths.dir/photos, без пути.
    let file: String

    var momentKind: MomentKind? { MomentKind(rawValue: kind) }
}

/// Кадры ещё не разобранных дней и счётчик снимков за текущие сутки. Верхнее поле SaveFile.shots,
/// пустое в файл не пишется.
struct ShotBook: Codable, Hashable, Sendable {
    var items: [PostcardShot] = []
    /// Сутки, за которые считаем taken.
    var day: Int?
    /// Сколько кадров за сутки day уже сняли (включая вытесненные).
    var taken = 0

    init() {}

    var isEmpty: Bool { items.isEmpty && day == nil && taken == 0 }

    enum CodingKeys: String, CodingKey { case items, day, taken }

    /// Один битый кадр не валит остальные.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = ((try? c.decodeIfPresent([LossyShot].self, forKey: .items)) ?? []).compactMap(\.value)
        day = try? c.decodeIfPresent(Int.self, forKey: .day)
        taken = (try? c.decodeIfPresent(Int.self, forKey: .taken)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(day, forKey: .day)
        if taken != 0 { try c.encode(taken, forKey: .taken) }
    }
}

private struct LossyShot: Decodable {
    let value: PostcardShot?
    init(from decoder: Decoder) throws { value = try? PostcardShot(from: decoder) }
}

enum PostcardPhotos {
    // MARK: настройки

    /// Каталог кадров рядом с сейвом (Paths.dir/photos).
    static let folder = "photos"
    /// Длинная сторона кадра, px. JPEG ~30–60 КБ.
    static let maxSide = 512
    static let jpegQuality = 0.8
    /// Кадр 4:3, как окошко открытки.
    static let aspect = 4.0 / 3.0
    /// Сколько кадров за сутки лежит одновременно.
    static let keepPerDay = 3
    /// Сколько раз за сутки вообще снимаем (вытесненные тоже считаются): камера не дёргается на каждый тап.
    static let shotsPerDay = 8
    /// Пауза между снимками.
    static let minGap: Double = 15 * 60
    /// Файл без ссылки моложе этого не трогаем: кадр мог только что лечь на диск и ещё не попасть в сейв.
    static let orphanGrace: Double = 10 * 60

    // MARK: какой момент

    /// Тип момента для удачного действия из приложения. nil — не снимаем (лечение, «разбудил», шаги, прогулка).
    static func kind(forAction kind: String, key: String?) -> MomentKind? {
        switch kind {
        case "feed": return (key ?? Catalog.mainFood) == Catalog.mainFood ? .feed : .treat
        // блюдо с кухни — тоже угощение
        case Cooking.reactKind: return .treat
        case "play": return .play
        case "pet": return .pets
        case "bath": return .bath
        default: return nil
        }
    }

    /// Трюк получился — для открытки это игра (своего типа момента у трюков нет).
    static let trickKind: MomentKind = .play
    /// Вернулся с прогулки с находкой.
    static let walkKind: MomentKind = .find

    /// Очки кадра — как у момента открытки.
    static func score(_ k: MomentKind) -> Int { Postcards.scores[k] ?? 10 }

    // MARK: снимать ли

    enum Plan: Equatable, Sendable {
        /// Не снимаем; причина для логов и тестов.
        case skip(String)
        /// Снимаем и кладём рядом с остальными.
        case add
        /// Снимаем и выбрасываем этот кадр.
        case replace(String)

        var shoots: Bool { if case .skip = self { return false } else { return true } }
    }

    /// Стоит ли снимать момент kind в момент now (сутки — по поясу хозяина).
    static func plan(_ f: SaveFile, kind: MomentKind, now: Double) -> Plan {
        plan(f.shots, kind: kind, now: now, day: Postcards.day(now, tzOffsetMin: f.owner.tzOffsetMin))
    }

    static func plan(_ book: ShotBook, kind: MomentKind, now: Double, day: Int) -> Plan {
        let taken = book.day == day ? book.taken : 0
        if taken >= shotsPerDay { return .skip("day_limit") }
        let today = book.items.filter { $0.day == day }
        let s = score(kind)
        if let last = today.max(by: { $0.t < $1.t }), now - last.t < minGap {
            // Тот же «всплеск» ухода: поел, потом поиграл — остаётся лучший момент.
            let other = today.contains { $0.kind == kind.rawValue && $0.file != last.file }
            if s > last.score, last.kind != kind.rawValue, !other { return .replace(last.file) }
            return .skip("too_soon")
        }
        if today.contains(where: { $0.kind == kind.rawValue }) { return .skip("have_kind") }
        if today.count < keepPerDay { return .add }
        guard let worst = today.min(by: worse) else { return .add }
        return s > worst.score ? .replace(worst.file) : .skip("not_better")
    }

    /// a хуже b: меньше очков, при равных — раньше снят.
    private static func worse(_ a: PostcardShot, _ b: PostcardShot) -> Bool {
        a.score != b.score ? a.score < b.score : a.t < b.t
    }

    /// Имя файла кадра: стабильно от дня и секунды, без личных данных.
    static func fileName(day: Int, t: Double, kind: MomentKind) -> String {
        "s\(day)-\(Int(t.rounded()))-\(kind.rawValue).jpg"
    }

    /// Кадр снят и лежит на диске: записать в сейв. План перепроверяется (между снимком и записью мог прийти
    /// другой процесс). Возвращает файлы, которые больше не нужны (вытесненный кадр или сам новый, если опоздал).
    @discardableResult
    static func commit(_ shot: PostcardShot, in f: inout SaveFile) -> [String] {
        let k = shot.momentKind ?? .play
        let p = plan(f.shots, kind: k, now: shot.t, day: shot.day)
        var drop: [String] = []
        switch p {
        case .skip:
            return [shot.file]
        case .add:
            break
        case .replace(let old):
            f.shots.items.removeAll { $0.file == old }
            drop.append(old)
        }
        if f.shots.day != shot.day { f.shots.day = shot.day; f.shots.taken = 0 }
        f.shots.taken += 1
        f.shots.items.append(shot)
        return drop
    }

    // MARK: кадр открытке

    /// Какие типы кадров подходят к открытке этого типа (еда к еде, находка к находке…).
    static func matching(_ cardKind: String) -> Set<String> {
        switch MomentKind(rawValue: cardKind) {
        case .feed, .treat: return [MomentKind.feed.rawValue, MomentKind.treat.rawValue]
        case .find, .findFirst: return [MomentKind.find.rawValue, MomentKind.findFirst.rawValue]
        case .pets, .rescue: return [MomentKind.pets.rawValue]
        case .play: return [MomentKind.play.rawValue]
        case .bath: return [MomentKind.bath.rawValue]
        default: return []
        }
    }

    /// Кадр для открытки: того же момента и ближайший по времени, иначе лучший кадр дня. nil — кадров нет.
    static func pick(for card: Postcard, among shots: [PostcardShot]) -> PostcardShot? {
        let day = shots.filter { $0.day == card.day }
        let same = matching(card.kind)
        if let m = day.filter({ same.contains($0.kind) }).min(by: { abs($0.t - card.t) < abs($1.t - card.t) }) {
            return m
        }
        return day.max(by: worse)
    }

    /// Разобрать кадры при сборке открыток (зовёт Postcards.refresh): новым открыткам — кадр, кадры прошедших
    /// дней из книжки убрать (их файлы станут сиротами, если открытке не достались).
    static func settle(_ f: inout SaveFile, made ids: [String], today: Int) {
        guard !f.shots.items.isEmpty else { return }
        for id in ids {
            guard let i = f.cards.pending.firstIndex(where: { $0.id == id }), f.cards.pending[i].image == nil,
                  let s = pick(for: f.cards.pending[i], among: f.shots.items) else { continue }
            f.cards.pending[i].image = s.file
        }
        f.shots.items.removeAll { $0.day < today }
    }

    // MARK: уборка

    /// Файлы, на которые ссылается сейв: кадры открыток (ждущих и альбома) и кадры дня.
    static func liveFiles(_ f: SaveFile) -> Set<String> {
        var s = Set(f.shots.items.map(\.file))
        for c in f.cards.pending + f.cards.album { if let i = c.image { s.insert(i) } }
        return s
    }

    /// Что удалить из каталога кадров: наши .jpg без ссылки, старше orphanGrace. files — имя → время изменения.
    static func orphans(_ files: [String: Double], live: Set<String>, now: Double) -> [String] {
        files.filter { name, mtime in
            name.hasSuffix(".jpg") && !live.contains(name) && now - mtime >= orphanGrace
        }.map(\.key).sorted()
    }

    /// Кадр 4:3 из картинки w×h: прямоугольник обрезки (x, y, ширина, высота) вокруг точки центра (доли 0…1).
    /// Окно — во всю ширину (или высоту, если картинка шире 4:3), не выходит за края.
    static func crop(width w: Double, height h: Double, centerX cx: Double = 0.5, centerY cy: Double)
        -> (x: Double, y: Double, w: Double, h: Double) {
        guard w > 0, h > 0 else { return (0, 0, 0, 0) }
        var cw = w, ch = w / aspect
        if ch > h { ch = h; cw = h * aspect }
        let x = min(max(0, w * cx - cw / 2), w - cw)
        let y = min(max(0, h * cy - ch / 2), h - ch)
        return (x, y, cw, ch)
    }

    /// Размер кадра на диске: длинная сторона не больше maxSide, пропорции сохраняются.
    static func fitted(width w: Double, height h: Double) -> (w: Int, h: Int) {
        guard w > 0, h > 0 else { return (0, 0) }
        let k = min(1, Double(maxSide) / max(w, h))
        return (max(1, Int((w * k).rounded())), max(1, Int((h * k).rounded())))
    }
}

// MARK: - срок открытки

extension Postcards {
    /// Сколько осталось жить несохранённой открытке, с. Сохранённая — бессрочно (nil).
    static func timeLeft(_ c: Postcard, now: Double) -> Double? {
        c.isSaved ? nil : max(0, c.expiresT - now)
    }

    /// Последние сутки несохранённой открытки: пора мягко напомнить.
    static func isLastDay(_ c: Postcard, now: Double) -> Bool {
        guard let left = timeLeft(c, now: now) else { return false }
        return left > 0 && left <= 86400
    }

    /// Сколько суток осталось (с округлением вверх): 7 в день появления, 1 в последний день, 0 — пропала.
    static func daysLeft(_ c: Postcard, now: Double) -> Int? {
        guard let left = timeLeft(c, now: now) else { return nil }
        return Int((left / 86400).rounded(.up))
    }

    /// Строка под открыткой: сколько ещё ждёт, или мягкое «последний день». Сохранённая или пропавшая — nil.
    static func expiryNote(_ c: Postcard, now: Double) -> String? {
        guard let n = daysLeft(c, now: now), n > 0 else { return nil }
        if n == 1 { return lastDayNote }
        return "Не сохранишь — пропадёт через \(n) \(daysWord(n))."
    }

    static let lastDayNote = "Сегодня последний день: сохрани, а то пропадёт."
    /// Коротко для карточки на главной.
    static let lastDayChip = "последний день"

    /// 1 день, 2 дня, 5 дней, 21 день.
    static func daysWord(_ n: Int) -> String { EconText.plural(n, "день", "дня", "дней") }
}
