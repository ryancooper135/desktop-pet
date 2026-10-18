// Звук в приложении: AVAudioEngine + AVAudioSourceNode, ноты синтезируются на лету (SynthCore),
// рецепты — SoundRecipes.swift. Файлов со звуками нет, лицензий тоже.
//
// Категория .ambient: звук смешивается с музыкой и молчит на беззвучном режиме — как у системных
// щелчков. Движок поднимается лениво, на первом звуке; через 30 с тишины и при уходе в фон — стоп.
// Переключатель «Звук» в настройках (UserDefaults, по умолчанию включён). Reduce Motion звук не трогает.
// В тестах (юнит и UI) звука нет совсем: аудиосессия на CI ни к чему.

import AVFoundation
import SwiftUI

@MainActor
final class SoundKit {
    static let shared = SoundKit()

    /// Ключ переключателя «Звук» в UserDefaults.standard. Нет значения — звук включён.
    nonisolated static let enabledKey = "sound.on"
    /// Сколько тишины держать движок, прежде чем остановить.
    static let idleStop: Duration = .seconds(30)

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private let core = SynthCore()
    private var engine: AVAudioEngine?
    private var idleTask: Task<Void, Never>?
    /// Приложение в фоне: новые звуки не поднимают движок.
    private var suspended = false
    /// Когда приложение вернулось из фона (см. ambient).
    private var wokeAt: ContinuousClock.Instant?
    static let wakeQuiet: Duration = .seconds(2)

    // MARK: что звучит

    func play(_ cue: SoundCue) {
        schedule(SoundRecipe.tones(cue))
    }

    /// Звук позже, вместе с анимацией (трюк «Голос»). Перебили хореографию — не прозвучит.
    func play(_ cue: SoundCue, after offset: Double) {
        schedule(SoundRecipe.delayed(cue, by: offset))
    }

    /// Ответ ядра на действие из приложения (рядом с хаптикой success/warning).
    func settled(kind: String, ok: Bool) {
        if let cue = SoundRecipe.forAction(kind: kind, ok: ok) { play(cue) }
    }

    /// Тик ласки: n — номер тика с начала жеста (StrokeEvent.tick).
    func strokeTick(_ n: Int) {
        play(.petTick(n))
    }

    /// Игра с мячом началась через offset секунд (PetChoreo.begin): пинок, удары отскоков, тычок лапой.
    func ball(after offset: Double) {
        typealias P = ChoreoPath.Play
        schedule(SoundRecipe.ball(start: offset, kick: P.kick,
                                  bounces: P.bounces.map { (duration: $0.0, height: Double($0.1)) },
                                  knock: P.pounce1 - 0.25))
    }

    /// Еда: хруст на окне eat (секунды от начала реакции).
    func eat(from: Double, to: Double) {
        schedule(SoundRecipe.eat(from: from, to: to))
    }

    /// Хореографию перебили (PetChoreo.begin/stop): недозвучавшие мяч и хруст снять.
    func cancelChoreo() {
        guard let engine, engine.isRunning else { return }
        core.cancelChoreo()
    }

    // MARK: жизненный цикл

    func becameActive() {
        suspended = false
        wokeAt = ContinuousClock.now
    }

    /// Звук от смены состояния, а не от касания (сердца, смерть, новый щенок). Первые секунды после
    /// возврата из фона молчит: снимок догоняет время вдали, и это не событие «сейчас».
    func ambient(_ cue: SoundCue) {
        if let wokeAt, ContinuousClock.now - wokeAt < Self.wakeQuiet { return }
        play(cue)
    }

    func wentBackground() {
        suspended = true
        stop()
    }

    /// Остановить движок; недоигранное выбрасывается. Следующий звук поднимет движок снова.
    func stop() {
        idleTask?.cancel()
        idleTask = nil
        guard let engine else { return }
        if engine.isRunning { engine.stop() }
        core.requestReset()
    }

    // MARK: движок

    private func schedule(_ tones: [Tone]) {
        guard !tones.isEmpty, Self.enabled, !suspended, !Env.isTesting else { return }
        guard ensureRunning() else { return }
        core.push(tones)
        armIdle()
    }

    /// Движок работает или поднят сейчас. Звонок, Siri, смена наушников останавливают его сами —
    /// поэтому проверка на каждом звуке, а не один раз.
    private func ensureRunning() -> Bool {
        if let engine, engine.isRunning { return true }
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .ambient {
                try session.setCategory(.ambient, mode: .default, options: [])
            }
            try session.setActive(true)
        } catch {
            return false
        }
        // Движок был, но его остановила система (звонок, Siri) — недоигранное в очереди уже не к месту.
        if engine != nil { core.requestReset() }
        let e = engine ?? makeEngine()
        engine = e
        do {
            try e.start()
            return true
        } catch {
            return false
        }
    }

    private func makeEngine() -> AVAudioEngine {
        let e = AVAudioEngine()
        // Моно на своей частоте; микшер сам приведёт к частоте выхода.
        let format = AVAudioFormat(standardFormatWithSampleRate: core.sampleRate, channels: 1)!
        let node = Self.makeSource(core, format: format)
        e.attach(node)
        e.connect(node, to: e.mainMixerNode, format: format)
        e.prepare()
        return e
    }

    /// Узел-источник. nonisolated: рендер зовётся из аудиопотока, а замыкание, созданное на главном
    /// акторе, Swift 6 проверял бы на «главный поток» и падал. Внутри — только core.render.
    nonisolated private static func makeSource(_ core: SynthCore, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let frames = Int(frameCount)
            guard buffers.count > 0, let first = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let silent = core.render(into: first, frames: frames)
            // Формат моно, но если система дала больше каналов — тот же сигнал во все.
            var c = 1
            while c < buffers.count {
                if let data = buffers[c].mData?.assumingMemoryBound(to: Float.self) {
                    data.update(from: first, count: frames)
                }
                c += 1
            }
            isSilence.pointee = ObjCBool(silent)
            return noErr
        }
    }

    /// После idleStop без новых звуков — остановить движок (батарея).
    private func armIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleStop)
            if Task.isCancelled { return }
            self?.stop()
        }
    }
}

/// Звуки на перемены снимка, которые не привязаны к кнопке: сердце вернулось или потеряно,
/// питомец умер, новый щенок. Только переходы, пока экран открыт; при запуске не звучит.
/// Сердца в ядре дробные — звучит только смена целого сердца.
struct SoundLayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Color.clear
            .onChange(of: Int(model.snap.hearts.rounded(.down))) { old, new in
                // С нуля — это новый щенок после смерти: там звучит hello.
                guard model.snap.alive, old > 0 else { return }
                if new > old {
                    SoundKit.shared.ambient(.hearts)
                } else if new < old {
                    SoundKit.shared.ambient(.heartLost)
                }
            }
            .onChange(of: model.snap.alive) { _, alive in
                SoundKit.shared.ambient(alive ? .hello : .death)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
