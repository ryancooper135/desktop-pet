// Звук в приложении: AVAudioEngine + AVAudioSourceNode, ноты синтезируются на лету (SynthCore),
// рецепты — SoundRecipes.swift. Файлов со звуками нет; файлы только у музыки (волна 49, ниже).
//
// Категория .ambient: звук смешивается с музыкой и молчит на беззвучном режиме — как у системных
// щелчков. Движок поднимается лениво, на первом звуке; через 30 с тишины и при уходе в фон — стоп.
// Переключатель «Звук» в настройках (UserDefaults, по умолчанию включён). Reduce Motion звук не трогает.
// В тестах (юнит и UI) звука нет совсем: аудиосессия на CI ни к чему.
// Звук-отклик на касание (кнопки, игры, отказы, сердца) идёт через Feel (App/FeelKit.swift): там кулдаун
// и тишина после фона. Напрямую сюда — только хореография (мяч, хруст, тявк «Голоса»).
// Волна 32: «Лай и рычание» (PetPref.voice) снимает собачьи голоса; тихая музыка (MusicTheme) — на экранах
// с .petMusic / .homeMusic, по своему переключателю «Музыка».
// Волна 49: музыка — CC0-лупы из бандла (Resources/Music) через AVAudioPlayer в той же сессии .ambient: молчит
// на беззвучном режиме и если на iPhone уже играет другая (secondaryAudioShouldBeSilencedHint и его уведомление);
// ночью и пока пёс спит — тише.

import AVFoundation
import SwiftUI

@MainActor
final class SoundKit {
    static let shared = SoundKit()

    /// Ключ переключателя «Звук» в UserDefaults.standard. Нет значения — звук включён.
    nonisolated static let enabledKey = FeelGate.soundKey
    /// Сколько тишины держать движок, прежде чем остановить.
    static let idleStop: Duration = .seconds(30)

    static var enabled: Bool { FeelGate.enabled(enabledKey) }

    private let core = SynthCore()
    private var engine: AVAudioEngine?
    private var idleTask: Task<Void, Never>?
    /// Приложение в фоне: новые звуки не поднимают движок.
    private var suspended = false

    // MARK: что звучит

    /// «Лай и рычание» включены (нет значения — да).
    static var voice: Bool { PetPref.voice.isOn() }

    /// Голос по росту (волна 34 I, Growth.look; ставит AppModel.noteLevel): щенок выше, подросток иногда срывается.
    static var voicePitch: Double = 1
    static var voiceCrack: Double = 0

    func play(_ cue: SoundCue) {
        schedule(grown(cue, SoundRecipe.tones(cue, voice: Self.voice)))
    }

    /// Звук позже, вместе с анимацией (трюк «Голос»). Перебили хореографию — не прозвучит.
    func play(_ cue: SoundCue, after offset: Double) {
        schedule(grown(cue, SoundRecipe.delayed(cue, by: offset, voice: Self.voice)))
    }

    /// Собачий голос — с поправкой роста; кнопки, хруст и заглушки при выключенном голосе — как есть.
    private func grown(_ cue: SoundCue, _ tones: [Tone]) -> [Tone] {
        guard Self.voice, cue.isVoice else { return tones }
        return GrowthVoice.apply(tones, pitch: Self.voicePitch, crack: Self.voiceCrack, roll: Double.random(in: 0..<1))
    }

    private var petVoice = PetVoice()

    /// Тявк или — редко — игривое рычание на игру и щекотку (PetVoice: пауза, не два раза подряд).
    func dogCue(_ event: PetVoice.Event) -> SoundCue {
        petVoice.cue(event, at: ProcessInfo.processInfo.systemUptime, roll: Double.random(in: 0..<1))
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
        restartMusic()
    }

    func wentBackground() {
        suspended = true
        stopMusicNow()
        stop()
    }

    // MARK: музыка

    /// Экраны с музыкой (последний — сверху): закрыли верхний — снова играет тот, что под ним.
    private var musicStack: [(token: Int, kind: MusicTheme.Kind)] = []
    private var musicToken = 0
    /// Играющий луп и его файл. Смена места на том же файле — только громкость, без перезапуска.
    private var player: AVAudioPlayer?
    private var playerTrack: String?
    private var hintObserver: NSObjectProtocol?

    static var musicOn: Bool { PetPref.music.isOn() }

