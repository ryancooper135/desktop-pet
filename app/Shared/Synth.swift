// Крошечный синтезатор для звуков питомца: 6 голосов (синус, треугольник, квадрат, шум), огибающая,
// скольжение высоты, однополюсный фильтр, мягкий ограничитель на выходе.
//
// Два потока. Главный (SoundKit) кладёт ноты в кольцо push(_:). Аудиопоток зовёт render(into:frames:)
// из AVAudioSourceNode: там нельзя ни выделять память, ни брать замки, ни ждать — только числа.
// Поэтому вся память выделена в init, а между потоками — кольцо на одного писателя и одного читателя
// с атомарными индексами (Synchronization). Ноты одного push публикуются разом и стартуют в одном
// блоке рендера — интервалы внутри звука точные до семпла.
//
// Без AVFoundation: рендер проверяется тестами и на Linux. Собирается только в приложение и пакет логики.

#if APP_TARGET || SWIFT_PACKAGE
import Foundation
import Synchronization

final class SynthCore: @unchecked Sendable {
    static let defaultRate: Double = 44_100
    static let voiceCount = 6
    /// Сколько нот помещается в кольцо и в очередь ожидания (хватает на мяч + еду + пару тапов).
    static let queueCapacity = 64
    /// Общая громкость перед ограничителем.
    static let master: Double = 0.9
    /// Предел ограничителя x − x³/3: выход никогда не громче 2/3 полной шкалы.
    static let ceiling: Double = 2.0 / 3.0

    let sampleRate: Double

    // MARK: общее для двух потоков

    /// Кольцо нот: пишет только главный поток, читает только аудиопоток.
    private let ring: UnsafeMutablePointer<Tone>
    /// Сколько нот всего записано / прочитано (растут всегда, слот — индекс по модулю).
    private let written = Atomic<Int>(0)
    private let read = Atomic<Int>(0)
    /// Просьба сбросить голоса и выкинуть из кольца всё, что записано до этой отметки; −1 — нет просьбы.
    private let resetMark = Atomic<Int>(-1)
    /// Просьба снять ноты хореографии (Tone.choreo), записанные до этой отметки; −1 — нет просьбы.
    private let choreoMark = Atomic<Int>(-1)
    /// Сколько голосов звучало в конце последнего блока (для тестов и простоя).
    private let sounding = Atomic<Int>(0)

    // MARK: только аудиопоток

    private struct Voice {
        var on = false
        /// Семплов до начала ноты (старт внутри блока точный до семпла).
        var wait = 0
        var age = 0
        var length = 0
        var tone = Tone(.sine, 0, env: Envelope(attack: 0, hold: 0, release: 0), gain: 0)
        var phase = 0.0
        var step = 0.0
        /// Множитель шага на семпл, пока идёт скольжение.
        var glideMul = 1.0
        var glideLeft = 0
        var lp = 0.0
        var lpA = 1.0
        var noise: UInt32 = 0x9E37_79B9
        /// Семплов до тишины при снятии (0 — не снимается): короткий спад вместо щелчка.
        var fade = 0
    }

    private struct Pending {
        var tone: Tone
        /// Номер семпла (часы рендера), с которого звучать.
        var start: Int
    }

    private let voices: UnsafeMutablePointer<Voice>
    private let pending: UnsafeMutablePointer<Pending>
    private var pendingCount = 0
    private var clock = 0
    private var seed: UInt32 = 0x2545_F491
    /// Ноты хореографии с номером в кольце меньше этого не берём (их сняли раньше, чем дочитали).
    private var choreoBelow = 0
    /// Сколько семплов гаснет снятый голос.
    static let fadeSamples = 256

    init(sampleRate: Double = SynthCore.defaultRate) {
        self.sampleRate = sampleRate
        let cap = Self.queueCapacity
        let blank = Tone(.sine, 0, env: Envelope(attack: 0, hold: 0, release: 0), gain: 0)
        ring = .allocate(capacity: cap)
        ring.initialize(repeating: blank, count: cap)
        voices = .allocate(capacity: Self.voiceCount)
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
        pending = .allocate(capacity: cap)
        pending.initialize(repeating: Pending(tone: blank, start: 0), count: cap)
    }

