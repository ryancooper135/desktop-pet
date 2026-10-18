// Звуки питомца без файлов: рецепты нот для синтезатора (Synth.swift), всё в одной тональности —
// до-мажорная пентатоника (до, ре, ми, соль, ля). Любые две ноты из неё звучат вместе мило, поэтому
// звуки могут налезать друг на друга (хруст поверх тявка) и не резать слух.
//
// Здесь только числа: нотная таблица, огибающая, рецепты. Никакого AVFoundation — проверяется тестами
// и на Linux (app/Package.swift). Проигрывает SoundKit в приложении; виджетам это не нужно,
// поэтому файл собирается только в приложение (APP_TARGET) и в пакет логики (SWIFT_PACKAGE).

#if APP_TARGET || SWIFT_PACKAGE
import Foundation

/// Форма волны голоса. Шум — для хруста; высота у шума — частота среза фильтра.
enum Wave: UInt8, Sendable {
    case sine, triangle, square, noise
}

/// Огибающая громкости: линейный подъём, полка, спад по квадрату (как затухающий щипок).
struct Envelope: Sendable, Equatable {
    var attack: Double
    var hold: Double
    var release: Double

    /// Минимальный подъём, с которым нота не щёлкает в начале.
    static let minAttack = 0.001

    var length: Double { attack + hold + release }

    /// Громкость 0…1 через t секунд после начала ноты.
    func level(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t < attack { return t / attack }
        let r = t - attack - hold
        if r <= 0 { return 1 }
        if r >= release { return 0 }
        let x = 1 - r / release
        return x * x
    }
}

/// Одна нота рецепта. Время — от момента, когда звук попросили.
struct Tone: Sendable, Equatable {
    /// Задержка от начала звука, секунды.
    var at: Double
    var wave: Wave
    /// Начальная высота, Гц (у шума — срез фильтра).
    var freq: Double
    /// Куда скользит высота; без скольжения — та же freq.
    var glideTo: Double
    /// За сколько секунд скользит (экспоненциально, по полутонам ровно).
    var glide: Double
    var env: Envelope
    /// Громкость ноты до общего ограничителя, 0…1.
    var gain: Double
    /// Срез однополюсного фильтра, Гц; 0 — без фильтра. Смягчает квадрат и шум.
    var cutoff: Double
    /// Нота хореографии (мяч, хруст): её можно отменить, если анимацию перебили (SynthCore.cancelChoreo).
    var choreo = false

    /// Когда нота замолкает целиком.
    var end: Double { at + env.length }

    init(at: Double = 0, _ wave: Wave, _ freq: Double, to glideTo: Double? = nil, glide: Double = 0,
         env: Envelope, gain: Double, cutoff: Double = 0) {
        self.at = at
        self.wave = wave
        self.freq = freq
        self.glideTo = glideTo ?? freq
        self.glide = glide
        self.env = env
        self.gain = gain
        self.cutoff = cutoff
    }
}

// MARK: - нотная таблица

/// До-мажорная пентатоника. Ступень 0 — до первой октавы (C4, MIDI 60), 1 — ре, 2 — ми, 3 — соль, 4 — ля,
/// 5 — до второй октавы и так далее; отрицательные — вниз.
enum Scale {
    /// Полутона ступеней от «до».
    static let degrees = [0, 2, 4, 7, 9]
    static let root = 60
    /// Диапазон таблицы: от до большой октавы (C2) до до пятой (C8).
    static let lowest = -10
    static let highest = 20

    /// Частоты всех ступеней заранее: рецепты не считают степени на каждый звук.
    static let table: [Double] = (lowest...highest).map { hz(midi: midi($0)) }

    static func midi(_ step: Int) -> Int {
        let n = degrees.count
        let octave = step >= 0 ? step / n : -((-step + n - 1) / n)
        let degree = step - octave * n
        return root + 12 * octave + degrees[degree]
    }

