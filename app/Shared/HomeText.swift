// Тексты главного экрана без SwiftUI (гоняются на Linux): спокойный таймер под репликой,
// когда ему обновляться и какой высоты лист шкал.

import Foundation

enum HomeText {
    /// Остаток без секунд: «2 ч 51 мин», «40 мин», «2 ч»; меньше минуты (и после конца) — «меньше минуты».
    /// Минуты вниз: при 2:51:59 — «2 ч 51 мин», как на часах.
    static func calmRemaining(_ seconds: Double) -> String {
        guard seconds >= 60 else { return "меньше минуты" }
        let total = Int((seconds / 60).rounded(.down))
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) мин" }
        if m == 0 { return "\(h) ч" }
        return "\(h) ч \(m) мин"
    }

    /// Таймер под репликой: «Испачкается через 2 ч 51 мин», «Моется ещё 4 мин».
    /// Меньше минуты: «Испачкается меньше чем через минуту», «Моется ещё меньше минуты». Пустой title — без него.
    static func calmTimer(kind: String, title: String, remaining: Double) -> String {
        let prefix = Presenter.timerPrefix(kind: kind)
        let tail: String
        if remaining < 60 {
            tail = prefix == "через" ? "меньше чем через минуту" : "\(prefix) меньше минуты"
        } else {
            tail = "\(prefix) \(calmRemaining(remaining))"
        }
        return title.isEmpty ? tail : "\(title) \(tail)"
    }

    /// Когда текст таймера сменится: ближайший момент после t, где остаток до end только что перешёл кратное минуты.
    /// Так «40 мин» становится «39 мин» в свою секунду, а не до минуты позже. Ровно на границе остаток ещё
    /// «40 мин» (минуты вниз), поэтому тик чуть позже границы — на tickLag. После конца — раз в минуту.
    static let tickLag = 0.05

    static func nextChange(after t: Double, end: Double) -> Double {
        let r = end - t
        guard r > 0 else { return t + 60 }
        let k = (r / 60).rounded(.down)
        let next = end - k * 60 + tickLag
        return next > t ? next : end - (k - 1) * 60 + tickLag
    }

    /// Что делает питомец, для VoiceOver: «Шиба спокоен». Имя уже внутри фразы.
    /// Свой персонаж (волна 14) — его имя в именительном и слова без рода: «Мурка отдыхает», а не «спокоен».
    static func poseText(_ pose: Pose, name: String = PetNames.shiba) -> String {
        if PetNames.isShiba(name) { return shibaPoseText(pose) }
        switch pose {
        case .happy: return "\(name) радуется"
        case .idle: return "\(name) отдыхает"
        case .eating: return "\(name) ест"
        case .loved: return "\(name) жмурится от ласки"
        case .sleep: return "\(name) спит"
        case .nap: return "\(name) дремлет"
        case .bath: return "\(name) моется"
        case .hungry: return "\(name) хочет есть"
        case .dirty: return "\(name) в пыли — пора мыться"
        case .tired: return "\(name) без сил"
        case .bored: return "\(name) хочет играть"
        case .lonely: return "\(name) скучает по тебе"
        case .sulky: return "\(name) дуется"
        case .critical: return "\(name): совсем плохо"
        case .dead: return PetNames.gone(name)
        case .away: return "\(name) гуляет"
        }
    }

    private static func shibaPoseText(_ pose: Pose) -> String {
        switch pose {
        case .happy: return "Шиба радуется"
        case .idle: return "Шиба спокоен"
        case .eating: return "Шиба ест"
        case .loved: return "Шибе приятно"
        case .sleep: return "Шиба спит"
        case .nap: return "Шиба дремлет"
        case .bath: return "Шиба моется"
        case .hungry: return "Шиба голодный"
        case .dirty: return "Шиба испачкался"
        case .tired: return "Шиба устал"
        case .bored: return "Шибе скучно"
        case .lonely: return "Шиба скучает по тебе"
        case .sulky: return "Шиба обиделся"
        case .critical: return "Шибе очень плохо"
        case .dead: return "Шибы больше нет"
        case .away: return "Шиба ушёл гулять"
        }
    }

    /// Подпись сцены для VoiceOver. Фраза позы уже называет питомца («Шиба спокоен», «Мурка отдыхает»),
    /// поэтому имя отдельно спереди не ставим (раньше выходило «Шиба: Шиба спокоен»).
    static func stageLabel(name: String, pose: Pose) -> String {
        poseText(pose, name: name)
    }

    /// Высота листа под содержимое (detent .height): немного запаса на округление,
    /// но не меньше minHeight — пустой лист-щёлочку не показываем.
    static func sheetHeight(content: Double, minHeight: Double = 200) -> Double {
        max(minHeight, (content + 8).rounded(.up))
    }
}