    deinit {
        ring.deinitialize(count: Self.queueCapacity)
        ring.deallocate()
        voices.deinitialize(count: Self.voiceCount)
        voices.deallocate()
        pending.deinitialize(count: Self.queueCapacity)
        pending.deallocate()
    }

    // MARK: главный поток

    /// Положить ноты одного звука. Не влезло в кольцо — хвост теряется (звук тише, но не ломается).
    /// Возвращает, сколько нот положено. Писатель должен быть один (SoundKit на главном акторе).
    @discardableResult
    func push(_ tones: [Tone]) -> Int {
        let w = written.load(ordering: .relaxed)
        let r = read.load(ordering: .acquiring)
        let room = Self.queueCapacity - (w - r)
        let count = min(room, tones.count)
        guard count > 0 else { return 0 }
        for i in 0..<count {
            ring[(w + i) % Self.queueCapacity] = tones[i]
        }
        written.store(w + count, ordering: .releasing)
        return count
    }

    /// Замолчать: голоса гаснут, всё недоигранное выбрасывается на следующем блоке рендера.
    /// Ноты, положенные после этого вызова, сыграют как обычно.
    func requestReset() {
        resetMark.store(written.load(ordering: .relaxed), ordering: .releasing)
    }

    /// Анимацию перебили: мяч и хруст, которые ещё не прозвучали, не нужны. Звучащие ноты хореографии
    /// гаснут за несколько миллисекунд, остальные звуки не трогаются.
    func cancelChoreo() {
        choreoMark.store(written.load(ordering: .relaxed), ordering: .releasing)
    }

    /// Сколько голосов звучало в конце последнего блока.
    var activeVoices: Int { sounding.load(ordering: .relaxed) }

    // MARK: аудиопоток

    /// Заполнить out на frames семплов (моно, Float). Возвращает true, если блок — тишина.
    /// Без выделений памяти, замков и ожиданий.
    func render(into out: UnsafeMutablePointer<Float>, frames: Int) -> Bool {
        let mark = resetMark.exchange(-1, ordering: .acquiringAndReleasing)
        if mark >= 0 {
            for v in 0..<Self.voiceCount { voices[v].on = false }
            pendingCount = 0
            if mark > read.load(ordering: .relaxed) { read.store(mark, ordering: .releasing) }
        }
        let cut = choreoMark.exchange(-1, ordering: .acquiringAndReleasing)
        if cut >= 0 {
            choreoBelow = max(choreoBelow, cut)
            for v in 0..<Self.voiceCount where voices[v].on && voices[v].tone.choreo && voices[v].fade == 0 {
                // Ещё не начала (ждёт внутри блока) — просто снять; звучит — короткий спад.
                if voices[v].wait > 0 { voices[v].on = false } else { voices[v].fade = Self.fadeSamples }
            }
            var i = 0
            while i < pendingCount {
                if pending[i].tone.choreo {
                    pendingCount -= 1
                    pending[i] = pending[pendingCount]
                } else {
                    i += 1
                }
            }
        }
        drainRing()
        startDue(frames: frames)

        var anyOn = false
        for v in 0..<Self.voiceCount where voices[v].on {
            anyOn = true
            break
        }
        if !anyOn {
            out.update(repeating: 0, count: frames)
            clock += frames
            sounding.store(0, ordering: .relaxed)
            return true
        }

        let sr = sampleRate
        for i in 0..<frames {
            var sum = 0.0
            for v in 0..<Self.voiceCount where voices[v].on {
                sum += next(&voices[v], sr)
            }
            out[i] = Float(Self.limit(sum * Self.master))
        }
        clock += frames
        var n = 0
        for v in 0..<Self.voiceCount where voices[v].on { n += 1 }
        sounding.store(n, ordering: .relaxed)
        return false
    }