    static func hz(midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    /// Частота ступени из таблицы; за краем таблицы — крайняя нота.
    static func note(_ step: Int) -> Double {
        table[min(max(step, lowest), highest) - lowest]
    }

    /// Нота частоты f попадает в тональность (с точностью 1 цент).
    static func isInKey(_ f: Double) -> Bool {
        guard f > 0 else { return false }
        let m = 69 + 12 * log2(f / 440)
        let r = m.rounded()
        guard abs(m - r) < 0.01 else { return false }
        let pc = ((Int(r) % 12) + 12) % 12
        return degrees.contains(pc)
    }
}

// MARK: - звуки

/// Что прозвучало. Набор звуков приложения; ноты — в SoundRecipe.tones.
enum SoundCue: Sendable, Hashable {
    /// Нажатие кнопки: еле слышный тик.
    case button
    /// Тап по питомцу: мягкий «буп» в нос.
    case boop
    /// Тик ласки: лесенка вверх по пентатонике, n — номер тика с начала жеста.
    case petTick(Int)
    /// Погладили и ядро приняло: мягкое чириканье вверх и три сердечка-капли.
    case pet
    /// Покормили: два «плинька» корма в миску (хруст — во время еды, SoundRecipe.eat).
    case feed
    /// Тявк-тявк: радость, «Поиграть», щекотка.
    case yip
    /// Помыли: пузыри.
    case bath
    /// Отказ: две низкие ноты «не-а».
    case refuse
    /// Прочее удачное действие: короткое «динь-динь» вверх.
    case ok
    /// Разбудили: сонное скольжение вверх.
    case wake
    /// Сердце вернулось: арпеджио вверх.
    case hearts
    /// Сердце потеряно: две ноты вниз.
    case heartLost
    /// Новый щенок: арпеджио и тявк.
    case hello
    /// Смерть: тихое нисхождение.
    case death
    /// Мазок расчёской: мягкое «шорх» — два шумовых всплеска, светлый и потемнее.
    case brush
    /// Дочесали: пёс отряхивается — «фррр» и «динь» вверх.
    case brushDone
}

enum SoundRecipe {
    /// Обычный звук не длиннее этого (RESEARCH/08 §3: «все звуки короче 0,6 с»). Длиннее — только смерть
    /// и хореография (еда, мяч), они идут вместе с анимацией.
    static let maxLength = 0.6

    private static func n(_ step: Int) -> Double { Scale.note(step) }

    /// Звук на ответ ядра по виду действия; nil — молчать (шаги приходят не с экрана).
    static func forAction(kind: String, ok: Bool) -> SoundCue? {
        guard ok else { return .refuse }
        switch kind {
        case "feed": return .feed
        case "pet": return .pet
        case "play", "walk": return .yip
        case "bath": return .bath
        case "wake": return .wake
        case "steps": return nil
        default: return .ok
        }
    }

