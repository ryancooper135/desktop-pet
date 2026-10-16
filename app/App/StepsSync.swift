// Шаги хозяина из CMPedometer (как в probe): питомец «гуляет» вместе с ним.
// Первый запрос показывает системный алерт «Движение и фитнес».

@preconcurrency import CoreMotion
import Foundation

enum StepsSync {
    /// Меньше — не засчитываем, чтобы не забивать журнал мелочью.
    static let minSteps = 100

    nonisolated(unsafe) private static let pedometer = CMPedometer()

    static var available: Bool {
        CMPedometer.isStepCountingAvailable() && CMPedometer.authorizationStatus() != .denied
            && CMPedometer.authorizationStatus() != .restricted
    }

    /// Шаги за интервал или nil (нет шагомера, нет разрешения, ошибка).
    static func count(from: Date, to: Date) async -> Int? {
        guard available, to > from else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
            pedometer.queryPedometerData(from: from, to: to) { data, _ in
                cont.resume(returning: data.map { $0.numberOfSteps.intValue })
            }
        }
    }
}
