// Отклик на касание (волна 29): какой вид вибрации у какого события и когда отклик молчит.
// Чистая логика без UIKit — идёт и на Linux (app/Package.swift). Сами генераторы и звук — App/FeelKit.swift.
// Виджетам отклик не нужен (и SoundCue у них нет): файл собирается только в приложение и в пакет логики.
//
// Словарь видов (RESEARCH/15-feedback.md):
//   select  — выбор/смена значения (клетка-превью в Блок Дуо, свой персонаж);
//   tap     — нажали кнопку, результат будет позже (трюк, отбой, «Готово»);
//   soft    — касание тела питомца (тап, тики ласки, мазок щёткой);
//   bump    — заметный толчок (щекотка, капсула упала, ход Шибы, большой зомби);
//   nudge   — мягкое «не то» внутри игры (промах, обнял зомби, против шерсти);
//   success — получилось (ядро приняло, купили, выиграли);
//   denied  — нельзя/недоступно/отказ: всегда с «не-а», а не тишина.

#if APP_TARGET || SWIFT_PACKAGE
import Foundation

enum FeelKind: String, CaseIterable, Sendable {
    case select, tap, soft, bump, nudge, success, denied

    /// Минимальный промежуток между двумя откликами этого вида, с. Чаще — пулемёт, а не отклик.
    var cooldown: Double {
        switch self {
        case .select: return 0.05
        case .tap, .soft: return 0.08
        case .bump: return 0.15
        case .nudge: return 0.2
        case .success: return 0.4
        case .denied: return 0.6
        }
    }

    /// Сила: в одном кадре (FeelGate.sameFrame) слабый отклик после равного или сильного не нужен.
    var rank: Int {
        switch self {
        case .select: return 0
        case .tap, .soft: return 1
        case .bump, .nudge: return 2
        case .success, .denied: return 3
        }
    }

    /// Из двух — более сильный (одна вибрация на кадр игры). Равные — новый.
    static func strongest(_ a: FeelKind?, _ b: FeelKind) -> FeelKind {
        guard let a else { return b }
        return a.rank > b.rank ? a : b
    }
}

extension SoundCue {
    /// Ключ кулдауна звука: тики ласки — один ключ на все n.
    var feelKey: String {
        if case .petTick = self { return "petTick" }
        return String(describing: self)
    }
}

/// Решает, звучать ли отклику. Время — секунды на любой монотонной шкале (в приложении — ProcessInfo.systemUptime).
struct FeelGate: Sendable {
    /// Ключи UserDefaults. «Звук» — переключатель в настройках (SoundKit.enabledKey);
    /// «Вибрация» — пока без переключателя, по умолчанию включена (вопрос Вадиму, PROGRESS).
    static let soundKey = "sound.on"
    static let hapticsKey = "haptics.on"
    /// После возврата из фона фоновые отклики (сердца, вернулся с прогулки) молчат: снимок догоняет время.
    static let wakeQuiet: Double = 2
    /// Одинаковый звук чаще этого — одно касание дважды (двойной вызов), а не два события.
    static let soundCooldown: Double = 0.07
    /// «Один кадр» для слабого отклика после сильного.
    static let sameFrame: Double = 0.05

    var haptics = true
    var sound = true
    /// Приложение на экране. В фоне — ни вибрации, ни звука.
    private(set) var active = true
    private(set) var wokeAt: Double? = nil
    private var lastKind: [FeelKind: Double] = [:]
    private var lastAny: (rank: Int, t: Double)? = nil
    private var lastSound: [String: Double] = [:]

    mutating func becameActive(at t: Double) {
        active = true
        wokeAt = t
    }

    mutating func wentBackground() {
        active = false
    }

    /// Фоновый отклик (не от пальца) в первые секунды после возврата из фона молчит.
    func quietAfterWake(at t: Double) -> Bool {
        guard let wokeAt else { return false }
        return t - wokeAt < Self.wakeQuiet
    }

    /// Пропустить вибрацию вида kind в момент t? Если да — запомнить её.
    mutating func allowHaptic(_ kind: FeelKind, at t: Double, ambient: Bool = false) -> Bool {
        guard haptics, active else { return false }
        if ambient, quietAfterWake(at: t) { return false }
        if let last = lastKind[kind], t - last < kind.cooldown { return false }
        if let any = lastAny, t - any.t < Self.sameFrame, any.rank >= kind.rank { return false }
        lastKind[kind] = t
        lastAny = (kind.rank, t)
        return true
    }

    /// Пропустить звук cue в момент t? Если да — запомнить его.
    mutating func allowSound(_ cue: SoundCue, at t: Double, ambient: Bool = false) -> Bool {
        guard sound, active else { return false }
        if ambient, quietAfterWake(at: t) { return false }
        let key = cue.feelKey
        if let last = lastSound[key], t - last < Self.soundCooldown { return false }
        lastSound[key] = t
        return true
    }

    /// Настройки из UserDefaults: нет значения — включено.
    static func enabled(_ key: String, in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
#endif