    static func tones(_ cue: SoundCue) -> [Tone] {
        switch cue {
        case .button:
            return [Tone(.sine, n(10), env: Envelope(attack: 0.001, hold: 0, release: 0.03), gain: 0.05)]

        case .boop:
            return [Tone(.triangle, n(5), to: n(7), glide: 0.04,
                         env: Envelope(attack: 0.003, hold: 0.01, release: 0.08), gain: 0.18)]

        case .petTick(let i):
            // Лесенка от до второй октавы на 7 ступеней вверх, дальше держится наверху.
            let step = 5 + min(max(i - 1, 0), 7)
            return [Tone(.sine, n(step), env: Envelope(attack: 0.004, hold: 0, release: 0.09), gain: 0.07)]

        case .pet:
            // Сердечки всплывают через 0, 120 и 240 мс (AppModel.heartBurst) — капли следом за чириканьем.
            var out = [Tone(.sine, n(3), to: n(5), glide: 0.12,
                            env: Envelope(attack: 0.02, hold: 0.04, release: 0.15), gain: 0.22)]
            for (i, step) in [12, 13, 14].enumerated() {
                out.append(Tone(at: 0.1 + 0.12 * Double(i), .triangle, n(step),
                                env: Envelope(attack: 0.002, hold: 0, release: 0.12), gain: 0.08))
            }
            return out

        case .feed:
            return [
                Tone(.triangle, n(8), env: Envelope(attack: 0.002, hold: 0.01, release: 0.12), gain: 0.16),
                Tone(at: 0.09, .triangle, n(10), env: Envelope(attack: 0.002, hold: 0.01, release: 0.14), gain: 0.16),
            ]

        case .yip:
            // Квадрат через фильтр — «голос»; быстрый подъём высоты делает из ноты тявк.
            return [
                Tone(.square, n(7), to: n(9), glide: 0.04,
                     env: Envelope(attack: 0.004, hold: 0.03, release: 0.07), gain: 0.14, cutoff: 2400),
                Tone(at: 0.13, .square, n(8), to: n(10), glide: 0.035,
                     env: Envelope(attack: 0.003, hold: 0.02, release: 0.06), gain: 0.12, cutoff: 2400),
            ]

        case .bath:
            // Пузырь — синус, который быстро скользит вверх на три ступени.
            let at = [0, 0.06, 0.13, 0.19, 0.3]
            let steps = [5, 7, 6, 9, 8]
            return zip(at, steps).map { t, s in
                Tone(at: t, .sine, n(s), to: n(s + 3), glide: 0.05,
                     env: Envelope(attack: 0.003, hold: 0.01, release: 0.05), gain: 0.13)
            }

        case .brush:
            return [
                Tone(.noise, 3400, env: Envelope(attack: 0.025, hold: 0.04, release: 0.09), gain: 0.16, cutoff: 3400),
                Tone(at: 0.05, .noise, 1700, env: Envelope(attack: 0.02, hold: 0.03, release: 0.12), gain: 0.14,
                     cutoff: 1700),
            ]

        case .brushDone:
            // Отряхивается: светлый и тёмный шумовые всплески по очереди.
            var out: [Tone] = []
            for i in 0..<4 {
                let cut: Double = i % 2 == 0 ? 2400 : 1500
                let flick = Envelope(attack: 0.008, hold: 0.02, release: 0.05)
                out.append(Tone(at: 0.07 * Double(i), .noise, cut, env: flick, gain: 0.15, cutoff: cut))
            }
            out.append(Tone(at: 0.3, .triangle, n(8), env: Envelope(attack: 0.002, hold: 0.01, release: 0.1), gain: 0.12))
            out.append(Tone(at: 0.38, .triangle, n(10), env: Envelope(attack: 0.002, hold: 0.01, release: 0.16), gain: 0.12))
            return out

        case .refuse:
            return [
                Tone(.square, n(-1), env: Envelope(attack: 0.005, hold: 0.06, release: 0.08), gain: 0.14, cutoff: 900),
                Tone(at: 0.15, .square, n(-3), env: Envelope(attack: 0.005, hold: 0.07, release: 0.1), gain: 0.14, cutoff: 900),
            ]

        case .ok:
            return [
                Tone(.triangle, n(5), env: Envelope(attack: 0.002, hold: 0.01, release: 0.1), gain: 0.15),
                Tone(at: 0.08, .triangle, n(8), env: Envelope(attack: 0.002, hold: 0.01, release: 0.14), gain: 0.15),
            ]

        case .wake:
            return [Tone(.triangle, n(0), to: n(5), glide: 0.25,
                         env: Envelope(attack: 0.05, hold: 0.1, release: 0.2), gain: 0.15, cutoff: 2000)]

        case .hearts:
            return arpeggio([5, 7, 8, 10])

        case .heartLost:
            return [
                Tone(.triangle, n(4), env: Envelope(attack: 0.01, hold: 0.08, release: 0.15), gain: 0.12, cutoff: 1800),
                Tone(at: 0.18, .triangle, n(2), env: Envelope(attack: 0.01, hold: 0.08, release: 0.2), gain: 0.12, cutoff: 1800),
            ]

        case .hello:
            return arpeggio([5, 7, 8, 10]) + tones(.yip).map { var t = $0; t.at += 0.3; return t }

        case .death:
            // Соль, ми, ре, до — и последняя тихо сползает к соли малой октавы.
            var out: [Tone] = []
            for (i, step) in [3, 2, 1].enumerated() {
                out.append(Tone(at: 0.28 * Double(i), .triangle, n(step),
                                env: Envelope(attack: 0.02, hold: 0.1, release: 0.3), gain: 0.13, cutoff: 1500))
            }
            out.append(Tone(at: 0.84, .triangle, n(0), to: n(-2), glide: 0.6,
                            env: Envelope(attack: 0.02, hold: 0.2, release: 0.7), gain: 0.13, cutoff: 1500))
            return out
        }
    }