    /// Мягкий ограничитель: тихое почти не трогает, громкое плавно упирается в ±2/3.
    static func limit(_ x: Double) -> Double {
        let c = min(max(x, -1), 1)
        return c - c * c * c / 3
    }

    /// Из кольца — в очередь ожидания с абсолютным временем старта.
    private func drainRing() {
        let r = read.load(ordering: .relaxed)
        let w = written.load(ordering: .acquiring)
        guard w > r else { return }
        for k in r..<w {
            let t = ring[k % Self.queueCapacity]
            guard pendingCount < Self.queueCapacity, !(t.choreo && k < choreoBelow) else { continue }
            let delay = Int((max(t.at, 0) * sampleRate).rounded())
            pending[pendingCount] = Pending(tone: t, start: clock + delay)
            pendingCount += 1
        }
        read.store(w, ordering: .releasing)
    }

    /// Ноты, чей старт попадает в этот блок, — на голоса.
    private func startDue(frames: Int) {
        let end = clock + frames
        var i = 0
        while i < pendingCount {
            let p = pending[i]
            if p.start < end {
                start(p.tone, wait: max(0, p.start - clock))
                pendingCount -= 1
                pending[i] = pending[pendingCount]
            } else {
                i += 1
            }
        }
    }

    /// Свободный голос, а если все заняты — самый старый (он уже почти затих).
    private func start(_ t: Tone, wait: Int) {
        var slot = -1
        var oldest = -1
        for v in 0..<Self.voiceCount {
            if !voices[v].on { slot = v; break }
            if oldest < 0 || voices[v].age > voices[oldest].age { oldest = v }
        }
        if slot < 0 { slot = oldest }

        let sr = sampleRate
        var v = Voice()
        v.on = true
        v.wait = wait
        v.tone = t
        v.length = max(1, Int((t.env.length * sr).rounded()))
        v.step = max(t.freq, 0) / sr
        let glideSamples = Int((t.glide * sr).rounded())
        if glideSamples > 0, t.freq > 0, t.glideTo > 0, t.glideTo != t.freq {
            v.glideMul = pow(t.glideTo / t.freq, 1 / Double(glideSamples))
            v.glideLeft = glideSamples
        }
        if t.cutoff > 0, t.cutoff < sr / 2 {
            v.lpA = 1 - exp(-2 * Double.pi * t.cutoff / sr)
        }
        seed = seed &* 1_664_525 &+ 1_013_904_223
        v.noise = seed | 1
        voices[slot] = v
    }

    /// Следующий семпл голоса (уже с огибающей и громкостью).
    private func next(_ v: inout Voice, _ sr: Double) -> Double {
        if v.wait > 0 {
            v.wait -= 1
            return 0
        }
        let raw: Double
        switch v.tone.wave {
        case .sine:
            raw = sin(2 * Double.pi * v.phase)
        case .triangle:
            raw = 1 - 4 * abs(v.phase - 0.5)
        case .square:
            raw = v.phase < 0.5 ? 0.6 : -0.6
        case .noise:
            v.noise ^= v.noise << 13
            v.noise ^= v.noise >> 17
            v.noise ^= v.noise << 5
            raw = Double(v.noise) / Double(UInt32.max) * 2 - 1
        }
        v.lp += v.lpA * (raw - v.lp)
        var s = v.lp * v.tone.env.level(Double(v.age) / sr) * v.tone.gain
        if v.fade > 0 {
            s *= Double(v.fade) / Double(Self.fadeSamples)
            v.fade -= 1
            if v.fade == 0 { v.on = false }
        }

        v.phase += v.step
        if v.phase >= 1 { v.phase -= v.phase.rounded(.down) }
        if v.glideLeft > 0 {
            v.step *= v.glideMul
            v.glideLeft -= 1
        }
        v.age += 1
        if v.age >= v.length { v.on = false }
        return s
    }
}
#endif
