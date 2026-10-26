// Волна 34 I: уровень пса и рост на экране. Сцена нового уровня (прыжок, «★7», тост с монетами и открытиями),
// сцена «Подрос!» при смене стадии, опыт после мини-игр, вид роста для сцены (PetStage → PetRig) и голоса (SoundKit).
//
// Что уже показали — уровень и стадию — помним в UserDefaults по petId: стор не трогаем, ядро про показ не знает.
// Нет записи (первый запуск с уровнями) — показанным считается текущее, сцены нет; исключение — уровень, взятый
// только что (DogLevel.freshUp). Сцена одна за раз: следующая ждёт, пока кончится текущая.
//
// UI-тесты: сцены и рост только с сидом level* (свежий щенок за пару действий берёт ур. 2 — старые тесты
// получили бы лишний тост и маленького пса на снимках). Показанное там — только в памяти.

import CoreGraphics
import Foundation
@preconcurrency import PetCore

/// Что из уровня и роста уже показали, и чья сейчас сцена.
struct LevelSeen {
    /// Пёс, для которого прочитано; другой — читаем заново.
    var petId = ""
    var level = 0
    var phase: GrowthPhase? = nil
    /// До какого времени идёт сцена: следующая ждёт.
    var busyUntil: Double = 0
    /// Опыт на момент открытия мини-игры; nil — игра не открыта.
    var gameXp: Int? = nil

    /// Пауза перед сценой: доиграть отклик на действие и дать листу уехать.
    static let delay: Double = 1.2
    /// Сколько длится сцена уровня (с тостом открытий — дольше).
    static let levelFor: Double = 3.5
    static let unlockFor: Double = 6
    /// «Подрос!» — 3 с, по ТЗ.
    static let growFor: Double = 3
    /// Пауза после закрытия мини-игры: экран уезжает, игра дописывает партию в стор.
    static let gameDelay: Double = 1.4

    /// Сцены и рост включены: в обычном запуске всегда, в UI-тестах — только с сидом level*.
    static var on: Bool {
        if Env.isUnitTest { return false }
        guard Env.isUITest else { return true }
        return Env.value("PET_SEED")?.hasPrefix("level") ?? false
    }

    /// Писать показанное на диск (UI-тесты — только память, каждый запуск с нуля).
    static var persist: Bool { !Env.isUITest }

    private static func levelKey(_ id: String) -> String { "level.seen.\(id)" }
    private static func phaseKey(_ id: String) -> String { "growth.seen.\(id)" }

    /// Прочитать показанное для пса f. Записи нет — показанным считается текущее (кроме уровня, взятого только что).
    mutating func load(_ f: SaveFile, now: Double) {
        petId = f.petId
        busyUntil = 0
        let d = UserDefaults.standard
        if Self.persist, d.object(forKey: Self.levelKey(f.petId)) != nil {
            level = d.integer(forKey: Self.levelKey(f.petId))
        } else if let u = DogLevel.freshUp(f, now: now, shownT: nil), u.level == f.level.paidLevel {
            level = u.level - 1
        } else {
            level = f.level.paidLevel
        }
        if Self.persist, let raw = d.string(forKey: Self.phaseKey(f.petId)), let p = GrowthPhase(rawValue: raw) {
            phase = p
        } else {
            phase = Growth.phase(f)
        }
        save()
    }

    func save() {
        guard Self.persist, !petId.isEmpty else { return }
        let d = UserDefaults.standard
        d.set(level, forKey: Self.levelKey(petId))
        if let phase { d.set(phase.rawValue, forKey: Self.phaseKey(petId)) }
    }

    /// Стадия старше: щенок < подросток < взрослый.
    static func rank(_ p: GrowthPhase) -> Int { GrowthPhase.allCases.firstIndex(of: p) ?? 0 }
}

extension AppModel {
    /// Точка над псом для «★7» и «+5 опыта».
    var levelAnchor: CGPoint { CGPoint(x: stageSize.width / 2, y: stageSize.height * 0.4) }

