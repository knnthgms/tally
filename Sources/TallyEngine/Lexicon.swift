import Foundation

enum Keyword: String {
    case `in`, to, `as`, into, of, on, off, what, `is`, a, per
    case plus, minus, times, divide, mod, xor
    case prev, sum, avg, now, time, today, tomorrow, yesterday, next, last, this, ago, fromNow
    case am, pm, hex, bin, oct, sci, dec, unix, percent
    case square, cubic, squared, cubed, root
}

enum MathFunction: String, CaseIterable {
    case sqrt, cbrt, abs, log, ln, exp, fact, round, ceil, floor, trunc
    case sin, cos, tan, asin, acos, atan, sinh, cosh, tanh, fromunix
}

enum Meaning {
    case unit(UnitDef, power: Int)
    case keyword(Keyword)
    case function(MathFunction)
    case constant(Double)
    case timeZone(TimeZone)
    case month(Int)
    case weekday(Int)   // Calendar weekday: 1 = Sunday
    case scale(Double)
}

/// Tokens after multi-word phrases are merged and words have been looked up.
struct Tok {
    enum Kind {
        case number(Double, radix: Int)
        case op(String)
        case time(h: Int, m: Int, s: Int)
        case date(y: Int, m: Int, d: Int)
        case phrase(String, [Meaning])
        case variable(String)
    }
    var kind: Kind
    var range: Range<Int>
}

final class Lexicon {
    let catalog: UnitCatalog
    private var keywords: [String: Keyword] = [:]
    private var functions: [String: MathFunction] = [:]
    private var constants: [String: Double] = ["pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi, "τ": 2 * .pi,
                                               "phi": (1 + 5.squareRoot()) / 2]
    private var scalesCS: [String: Double] = ["k": 1e3, "M": 1e6]
    private var scales: [String: Double] = ["thousand": 1e3, "thousands": 1e3, "million": 1e6, "millions": 1e6,
                                            "billion": 1e9, "billions": 1e9, "bn": 1e9, "trillion": 1e12,
                                            "trillions": 1e12, "mn": 1e6, "lakh": 1e5, "lakhs": 1e5, "lac": 1e5,
                                            "crore": 1e7, "crores": 1e7, "dozen": 12, "hundred": 100]
    private var timeZonesCS: [String: TimeZone] = [:]
    private var timeZones: [String: TimeZone] = [:]
    private var months: [String: Int] = [:]
    private var weekdays: [String: Int] = [:]
    private(set) var maxWords = 4

    init(catalog: UnitCatalog) {
        self.catalog = catalog
        let kw: [(Keyword, [String])] = [
            (.in, ["in"]), (.to, ["to"]), (.as, ["as"]), (.into, ["into"]), (.of, ["of"]), (.on, ["on"]),
            (.off, ["off"]), (.what, ["what"]), (.is, ["is"]), (.a, ["a", "an"]), (.per, ["per"]),
            (.plus, ["plus", "and", "with", "add"]), (.minus, ["minus", "without", "subtract", "less"]),
            (.times, ["times", "mul", "multiplied by", "multiply by", "x"]),
            (.divide, ["divide", "divided by", "divide by", "over"]),
            (.mod, ["mod", "modulo"]), (.xor, ["xor"]),
            (.prev, ["prev", "previous", "ans"]), (.sum, ["sum", "total"]), (.avg, ["avg", "average", "mean"]),
            (.now, ["now"]), (.time, ["time"]), (.today, ["today"]), (.tomorrow, ["tomorrow"]),
            (.yesterday, ["yesterday"]), (.next, ["next"]), (.last, ["last"]), (.this, ["this"]), (.ago, ["ago"]),
            (.fromNow, ["from now", "later"]), (.am, ["am", "a.m."]), (.pm, ["pm", "p.m."]),
            (.hex, ["hex", "hexadecimal"]), (.bin, ["bin", "binary"]), (.oct, ["oct", "octal"]),
            (.sci, ["sci", "scientific", "exponential"]), (.dec, ["decimal", "dec"]), (.unix, ["unix", "timestamp"]),
            (.percent, ["percent", "percentage", "pct"]),
            (.square, ["square", "sq"]), (.cubic, ["cubic", "cu"]), (.squared, ["squared"]), (.cubed, ["cubed"]),
            (.root, ["root"]),
        ]
        for (k, words) in kw { for w in words { keywords[w] = k } }
        for f in MathFunction.allCases { functions[f.rawValue] = f }
        functions["arcsin"] = .asin; functions["arccos"] = .acos; functions["arctan"] = .atan
        functions["factorial"] = .fact; functions["log10"] = .log

        let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august",
                          "september", "october", "november", "december"]
        for (i, m) in monthNames.enumerated() {
            months[m] = i + 1
            months[String(m.prefix(3))] = i + 1
        }
        months["sept"] = 9
        let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (i, d) in dayNames.enumerated() {
            weekdays[d] = i + 1
            weekdays[String(d.prefix(3))] = i + 1
        }
        weekdays["tues"] = 3; weekdays["thurs"] = 5; weekdays["weds"] = 4

