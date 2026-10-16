// Точка расширения под бэкап и синхронизацию (iCloud, сервер друзей). Пока ничего не отправляет:
// зеркало в Documents пишет сам PetStore, outbox копится в SaveFile.

import Foundation

protocol BackupService: Sendable {
    /// Вызывается после каждого действия в приложении. Не должна бросать и долго ждать.
    func backup(_ f: SaveFile) async
}

struct NoopBackup: BackupService {
    func backup(_ f: SaveFile) async {}
}
