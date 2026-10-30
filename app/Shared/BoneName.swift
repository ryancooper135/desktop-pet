// Имена костей (волна 50). Код спрашивал уши как «Ear1.L», а в shiba.usdz они «Ear1_L» — уши в отклике
// на тап (TapWiggle) не двигались ни разу. Свои персонажи и будущая модель (волна 58) тоже могут звать кости
// по-своему: точка, дефис, пробел, двоеточие, регистр. Сначала точное совпадение (путь или последнее звено),
// потом — по нормализованному последнему звену. Чистая логика без RealityKit, тесты — BoneNameTests.

import Foundation

enum BoneName {
    /// Нижний регистр, «.», «-», « », «:» → «_». «Ear1.L», «ear1-l», «EAR1_L» — одно имя.
    static func normalized<S: StringProtocol>(_ s: S) -> String {
        String(s.lowercased().map { ".- :".contains($0) ? "_" : $0 })
    }

    /// Последнее звено пути «Body/…/Neck3/Head».
    static func leaf(_ path: String) -> Substring {
        path.split(separator: "/").last ?? Substring(path)
    }

    /// Индекс кости leaf в путях names: точное имя или путь, кончающийся на «/leaf»; нет — первая кость
    /// с тем же нормализованным последним звеном. leaf с «/» (путь) — только точно.
    static func index(_ names: [String], _ leaf: String) -> Int? {
        if let i = names.firstIndex(where: { $0 == leaf || $0.hasSuffix("/" + leaf) }) { return i }
        guard !leaf.isEmpty, !leaf.contains("/") else { return nil }
        let want = normalized(leaf)
        return names.firstIndex { normalized(Self.leaf($0)) == want }
    }

    /// Все кости в поддереве кости root (по путям), без неё самой.
    static func descendants(_ names: [String], of root: Int) -> Set<Int> {
        guard names.indices.contains(root) else { return [] }
        let prefix = names[root] + "/"
        return Set(names.indices.filter { names[$0].hasPrefix(prefix) })
    }
}