        buildTimeZones()
    }

    private func buildTimeZones() {
        for (abbr, id) in TimeZone.abbreviationDictionary {
            if let tz = TimeZone(identifier: id) { timeZonesCS[abbr] = tz }
        }
        // Common abbreviations Foundation misses or maps oddly.
        let extra: [String: String] = [
            "UTC": "UTC", "GMT": "GMT", "Z": "UTC", "IST": "Asia/Kolkata", "CET": "Europe/Paris", "CEST": "Europe/Paris",
            "AEST": "Australia/Sydney", "AEDT": "Australia/Sydney", "HKT": "Asia/Hong_Kong", "SGT": "Asia/Singapore",
            "PT": "America/Los_Angeles", "ET": "America/New_York", "CT": "America/Chicago", "MT": "America/Denver",
            "KST": "Asia/Seoul", "JST": "Asia/Tokyo", "MSK": "Europe/Moscow", "WIB": "Asia/Jakarta",
        ]
        for (abbr, id) in extra { if let tz = TimeZone(identifier: id) { timeZonesCS[abbr] = tz } }
        timeZones["utc"] = TimeZone(identifier: "UTC"); timeZones["gmt"] = TimeZone(identifier: "GMT")
        timeZones["local"] = .current

        for id in TimeZone.knownTimeZoneIdentifiers {
            let parts = id.split(separator: "/")
            guard parts.count == 2, parts[0] != "Etc", let tz = TimeZone(identifier: id), let city = parts.last else { continue }
            timeZones[city.replacingOccurrences(of: "_", with: " ").lowercased()] = tz
        }
        let cities: [String: String] = [
            "san francisco": "America/Los_Angeles", "seattle": "America/Los_Angeles", "las vegas": "America/Los_Angeles",
            "silicon valley": "America/Los_Angeles", "california": "America/Los_Angeles", "boston": "America/New_York",
            "washington": "America/New_York", "miami": "America/New_York", "atlanta": "America/New_York",
            "dallas": "America/Chicago", "houston": "America/Chicago", "austin": "America/Chicago",
            "beijing": "Asia/Shanghai", "shenzhen": "Asia/Shanghai", "china": "Asia/Shanghai",
            "mumbai": "Asia/Kolkata", "bombay": "Asia/Kolkata", "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata",
            "bangalore": "Asia/Kolkata", "bengaluru": "Asia/Kolkata", "goa": "Asia/Kolkata", "chennai": "Asia/Kolkata",
            "hyderabad": "Asia/Kolkata", "pune": "Asia/Kolkata", "india": "Asia/Kolkata",
            "japan": "Asia/Tokyo", "osaka": "Asia/Tokyo", "kyoto": "Asia/Tokyo", "korea": "Asia/Seoul",
            "uk": "Europe/London", "england": "Europe/London", "manchester": "Europe/London", "edinburgh": "Europe/London",
            "france": "Europe/Paris", "germany": "Europe/Berlin", "munich": "Europe/Berlin", "frankfurt": "Europe/Berlin",
            "hamburg": "Europe/Berlin", "spain": "Europe/Madrid", "barcelona": "Europe/Madrid", "italy": "Europe/Rome",
            "milan": "Europe/Rome", "portugal": "Europe/Lisbon", "porto": "Europe/Lisbon", "netherlands": "Europe/Amsterdam",
            "geneva": "Europe/Zurich", "switzerland": "Europe/Zurich", "russia": "Europe/Moscow",
            "st petersburg": "Europe/Moscow", "uae": "Asia/Dubai", "abu dhabi": "Asia/Dubai", "melbourne": "Australia/Melbourne",
            "canberra": "Australia/Sydney", "new zealand": "Pacific/Auckland", "wellington": "Pacific/Auckland",
            "montreal": "America/Toronto", "ottawa": "America/Toronto", "rio": "America/Sao_Paulo",
            "rio de janeiro": "America/Sao_Paulo", "brazil": "America/Sao_Paulo", "mexico": "America/Mexico_City",
            "hawaii": "Pacific/Honolulu", "kyiv": "Europe/Kiev", "kiev": "Europe/Kiev", "beirut": "Asia/Beirut",
        ]
        for (name, id) in cities { if let tz = TimeZone(identifier: id) { timeZones[name] = tz } }
    }

    /// Everything a phrase could mean. Empty means unknown.
    func meanings(_ phrase: String, rates: CurrencyRates) -> [Meaning] {
        let lower = phrase.lowercased()
        var out: [Meaning] = []
        if let s = scalesCS[phrase] { out.append(.scale(s)) }
        if let k = keywords[lower] { out.append(.keyword(k)) }
        if let u = catalog.lookup(phrase) { out.append(.unit(u, power: 1)) }
        else if let u = currency(phrase, rates: rates) { out.append(.unit(u, power: 1)) }
        else if let last = phrase.last, last == "2" || last == "3", let u = catalog.lookup(String(phrase.dropLast())),
                u.dim == .length {
            out.append(.unit(u, power: last == "2" ? 2 : 3))
        }
        if let f = functions[lower] { out.append(.function(f)) }
        if let c = constants[phrase] ?? constants[lower] { out.append(.constant(c)) }
        if let s = scales[lower] { out.append(.scale(s)) }
        if let m = months[lower] { out.append(.month(m)) }
        if let d = weekdays[lower] { out.append(.weekday(d)) }
        if let tz = timeZonesCS[phrase] ?? timeZones[lower] { out.append(.timeZone(tz)) }
        return out
    }

    private func currency(_ phrase: String, rates: CurrencyRates) -> UnitDef? {
        if phrase.count >= 3, phrase.count <= 5, phrase == phrase.uppercased(), rates.rate(phrase) != nil {
            catalog.addCurrency(phrase)
            return catalog.unit(phrase)
        }
        return nil
    }

    /// Merges multi-word phrases (longest match wins), resolves words, and drops words nobody understands.
    func resolve(_ raw: [RawToken], variables: Set<String>, rates: CurrencyRates) -> [Tok] {
        var out: [Tok] = []
        var i = 0
        while i < raw.count {
            let t = raw[i]
            switch t.kind {
            case .number(let v, let r): out.append(Tok(kind: .number(v, radix: r), range: t.range))
            case .op(let s): out.append(Tok(kind: .op(s), range: t.range))
            case .time(let h, let m, let s): out.append(Tok(kind: .time(h: h, m: m, s: s), range: t.range))
            case .date(let y, let m, let d): out.append(Tok(kind: .date(y: y, m: m, d: d), range: t.range))
            case .word(let w):
                // Try the longest run of space-separated words first; variables win over built-in words.
                var words = [w]
                var j = i + 1
                while j < raw.count, words.count < maxWords, raw[j].spaced, case .word(let nw) = raw[j].kind {
                    words.append(nw); j += 1
                }
                var matched = false
                for n in stride(from: words.count, through: 1, by: -1) {
                    let phrase = words[0..<n].joined(separator: " ")
                    if variables.contains(phrase) {
                        out.append(Tok(kind: .variable(phrase), range: t.range.lowerBound..<raw[i + n - 1].range.upperBound))
                        i += n; matched = true; break
                    }
                    let m = meanings(phrase, rates: rates)
                    if !m.isEmpty {
                        out.append(Tok(kind: .phrase(phrase, m), range: t.range.lowerBound..<raw[i + n - 1].range.upperBound))
                        i += n; matched = true; break
                    }
                }
                if matched { continue }
                // "a.m." style: word followed by '.' is not tokenized; unknown words are skipped.
            }
            i += 1
        }
        return out
    }
}
