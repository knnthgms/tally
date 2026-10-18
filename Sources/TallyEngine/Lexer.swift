import Foundation

/// A raw token. Ranges are UTF-16 offsets within the expression's line, so the editor can highlight them.
struct RawToken {
    enum Kind {
        case number(Double, radix: Int)
        case word(String)
        case op(String)
        case time(h: Int, m: Int, s: Int)
        case date(y: Int, m: Int, d: Int)
    }
    var kind: Kind
    var range: Range<Int>
    /// Whether whitespace immediately precedes this token (multi-word phrases need single spaces between words).
    var spaced: Bool
}

enum Lexer {
    static let currencySymbols = Set(CurrencyNames.symbols.keys)
    static let singleOps: Set<Character> = ["+", "-", "*", "/", "^", "(", ")", "%", "!", "=", "&", "|", ";", ",",
                                            "²", "³", "'", "\"", "~"]

    static func isWordStart(_ c: Character) -> Bool { c.isLetter || c == "_" || c == "°" || c == "µ" }
    static func isWordChar(_ c: Character) -> Bool { isWordStart(c) || c.isNumber && c.isASCII }

    static func tokenize(_ text: String, offset: Int = 0) -> [RawToken] {
        let chars = Array(text)
        // UTF-16 offset of each character position.
        var u16 = [Int](repeating: 0, count: chars.count + 1)
        for (i, c) in chars.enumerated() { u16[i + 1] = u16[i] + c.utf16.count }

        var tokens: [RawToken] = []
        var i = 0
        var spaced = true

        func emit(_ k: RawToken.Kind, _ start: Int, _ end: Int) {
            tokens.append(RawToken(kind: k, range: (offset + u16[start])..<(offset + u16[end]), spaced: spaced))
            spaced = false
        }
        func digit(_ j: Int) -> Bool { j < chars.count && chars[j].isASCII && chars[j].isNumber }
        func int(_ a: Int, _ b: Int) -> Int { Int(String(chars[a..<b])) ?? 0 }

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { spaced = true; i += 1; continue }
            let start = i

            // ISO date 2026-10-18
            if digit(i), i + 9 < chars.count + 0, (0..<10).allSatisfy({ k in
                let ch = chars[i + k]; return k == 4 || k == 7 ? ch == "-" : (ch.isASCII && ch.isNumber)
            }), !digit(i + 10) {
                emit(.date(y: int(i, i + 4), m: int(i + 5, i + 7), d: int(i + 8, i + 10)), i, i + 10)
                i += 10; continue
            }
            // Time 14:30 or 2:30:15
            if digit(i) {
                var j = i
                while digit(j) { j += 1 }
                if j - i <= 2, j < chars.count, chars[j] == ":", digit(j + 1), digit(j + 2), !digit(j + 3) {
                    let h = int(i, j), m = int(j + 1, j + 3)
                    var end = j + 3, s = 0
                    if end < chars.count, chars[end] == ":", digit(end + 1), digit(end + 2) {
                        s = int(end + 1, end + 3); end += 3
                    }
                    emit(.time(h: h, m: m, s: s), i, end)
                    i = end; continue
                }
            }
            // Numbers: 0x / 0b / 0o prefixes, grouping commas, decimals, exponents
            if digit(i) || (c == "." && digit(i + 1)) {
                if c == "0", i + 2 <= chars.count, i + 1 < chars.count, "xXbBoO".contains(chars[i + 1]) {
                    let radix: Int = "xX".contains(chars[i + 1]) ? 16 : "bB".contains(chars[i + 1]) ? 2 : 8
                    var j = i + 2
                    while j < chars.count, chars[j].isHexDigit, Int(String(chars[j]), radix: radix) != nil { j += 1 }
                    if j > i + 2, !(j < chars.count && isWordChar(chars[j])) {
                        let v = Int(String(chars[(i + 2)..<j]), radix: radix) ?? 0
                        emit(.number(Double(v), radix: radix), i, j); i = j; continue
                    }
                }
                var s = ""
                var j = i
                while j < chars.count {
                    if digit(j) { s.append(chars[j]); j += 1; continue }
                    // 1,000,000 — comma followed by exactly three digits
                    if chars[j] == ",", !s.contains("."), digit(j + 1), digit(j + 2), digit(j + 3), !digit(j + 4) {
                        s += String(chars[(j + 1)...(j + 3)]); j += 4; continue
                    }
                    if chars[j] == ".", !s.contains("."), !s.contains("e"), digit(j + 1) {
                        s.append("."); j += 1; continue
                    }
                    if chars[j] == "e" || chars[j] == "E", !s.contains("e") {
                        if digit(j + 1) { s += "e"; j += 1; continue }
                        if j + 1 < chars.count, "+-".contains(chars[j + 1]), digit(j + 2) {
                            s += "e" + String(chars[j + 1]); j += 2; continue
                        }
                    }
                    break
                }
                emit(.number(Double(s) ?? 0, radix: 10), i, j)
                i = j; continue
            }
            if isWordStart(c) {
                var j = i + 1
                while j < chars.count, isWordChar(chars[j]) { j += 1 }
                emit(.word(String(chars[i..<j])), i, j)
                i = j; continue
            }
            if i + 1 < chars.count {
                let two = String(chars[i...(i + 1)])
                if ["<<", ">>", "**"].contains(two) {
                    emit(.op(two == "**" ? "^" : two), i, i + 2); i += 2; continue
                }
            }
            if currencySymbols.contains(String(c)) { emit(.op(String(c)), i, i + 1); i += 1; continue }
            switch c {
            case "×", "·": emit(.op("*"), i, i + 1)
            case "÷": emit(.op("/"), i, i + 1)
            case "−", "–": emit(.op("-"), i, i + 1)
            case "π": emit(.word("π"), i, i + 1)
            default:
                if singleOps.contains(c) { emit(.op(String(c)), i, i + 1) } else { spaced = true }
            }
            i = start + 1
        }
        return tokens
    }
}
