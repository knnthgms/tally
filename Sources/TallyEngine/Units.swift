import Foundation

/// Exponents over the base dimensions: length, mass, time, temperature, data, currency, angle.
public struct Dim: Hashable, Sendable {
    public var v: [Int]
    public init(_ v: [Int] = [0, 0, 0, 0, 0, 0, 0]) { self.v = v }

    static func base(_ i: Int) -> Dim { var d = Dim(); d.v[i] = 1; return d }
    public static let none = Dim()
    public static let length = base(0), mass = base(1), time = base(2), temperature = base(3)
    public static let data = base(4), currency = base(5), angle = base(6)

    public var isNone: Bool { v.allSatisfy { $0 == 0 } }
    static func + (a: Dim, b: Dim) -> Dim { Dim(zip(a.v, b.v).map(+)) }
    static func * (a: Dim, p: Int) -> Dim { Dim(a.v.map { $0 * p }) }
}

public final class UnitDef: Hashable, @unchecked Sendable {
    public enum Kind: Sendable { case normal, currency, pixel, em, temperature }

    public let id: String
    public let dim: Dim
    public let factor: Double      // multiply to get base units
    public let offset: Double      // temperatures only
    public let symbol: String      // short form, used inside compound units
    public let singular: String?   // word form used when the unit stands alone
    public let plural: String?
    public let kind: Kind

    init(_ id: String, _ dim: Dim, _ factor: Double, symbol: String? = nil, words: (String, String)? = nil,
         kind: Kind = .normal, offset: Double = 0) {
        self.id = id; self.dim = dim; self.factor = factor; self.offset = offset
        self.symbol = symbol ?? id; self.singular = words?.0; self.plural = words?.1; self.kind = kind
    }

    public static func == (a: UnitDef, b: UnitDef) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }

    public var isTime: Bool { dim == .time }
}

/// All known units plus the words that name them.
public final class UnitCatalog: @unchecked Sendable {
    public private(set) var byID: [String: UnitDef] = [:]
    private var caseSensitive: [String: UnitDef] = [:]
    private var caseInsensitive: [String: UnitDef] = [:]
    /// Longest phrase in words, used by the tokenizer for multi-word lookups.
    private(set) var maxPhraseWords = 1

    public init() { buildStandard() }

    public func unit(_ id: String) -> UnitDef? { byID[id] }

    func lookup(_ phrase: String) -> UnitDef? {
        caseSensitive[phrase] ?? caseInsensitive[phrase.lowercased()]
    }

    @discardableResult
    func add(_ u: UnitDef, _ phrases: [String], cs: [String] = []) -> UnitDef {
        byID[u.id] = u
        for p in phrases { caseInsensitive[p.lowercased()] = u; note(p) }
        for p in cs { caseSensitive[p] = u; note(p) }
        return u
    }

    private func note(_ p: String) {
        maxPhraseWords = max(maxPhraseWords, p.split(separator: " ").count)
    }

    /// Registers a currency code (and optional extra names) as a unit.
    func addCurrency(_ code: String, names: [String] = [], lowercaseCode: Bool = false) {
        let u = byID[code] ?? UnitDef(code, .currency, 1, symbol: code, kind: .currency)
        add(u, names + (lowercaseCode ? [code.lowercased()] : []), cs: [code])
    }

    // MARK: - Standard units

