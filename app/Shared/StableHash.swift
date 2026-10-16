// FNV-1a 64 по UTF-8. Hasher нельзя: он солится на каждый запуск, и выбор реплики
// разъедется между приложением и расширением.

enum StableHash {
    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }
}
