// Звук в приложении: AVAudioEngine + AVAudioSourceNode, ноты синтезируются на лету (SynthCore),
// рецепты — SoundRecipes.swift. Файлов со звуками нет, лицензий тоже.
//
// Категория .ambient: звук смешивается с музыкой и молчит на беззвучном режиме — как у системных
// щелчков. Движок поднимается лениво, на первом звуке; через 30 с тишины и при уходе в фон — стоп.
// Переключатель «Звук» в настройках (UserDefaults, по умолчанию включён). Reduce Motion звук не трогает.
// В тестах (юнит и UI) звука нет совсем: аудиосессия на CI ни к чему.
// Звук-отклик на касание (кнопки, игры, отказы, сердца) идёт через Feel (App/FeelKit.swift): там кулдаун
// и тишина после фона. Напрямую сюда — только хореография (мяч, хруст, тявк «Голоса»).
// Волна 32: «Лай и рычание» (PetPref.voice) снимает собачьи голоса; тихая музыка (MusicTheme) — на экранах
// с .petMusic / .homeMusic, по своему переключателю «Музыка»; молчит ночью и если на iPhone уже играет другая.

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
        musicTask?.cancel()
        musicTask = nil
        stop()
    }

    // MARK: музыка

    /// Экраны с музыкой (последний — сверху): закрыли верхний — снова играет тот, что под ним.
    private var musicStack: [(token: Int, kind: MusicTheme.Kind)] = []
    private var musicToken = 0
    private var musicTask: Task<Void, Never>?
    /// За сколько секунд до такта класть его ноты в синтезатор.
    private static let musicLead = 0.3

    static var musicOn: Bool { PetPref.music.isOn() }

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

    /// Тихие часы (ночь хозяина): молчит вся музыка, и в играх тоже. Ставит главный экран.
    var musicQuiet = false {
        didSet { if musicQuiet != oldValue { restartMusic() } }
    }

    /// Переключатель «Музыка» сменили.
    func musicPrefChanged() {
        restartMusic()
    }

    private func restartMusic() {
        musicTask?.cancel()
        musicTask = nil
        if let engine, engine.isRunning { core.cancelMusic() }
        guard let kind = musicStack.last?.kind, Self.musicOn, !musicQuiet, !suspended, !Env.isTesting else { return }
        musicTask = Task { [weak self] in await self?.musicLoop(kind) }
    }

    /// Такт за тактом по кругу: ноты такта кладутся за musicLead до его начала. Отстали (движок
    /// поднимался, приложение тормозило) — следующий такт с небольшой паузы, без догоняния.
    private func musicLoop(_ kind: MusicTheme.Kind) async {
        let bar = MusicTheme.barLength(kind)
        var due = ProcessInfo.processInfo.systemUptime + 0.5
        var i = 0
        while !Task.isCancelled {
            let now = ProcessInfo.processInfo.systemUptime
            if due < now + 0.02 { due = now + 0.05 }
            // На iPhone уже играет другая музыка (Spotify, подкаст) — свою не накладываем.
            // Пустой такт — пауза между фразами: ничего не кладём, движок может уснуть (батарея).
            if !MusicTheme.isRest(i, kind), !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint {
                let lead = due - now
                guard pushMusic(MusicTheme.bar(i, kind).map { var t = $0; t.at += lead; return t }) else { return }
            }
            i += 1
            due += bar
            let wait = due - Self.musicLead - ProcessInfo.processInfo.systemUptime
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        }
    }

    private func pushMusic(_ tones: [Tone]) -> Bool {
        guard Self.musicOn, !suspended, !Env.isTesting, ensureRunning() else { return false }
        core.push(tones)
        armIdle()
        return true
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

/// Музыка главного экрана: тихая «домашняя», «прогулка», пока пёс гуляет, и тишина, пока спит.
/// Раз в минуту сверяет тихие часы (от отбоя хозяина до подъёма) — ночью молчит вся музыка.
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