    /// Из refresh: вид роста для сцены и голоса, сцены нового уровня и «Подрос!».
    func noteLevel(_ f: SaveFile, now: Double) {
        let on = LevelSeen.on
        let look: GrowthLook? = on ? Growth.look(f) : nil
        if look != growthLook {
            growthLook = look
            SoundKit.voicePitch = look?.voicePitch ?? 1
            SoundKit.voiceCrack = look?.voiceCrack ?? 0
        }
        guard on, f.pet.alive else { return }
        if levelSeen.petId != f.petId { levelSeen.load(f, now: now) }
        let paid = f.level.paidLevel
        // Новый пёс на старом id или откат сейва: показанное не выше текущего.
        if paid < levelSeen.level {
            levelSeen.level = paid
            levelSeen.save()
        }
        guard now >= levelSeen.busyUntil, !levelSceneBlocked else { return }
        if let s = LevelInfo.summary(after: levelSeen.level, upTo: paid) {
            levelSeen.level = paid
            levelSeen.save()
            playLevelUp(s)
            return
        }
        let phase = Growth.phase(f)
        if phase != levelSeen.phase {
            let grew = levelSeen.phase.map { LevelSeen.rank(phase) > LevelSeen.rank($0) } ?? false
            levelSeen.phase = phase
            levelSeen.save()
            if grew { playGrow(phase) }
        }
    }

    /// Поверх чего сцену не играем: отчёт «Пока тебя не было», игры и листы. Ушёл гулять — тоже ждём.
    var levelSceneBlocked: Bool {
        away != nil || showCatch || showBlockDuo || showZombie || showTricks || showCapsule || showShop || showHouse
            || showSettings || showAlbum || showNeeds || showKitchen || showHabits || showLevel || postcard != nil
            || snap.pose == .away
    }

    /// Спит — без прыжка: тост и звезда, будить ради уровня не будем.
    private var levelCalm: Bool { [Pose.sleep, .nap].contains(snap.pose) }

    /// Новый уровень (или несколько разом — одной сводкой): прыжок, «★N», тост с монетами, потом «Открылось: …».
    func playLevelUp(_ s: LevelSummary) {
        let unlock = LevelInfo.unlockText(s.unlocks)
        levelSeen.busyUntil = Clock.now() + LevelSeen.delay + (unlock == nil ? LevelSeen.levelFor : LevelSeen.unlockFor)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(LevelSeen.delay))
            guard let self, !Task.isCancelled else { return }
            if !self.levelCalm { self.react(Trick.jump.kind) }
            Feel.success(.hearts)
            self.pop(LevelInfo.star(s), at: self.levelAnchor)
            self.show(LevelInfo.toast(s), emoji: "🪙")
            if let unlock {
                try? await Task.sleep(for: .seconds(2.6))
                guard !Task.isCancelled else { return }
                self.show(unlock, emoji: "✨")
            }
            self.refreshAfterScene()
        }
    }

    /// Сменилась стадия роста: прыжок, «📏», тост «Подрос!». Запись в памяти пишет Memories по журналу growth.phase.
    func playGrow(_ phase: GrowthPhase) {
        levelSeen.busyUntil = Clock.now() + LevelSeen.delay + LevelSeen.growFor
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(LevelSeen.delay))
            guard let self, !Task.isCancelled else { return }
            if !self.levelCalm { self.react(Trick.jump.kind) }
            Feel.success(.hearts)
            self.pop("📏", at: self.levelAnchor)
            self.show(LevelInfo.grewText(phase), emoji: "🐕")
            self.refreshAfterScene()
        }
    }

    /// Сцена кончилась — следом может ждать вторая (уровень и рост разом): не ждать тикера 30 с.
    private func refreshAfterScene() {
        let left = max(0, levelSeen.busyUntil - Clock.now())
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(left + 0.1))
            self?.refresh()
        }
    }

    // MARK: мини-игры

    /// Мини-игра открылась: запомнить опыт, чтобы после показать прибавку.
    func gameOpened() {
        levelSeen.gameXp = file?.level.xp
    }

    /// Мини-игра закрылась: начислить опыт за партию (DogLevel.settle) и показать «+5 опыта» над псом.
    /// Новый уровень покажет noteLevel из refresh — после поздравлений игры.
    func gameClosed() {
        guard let before = levelSeen.gameXp else { return }
        levelSeen.gameXp = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(LevelSeen.gameDelay))
            guard let self, !Task.isCancelled else { return }
            let now = Clock.now()
            _ = try? PetStore.shared.mutate { (f: inout SaveFile) -> Void in
                _ = DogLevel.settle(&f, now: now)
            }
            self.refresh(now: now)
            let gained = (self.file?.level.xp ?? before) - before
            if gained > 0 { self.pop(LevelInfo.xpPop(gained), at: self.levelAnchor) }
        }
    }
}