    /// Арпеджио вверх по ступеням, 70 мс между нотами.
    static func arpeggio(_ steps: [Int]) -> [Tone] {
        steps.enumerated().map { i, s in
            Tone(at: 0.07 * Double(i), .triangle, n(s),
                 env: Envelope(attack: 0.002, hold: 0.02, release: 0.18), gain: 0.13)
        }
    }

    // MARK: хореография

    /// Высота отскока мяча (м) → ступень «бульк»: выше прыгнул — сильнее упал — выше и громче нота.
    /// Самый высокий отскок в игре 0,16 м.
    static func bounceStep(_ height: Double) -> Int {
        5 + min(max(Int((height / 0.16 * 4).rounded()), 0), 5)
    }

    /// «Бульк» удара мяча о пол: короткий синус, высота скользит вниз на две ступени.
    static func bloop(at t: Double, height: Double) -> Tone {
        let s = bounceStep(height)
        return Tone(at: t, .sine, n(s), to: n(s - 2), glide: 0.06,
                    env: Envelope(attack: 0.002, hold: 0.02, release: 0.09),
                    gain: min(0.08 + 0.9 * height, 0.24))
    }

    /// Игра с мячом (PetChoreo, ChoreoPath.Play), всё от начала play_bow + start:
    /// пинок в kick, удары после каждого отскока bounces (длительность, высота), тычок лапой в knock.
    static func ball(start: Double, kick: Double, bounces: [(duration: Double, height: Double)],
                     knock: Double, knockHeight: Double = 0.04) -> [Tone] {
        var out = [Tone(at: start + kick, .triangle, n(3), to: n(8), glide: 0.08,
                        env: Envelope(attack: 0.003, hold: 0.02, release: 0.1), gain: 0.14)]
        var t = start + kick
        for b in bounces {
            t += b.duration
            out.append(bloop(at: t, height: b.height))
        }
        out.append(bloop(at: start + knock, height: knockHeight))
        return choreo(out)
    }

    /// Обычный звук позже на offset секунд, как нота хореографии: его снимает cancelChoreo, если
    /// анимацию перебили («Голос»: тявк на прыжке, а не на нажатии).
    static func delayed(_ cue: SoundCue, by offset: Double) -> [Tone] {
        choreo(tones(cue).map { var t = $0; t.at += max(0, offset); return t })
    }

    private static func choreo(_ tones: [Tone]) -> [Tone] {
        tones.map { var t = $0; t.choreo = true; return t }
    }

    /// Сколько хрустов за одну еду, не больше.
    static let maxCrunches = 10
    static let crunchEvery = 0.32

    /// Хруст во время еды (окно eat от начала реакции): шумовой щелчок и тихий «плинь» над ним.
    static func eat(from: Double, to: Double) -> [Tone] {
        var out: [Tone] = []
        let plinks = [11, 12, 10, 13]
        var t = from
        var i = 0
        while t < to - 0.05, i < maxCrunches {
            out.append(Tone(at: t, .noise, 2600, env: Envelope(attack: 0.002, hold: 0.015, release: 0.05),
                            gain: 0.3, cutoff: 2600))
            out.append(Tone(at: t + 0.01, .triangle, n(plinks[i % plinks.count]),
                            env: Envelope(attack: 0.002, hold: 0, release: 0.06), gain: 0.04))
            t += crunchEvery
            i += 1
        }
        return choreo(out)
    }
}
#endif