    private func buildStandard() {
        let L = Dim.length, M = Dim.mass, T = Dim.time, D = Dim.data, A = Dim.angle
        let area = L * 2, vol = L * 3, speed = L + T * -1, freq = T * -1

        func w(_ s: String, _ p: String? = nil) -> (String, String) { (s, p ?? s + "s") }

        // Length (metre)
        add(UnitDef("m", L, 1), ["meter", "meters", "metre", "metres"], cs: ["m"])
        let siLength: [(String, String, Double)] = [("k", "kilo", 1e3), ("c", "centi", 1e-2), ("m", "milli", 1e-3),
                                                  ("d", "deci", 1e-1), ("µ", "micro", 1e-6), ("n", "nano", 1e-9)]
        for (p, word, f) in siLength {
            var cs = [p + "m"]
            if p == "µ" { cs.append("um") }
            add(UnitDef(p + "m", L, f), [word + "meter", word + "meters", word + "metre", word + "metres"], cs: cs)
        }
        add(UnitDef("micron", L, 1e-6, words: w("micron")), ["micron", "microns"])
        add(UnitDef("in", L, 0.0254), ["inch", "inches", "\""])
        add(UnitDef("ft", L, 0.3048), ["foot", "feet", "ft", "'"])
        add(UnitDef("yd", L, 0.9144), ["yard", "yards", "yd", "yds"])
        add(UnitDef("mi", L, 1609.344), ["mile", "miles", "mi"])
        add(UnitDef("nmi", L, 1852), ["nautical mile", "nautical miles", "nmi"])
        add(UnitDef("mil", L, 0.0000254, words: w("mil")), ["mil", "mils", "thou"])
        add(UnitDef("line", L, 0.0254 / 12, words: w("line")), ["line", "lines"])
        add(UnitDef("hand", L, 0.1016, words: w("hand")), ["hand", "hands"])
        add(UnitDef("rod", L, 5.0292, words: w("rod")), ["rod", "rods"])
        add(UnitDef("chain", L, 20.1168, words: w("chain")), ["chain", "chains"])
        add(UnitDef("furlong", L, 201.168, words: w("furlong")), ["furlong", "furlongs"])
        add(UnitDef("cable", L, 185.2, words: w("cable")), ["cable", "cables"])
        add(UnitDef("league", L, 4828.032, words: w("league")), ["league", "leagues"])
        add(UnitDef("ly", L, 9.4607304725808e15, words: w("light year")), ["light year", "light years", "lightyear", "lightyears", "ly"])
        add(UnitDef("au", L, 1.495978707e11), ["astronomical unit", "astronomical units", "au"])
        add(UnitDef("pc", L, 3.0856775814913673e16), ["parsec", "parsecs", "pc"])
        // Typography / CSS
        add(UnitDef("pt", L, 0.0254 / 72), ["point", "points", "pt", "pts"])
        add(UnitDef("px", L, 0.0254 / 96, kind: .pixel), ["pixel", "pixels", "px"])
        add(UnitDef("em", L, 16 * 0.0254 / 96, kind: .em), ["em", "ems", "rem", "rems"])

        // Area (square metre)
        add(UnitDef("ha", area, 1e4, words: w("hectare")), ["hectare", "hectares", "ha"])
        add(UnitDef("are", area, 100, words: w("are")), ["ares"])
        add(UnitDef("acre", area, 4046.8564224, words: w("acre")), ["acre", "acres", "ac"])

        // Volume (cubic metre)
        add(UnitDef("L", vol, 1e-3), ["liter", "liters", "litre", "litres"], cs: ["l", "L"])
        add(UnitDef("ml", vol, 1e-6), ["milliliter", "milliliters", "millilitre", "millilitres", "ml", "mL"])
        add(UnitDef("cl", vol, 1e-5), ["centiliter", "centiliters", "centilitre", "centilitres", "cl", "cL"])
        add(UnitDef("dl", vol, 1e-4), ["deciliter", "deciliters", "decilitre", "decilitres", "dl", "dL"])
        add(UnitDef("gal", vol, 0.003785411784, words: w("gallon")), ["gallon", "gallons", "gal"])
        add(UnitDef("qt", vol, 0.000946352946, words: w("quart")), ["quart", "quarts", "qt"])
        add(UnitDef("pint", vol, 0.000473176473, words: w("pint")), ["pint", "pints"])
        add(UnitDef("cup", vol, 0.0002365882365, words: w("cup")), ["cups"], cs: ["cup", "Cup"])
        add(UnitDef("floz", vol, 2.95735295625e-5, symbol: "fl oz"), ["fluid ounce", "fluid ounces", "fl oz", "floz"])
        add(UnitDef("tbsp", vol, 1.478676478125e-5), ["tablespoon", "tablespoons", "table spoon", "table spoons", "tbsp", "tbs"])
        add(UnitDef("tsp", vol, 4.92892159375e-6), ["teaspoon", "teaspoons", "tea spoon", "tea spoons", "tsp"])

        // Mass (kilogram)
        add(UnitDef("kg", M, 1), ["kilogram", "kilograms", "kilo", "kilos", "kilogramme", "kilogrammes", "kg", "kgs"])
        add(UnitDef("g", M, 1e-3), ["gram", "grams", "gramme", "grammes", "g", "gr"])
        add(UnitDef("mg", M, 1e-6), ["milligram", "milligrams", "mg"])
        add(UnitDef("µg", M, 1e-9), ["microgram", "micrograms", "µg", "ug", "mcg"])
        add(UnitDef("t", M, 1000), ["tonne", "tonnes", "metric ton", "metric tons"], cs: ["t"])
        add(UnitDef("ton", M, 907.18474, words: w("ton")), ["ton", "tons", "short ton", "short tons"])
        add(UnitDef("lb", M, 0.45359237), ["pound", "pounds", "lb", "lbs"])
        add(UnitDef("oz", M, 0.028349523125), ["ounce", "ounces", "oz"])
        add(UnitDef("st", M, 6.35029318, words: w("stone", "stone")), ["stone", "stones", "st"])
        add(UnitDef("ct", M, 0.0002, words: w("carat")), ["carat", "carats", "ct"])
        add(UnitDef("centner", M, 100, words: w("centner")), ["centner", "centners"])

        // Time (second)
        add(UnitDef("ns", T, 1e-9), ["nanosecond", "nanoseconds", "ns"])
        add(UnitDef("µs", T, 1e-6), ["microsecond", "microseconds", "µs", "us"])
        add(UnitDef("ms", T, 1e-3), ["millisecond", "milliseconds", "ms"])
        add(UnitDef("s", T, 1, words: w("second")), ["second", "seconds", "sec", "secs", "s"])
        add(UnitDef("min", T, 60, words: w("minute")), ["minute", "minutes", "min", "mins"])
        add(UnitDef("h", T, 3600, words: w("hour")), ["hour", "hours", "h", "hr", "hrs"])
        add(UnitDef("day", T, 86400, symbol: "d", words: w("day")), ["day", "days", "d"])
        add(UnitDef("week", T, 604800, symbol: "wk", words: w("week")), ["week", "weeks", "wk", "wks"])
        add(UnitDef("fortnight", T, 1209600, words: w("fortnight")), ["fortnight", "fortnights"])
        add(UnitDef("month", T, 2629746, symbol: "mo", words: w("month")), ["month", "months", "mo", "mos"])
        add(UnitDef("year", T, 31556952, symbol: "yr", words: w("year")), ["year", "years", "yr", "yrs"])
        add(UnitDef("decade", T, 315569520, words: w("decade")), ["decade", "decades"])
        add(UnitDef("century", T, 3155695200, words: w("century", "centuries")), ["century", "centuries"])

        // Temperature (kelvin)
        add(UnitDef("K", .temperature, 1, kind: .temperature), ["kelvin", "kelvins"], cs: ["K"])
        add(UnitDef("°C", .temperature, 1, kind: .temperature, offset: 273.15),
            ["celsius", "centigrade", "°c", "degc", "degrees celsius", "degree celsius"], cs: ["C"])
        add(UnitDef("°F", .temperature, 5.0 / 9, kind: .temperature, offset: 273.15 - 32 * 5.0 / 9),
            ["fahrenheit", "°f", "degf", "degrees fahrenheit", "degree fahrenheit"], cs: ["F"])

        // Angle (radian)
        add(UnitDef("rad", A, 1), ["radian", "radians", "rad", "rads"])
        add(UnitDef("°", A, .pi / 180), ["degree", "degrees", "deg", "°"])
        add(UnitDef("turn", A, 2 * .pi, words: w("turn")), ["turn", "turns", "revolution", "revolutions"])
        add(UnitDef("arcmin", A, .pi / 10800), ["arcminute", "arcminutes", "arcmin"])
        add(UnitDef("arcsec", A, .pi / 648000), ["arcsecond", "arcseconds", "arcsec"])

        // Data (bit)
        add(UnitDef("b", D, 1, symbol: "bit", words: w("bit")), ["bit", "bits"], cs: ["b"])
        add(UnitDef("B", D, 8), ["byte", "bytes"], cs: ["B"])
        let si: [(String, String, Double)] = [("k", "kilo", 1e3), ("M", "mega", 1e6), ("G", "giga", 1e9),
                                              ("T", "tera", 1e12), ("P", "peta", 1e15)]
        for (p, word, f) in si {
            let up = p.uppercased()
            add(UnitDef(up + "B", D, 8 * f), [word + "byte", word + "bytes", up.lowercased() + "b"], cs: [up + "B", p + "B"])
            add(UnitDef(up + "bit", D, f, symbol: up + "b"), [word + "bit", word + "bits"], cs: [up + "b", up + "bit"])
            add(UnitDef(up + "bps", speedOfData, f, symbol: up + "bps"), [word + "bits per second"], cs: [up + "bps", p + "bps"])
        }
        let iec: [(String, String, Double)] = [("Ki", "kibi", 1024), ("Mi", "mebi", 1048576), ("Gi", "gibi", 1073741824),
                                               ("Ti", "tebi", 1099511627776), ("Pi", "pebi", 1125899906842624)]
        for (p, word, f) in iec {
            add(UnitDef(p + "B", D, 8 * f), [word + "byte", word + "bytes"], cs: [p + "B"])
            add(UnitDef(p + "bit", D, f, symbol: p + "b"), [word + "bit", word + "bits"], cs: [p + "b", p + "bit"])
        }
        add(UnitDef("bps", speedOfData, 1), ["bits per second"], cs: ["bps"])

        // Speed & frequency
        add(UnitDef("km/h", speed, 1000.0 / 3600), ["kph", "kmh", "kmph"])
        add(UnitDef("mph", speed, 0.44704), ["mph"])
        add(UnitDef("kn", speed, 1852.0 / 3600, words: w("knot")), ["knot", "knots", "kn", "kt"])
        add(UnitDef("Hz", freq, 1), ["hertz", "hz"])
        add(UnitDef("kHz", freq, 1e3), ["kilohertz", "khz"])
        add(UnitDef("MHz", freq, 1e6), ["megahertz", "mhz"])
        add(UnitDef("GHz", freq, 1e9), ["gigahertz", "ghz"])
    }

    private var speedOfData: Dim { Dim.data + Dim.time * -1 }
}

/// A product of units raised to integer powers, e.g. km/h or m².
public struct CompoundUnit: Equatable, Sendable {
    public struct Term: Equatable, Sendable { public let unit: UnitDef; public var power: Int }
    public var terms: [Term]

    public init(_ terms: [Term] = []) { self.terms = terms }
    public init(_ u: UnitDef, _ p: Int = 1) { terms = [Term(unit: u, power: p)] }

    public static let none = CompoundUnit()
    public var isEmpty: Bool { terms.isEmpty }
    public var dim: Dim { terms.reduce(Dim.none) { $0 + $1.unit.dim * $1.power } }
    public var single: UnitDef? { terms.count == 1 && terms[0].power == 1 ? terms[0].unit : nil }
    public var isCurrency: Bool { single?.kind == .currency }

    func raised(_ p: Int) -> CompoundUnit {
        CompoundUnit(terms.map { Term(unit: $0.unit, power: $0.power * p) })
    }
}
