// Кто первый — тот и закончил (волна 25, хвост волны 23: защёлка камеры открыток).
// ARView.snapshot может не позвать колбэк (рендер на паузе, приложение ушло в фон) — continuation тогда ждёт
// вечно, PostcardCamera.busy остаётся true до перезапуска, и открыток больше нет. Колбэк и таймаут соревнуются:
// продолжает тот, кто первым взял claim(); второй молчит (continuation нельзя продолжить дважды).

import Foundation

final class FirstWins: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    init() {}

    /// true — только первому вызвавшему.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}