    private init() {
        // Другое приложение начало или кончило играть музыку — своя уступает или возвращается.
        hintObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in SoundKit.shared.restartMusic() }
        }
    }

    /// Экран с музыкой появился. Вернуть токен для stopMusic.
    func startMusic(_ kind: MusicTheme.Kind) -> Int {
        musicToken += 1
        musicStack.append((token: musicToken, kind: kind))
        restartMusic()
        return musicToken
    }

    /// Экран сменил свою музыку (главный: дома → прогулка → сон). Место в стопке не меняется:
    /// если сверху открыта игра, играет по-прежнему она. nil — экран замолчал (токен снят).
    func setMusic(_ token: Int?, _ kind: MusicTheme.Kind?) -> Int? {
        guard let token, let at = musicStack.firstIndex(where: { $0.token == token }) else {
            guard let kind else { return nil }
            return startMusic(kind)
        }
        guard let kind else {
            stopMusic(token)
            return nil
        }
        guard musicStack[at].kind != kind else { return token }
        musicStack[at].kind = kind
        if at == musicStack.count - 1 { restartMusic() }
        return token
    }

    /// Экран с музыкой ушёл.
    func stopMusic(_ token: Int) {
        let wasTop = musicStack.last?.token == token
        musicStack.removeAll { $0.token == token }
        if wasTop { restartMusic() }
    }

    /// Тихие часы (ночь хозяина): вся музыка тише (MusicTheme.nightScale), и в играх тоже. Ставит главный экран.
    var musicQuiet = false {
        didSet { if musicQuiet != oldValue { restartMusic() } }
    }

    /// Переключатель «Музыка» сменили.
    func musicPrefChanged() {
        restartMusic()
    }

    /// Привести плеер к верху стопки: тот же файл — плавно к новой громкости, другой — уход старого и вход нового.
    private func restartMusic() {
        guard let kind = musicStack.last?.kind, Self.musicOn, !suspended, !Env.isTesting,
              !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else {
            fadeOutMusic()
            return
        }
        let target = Float(MusicTheme.level(kind, quiet: musicQuiet))
        let track = MusicTheme.track(kind)
        if let player, playerTrack == track {
            // Звонок или Siri могли поставить плеер на паузу — продолжить.
            if !player.isPlaying, activateSession() { player.play() }
            player.setVolume(target, fadeDuration: MusicTheme.fadeChange)
            return
        }
        fadeOutMusic()
        guard activateSession(),
              let url = Bundle.main.url(forResource: track, withExtension: MusicTheme.fileExtension),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        guard p.play() else { return }
        p.setVolume(target, fadeDuration: MusicTheme.fadeIn)
        player = p
        playerTrack = track
    }

    /// Плавно увести музыку в ноль и остановить.
    private func fadeOutMusic() {
        guard let p = player else { return }
        player = nil
        playerTrack = nil
        p.setVolume(0, fadeDuration: MusicTheme.fadeOut)
        Task {
            try? await Task.sleep(for: .seconds(MusicTheme.fadeOut + 0.1))
            p.stop()
        }
    }

    /// Ушли в фон — музыка сразу стоп, без затухания.
    private func stopMusicNow() {
        player?.stop()
        player = nil
        playerTrack = nil
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
        guard activateSession() else { return false }
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

    /// Сессия .ambient: смешивается с чужой музыкой и молчит на беззвучном режиме. Общая для звуков и музыки.
    private func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .ambient {
                try session.setCategory(.ambient, mode: .default, options: [])
            }
            try session.setActive(true)
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

/// Тихая музыка, пока экран на виду (мини-игры, лавка, дом). Главный экран — HomeMusic.
struct PetMusic: ViewModifier {
    let kind: MusicTheme.Kind
    @State private var token: Int?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if token == nil { token = SoundKit.shared.startMusic(kind) }
            }
            .onDisappear {
                if let token { SoundKit.shared.stopMusic(token) }
                token = nil
            }
    }
}

/// Музыка главного экрана: тихая «домашняя», пока пёс гуляет — чуть тише, пока спит — еле слышно.
/// Раз в минуту сверяет тихие часы (от отбоя хозяина до подъёма) — ночью вся музыка тише.
struct HomeMusic: ViewModifier {
    let kind: MusicTheme.Kind?
    let schedule: RoomSchedule
    @State private var token: Int?

    func body(content: Content) -> some View {
        content
            .onAppear { token = SoundKit.shared.setMusic(token, kind) }
            .onDisappear {
                if let token { SoundKit.shared.stopMusic(token) }
                token = nil
            }
            .onChange(of: kind) { _, now in token = SoundKit.shared.setMusic(token, now) }
            .task(id: schedule) {
                while !Task.isCancelled {
                    SoundKit.shared.musicQuiet = Self.quietNow(schedule)
                    try? await Task.sleep(for: .seconds(60))
                }
            }
    }

    static func quietNow(_ s: RoomSchedule, clock: Double = Clock.now()) -> Bool {
        let local = RoomClock.localMinute(now: clock, tzOffsetMin: Clock.tzOffsetMin(at: clock))
        return MusicTheme.quietHours(localMin: local, bedMin: s.bedMin, wakeMin: s.wakeMin)
    }
}

extension View {
    func petMusic(_ kind: MusicTheme.Kind) -> some View {
        modifier(PetMusic(kind: kind))
    }

    func homeMusic(_ kind: MusicTheme.Kind?, schedule: RoomSchedule) -> some View {
        modifier(HomeMusic(kind: kind, schedule: schedule))
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
                // Фоновые: первые секунды после возврата из фона молчат (снимок догоняет время вдали).
                if new > old {
                    Feel.ambient(nil, .hearts)
                } else if new < old {
                    Feel.ambient(nil, .heartLost)
                }
            }
            .onChange(of: model.snap.alive) { _, alive in
                Feel.ambient(nil, alive ? .hello : .death)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
