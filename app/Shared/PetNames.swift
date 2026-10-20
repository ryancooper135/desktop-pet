// Имя того, кто в комнате (волна 14). Шиба — «Шиба», свой персонаж — имя из его character.json
// (SaveFile.petName). Реплики писались под Шибу («Шиба отряхнулся», «Очки Шибы»), а имя пака бывает любым:
// склонять его и угадывать род нельзя. Поэтому adapt ставит имя только туда, где оно в именительном
// и рядом нет слов мужского рода; в остальных местах — «питомец» в нужном падеже: он мужского рода
// и согласуется с «отряхнулся», «доволен», «красавец». У Шибы тексты не меняются.

import Foundation

enum PetNames {
    static let shiba = "Шиба"

    /// Самое длинное имя на экране, в острове и в уведомлениях (в символах).
    static let maxLength = 24

    /// Имя из character.json — в одну строку и разумной длины (волна 23). Перевод строки или управляющие
    /// символы ломали шапку и остров, знаки направления текста (RLE, RLO, изоляты) переворачивали соседние
    /// фразы, а имя в несколько килобайт не помещалось в Live Activity — запуск острова падал. Эмодзи
    /// и буквы любых языков остаются; пустое остаётся пустым (тогда «Шиба»).
    static func clean(_ raw: String) -> String {
        let bidi: ClosedRange<UInt32> = 0x202A...0x202E
        let isolates: ClosedRange<UInt32> = 0x2066...0x2069
        var out = ""
        var space = false
        for u in raw.unicodeScalars {
            let v = u.value
            if v == 0x200E || v == 0x200F || bidi.contains(v) || isolates.contains(v) { continue }
            if u.properties.generalCategory == .control || u.properties.isWhitespace
                || u.properties.generalCategory == .lineSeparator || u.properties.generalCategory == .paragraphSeparator {
                space = !out.isEmpty
                continue
            }
            if space { out.unicodeScalars.append(" "); space = false }
            out.unicodeScalars.append(u)
        }
        guard out.count > maxLength else { return out }
        return String(out.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Пустое имя или «Шиба» — тексты как есть.
    static func isShiba(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty || n == shiba
    }

    /// Питомца больше нет. Имя в именительном, без падежей: «Мурка больше не с нами».
    static func gone(_ name: String) -> String {
        isShiba(name) ? "Шибы больше нет" : "\(name) больше не с нами"
    }

    /// Целые фразы, где замена по словам звучит плохо. Порядок — длинные раньше.
    private static let phrases: [(from: String, to: String)] = [
        ("Шибы больше нет", gonePlaceholder),
        ("Шибы так умеют", "Питомцы так умеют"),
        ("Шиба-улыбка", "Улыбка до ушей"),
    ]

    /// Формы «Шибы» → «питомец» в том же падеже. «Шиба» (именительный) решается отдельно.
    private static let forms: [String: String] = [
        "Шибы": "питомца", "Шибу": "питомца", "Шибе": "питомцу", "Шибой": "питомцем",
    ]

    // Метки на время замены: имя может само содержать «Шиба» («Серый Шиба»), его второй раз не трогаем.
    private static let namePlaceholder = "\u{E000}"
    private static let gonePlaceholder = "\u{E001}"

    /// Реплика под Шибу → под этого питомца. Применять один раз, там где текст собирается.
    static func adapt(_ text: String, name: String) -> String {
        guard !isShiba(name), text.contains("Шиб") else { return text }
        var s = text
        for p in phrases { s = s.replacingOccurrences(of: p.from, with: p.to) }
        let masculine = hasMasculine(s)
        var out = ""
        var word = ""
        var sentenceStart = true
        func flush() {
            guard !word.isEmpty else { return }
            var w = word
            if w == shiba {
                w = masculine ? "питомец" : namePlaceholder
            } else if let f = forms[w] {
                w = f
            }
            if sentenceStart, w != word, let first = w.first, first.isLowercase {
                w = first.uppercased() + w.dropFirst()
            }
            out += w
            word = ""
            sentenceStart = false
        }
        for ch in s {
            if ch.isLetter {
                word.append(ch)
            } else {
                flush()
                out.append(ch)
                if ".!?…".contains(ch) { sentenceStart = true }
                else if !ch.isWhitespace && !("«\"(—–-".contains(ch)) { sentenceStart = false }
            }
        }
        flush()
        return out.replacingOccurrences(of: gonePlaceholder, with: gone(name))
            .replacingOccurrences(of: namePlaceholder, with: name)
    }

    /// Есть ли в тексте слова мужского рода, кроме самой «Шибы»: прошедшее время (отряхнулся, ждал, принёс),
    /// краткие и полные прилагательные (согласен, пушистый). Ошибиться в сторону «питомца» не страшно.
    static func hasMasculine(_ text: String) -> Bool {
        let words = text.split(whereSeparator: { !$0.isLetter }).map { String($0).lowercased() }
        let exact: Set<String> = ["рад", "сам", "красавец", "доволен", "согласен", "один"]
        let endings = ["л", "лся", "ёл", "ёс", "ый", "ий", "ен", "ён"]
        for w in words where !w.hasPrefix("шиб") {
            if exact.contains(w) { return true }
            if w.count > 2, endings.contains(where: { w.hasSuffix($0) }) { return true }
        }
        return false
    }
}
