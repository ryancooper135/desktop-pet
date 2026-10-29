// Волна 47 T: кэш на чтении сейва для того, что экран читает в body.
// AppModel.dogAsk читается в теле HomeScreen дважды (плашка и .animation), а тело пересчитывается на каждое
// движение пальца по сцене (lookX), тост, реплику и подсказку жеста. Каждый раз это был DogAsks.shown: копия
// сейва, prepare/settle с проходом по журналу, peek ядра от pet.t до now минута за минутой (между записями pet.t
// отстаёт — чем дольше открыт экран без действий, тем дольше прогон), а для только что наступившей просьбы — ещё
// и peek на её старт. Сейв и снимок между refresh не меняются, значит и ответ тот же: считаем раз на пару
// (запись сейва, now). Результат — ровно DogAsks.shown (Wave47PerfTests).
// Без SwiftUI — гоняется в WSL.

import Foundation
@preconcurrency import PetCore

/// Какая это запись сейва: каждая запись через PetStore.mutate двигает rev, действие — ещё и seq и pet.t;
/// другой щенок или другое устройство — другие petId и deviceId. Для кэшей на чтении: сравнить дёшево,
/// а сам SaveFile не Equatable (и сравнивать его журнал — почти та же работа, что пересчитать).
struct SaveStamp: Hashable, Sendable {
    var petId: String
    var deviceId: String
    var rev: Int
    var seq: Int
    var petT: Double

    init(_ f: SaveFile) {
        petId = f.petId
        deviceId = f.deviceId
        rev = f.rev
        seq = f.seq
        petT = f.pet.t
    }
}

/// Просьба, которую видно на now (DogAsks.shown), — один расчёт на (сейв, now, пояс, вкл/выкл).
/// Хранится у читателя (AppModel, @ObservationIgnored): новый refresh даёт новый now — и новый расчёт.
struct AskMemo: Sendable {
    struct Key: Equatable, Sendable {
        var save: SaveStamp
        var now: Double
        var tz: Int
        var enabled: Bool
    }

    private(set) var key: Key?
    private(set) var value: DogAsk?
    /// Сколько раз считали по-настоящему (для тестов).
    private(set) var misses = 0

    mutating func shown(_ f: SaveFile, now: Double) -> DogAsk? {
        let k = Key(save: SaveStamp(f), now: now, tz: Clock.tzOffsetMin(at: now), enabled: DogAsks.enabled)
        if let key, key == k { return value }
        let v = DogAsks.shown(f, now: now)
        key = k
        value = v
        misses += 1
        return v
    }
}
