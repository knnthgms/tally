import Foundation

public struct FormatSettings: Sendable, Equatable {
    /// Decimal places for ordinary numbers (small numbers always keep two significant digits).
    public var decimals: Int = 2
    public var grouping: Bool = true
    public var use24Hour: Bool = false
    public init() {}
}

public final class ResultFormatter: @unchecked Sendable {
    public var settings = FormatSettings()

    public func format(_ v: Value) -> String {
        switch v {
        case .quantity(let q): return format(q)
        case .percent(let p): return number(p) + "%"
        case .date(let d): return format(d)
        }
    }

    public func format(_ q: Quantity) -> String {
        switch q.style {
        case .hex: return radix(q.value, 16, "0x")
        case .binary: return radix(q.value, 2, "0b")
        case .octal: return radix(q.value, 8, "0o")
        case .scientific: return scientific(q.value) + unitSuffix(q)
        case .decimal: break
        }
        if let u = q.unit.single, u.kind == .currency {
            let crypto = CurrencyNames.crypto.contains(u.id)
            let amount = crypto ? number(q.value, minSignificant: 4, maxDecimals: 8) : money(q.value)
            if let p = CurrencyNames.prefix[u.id] {
                return amount.hasPrefix("-") ? "-" + p + amount.dropFirst() : p + amount
            }
            return amount + " " + u.id
        }
        return number(q.value) + unitSuffix(q)
    }

    private func unitSuffix(_ q: Quantity) -> String {
        guard !q.unit.isEmpty else { return "" }
        let text = unitText(q.unit, q.value)
        if text == "°" { return text }
        return " " + text
    }

    /// Unit label: word form ("hours") when a unit stands alone and has one, otherwise symbols ("km/h", "m²").
    public func unitText(_ u: CompoundUnit, _ value: Double) -> String {
        if let s = u.single {
            if let one = s.singular { return Swift.abs(value) == 1 ? one : (s.plural ?? one) }
            return s.symbol
        }
        func sup(_ p: Int) -> String {
            let digits: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
                                                  "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
            return p == 1 ? "" : String(String(p).map { digits[$0] ?? $0 })
        }
        let num = u.terms.filter { $0.power > 0 }.map { $0.unit.symbol + sup($0.power) }
        let den = u.terms.filter { $0.power < 0 }.map { $0.unit.symbol + sup(-$0.power) }
        let top = num.isEmpty ? "1" : num.joined(separator: "·")
        return den.isEmpty ? top : top + "/" + den.joined(separator: "·")
    }

    /// The bare number, without units or grouping, for pasting into other apps.
    public func numberOnly(_ v: Value) -> String {
        let saved = settings.grouping
        settings.grouping = false
        defer { settings.grouping = saved }
        switch v {
        case .quantity(let q):
            if q.style != .decimal { return format(q) }
            if q.unit.isCurrency, !CurrencyNames.crypto.contains(q.unit.single!.id) {
                return plain(q.value, decimals: Swift.max(settings.decimals, 2), minDecimals: 0)
            }
            return number(q.value)
        case .percent(let p): return number(p)
        case .date: return format(v)
        }
    }

    // MARK: Numbers

    public func number(_ x: Double, minSignificant: Int = 2, maxDecimals: Int? = nil) -> String {
        if x.isNaN { return "NaN" }
        if x.isInfinite { return x < 0 ? "-∞" : "∞" }
        if x == 0 { return "0" }
        let ax = Swift.abs(x)
        if ax >= 1e15 || ax < 1e-10 { return scientific(x) }
        var decimals = settings.decimals
        if ax < 1 {
            // Keep enough decimals to show `minSignificant` significant digits.
            let lead = Int(Foundation.floor(-log10(ax)))
            decimals = Swift.max(decimals, lead + minSignificant)
        }
        if let m = maxDecimals { decimals = Swift.min(Swift.max(decimals, minSignificant), m) }
        return plain(x, decimals: Swift.min(decimals, 12), minDecimals: 0)
    }

    private func money(_ x: Double) -> String {
        let cents = (x * 100).rounded() / 100
        let hasFraction = cents != cents.rounded()
        if Swift.abs(x) < 0.01 && x != 0 { return number(x) }
        let d = Swift.max(settings.decimals, 2)
        return plain(x, decimals: hasFraction ? d : 0, minDecimals: hasFraction ? 2 : 0)
    }

    private func plain(_ x: Double, decimals: Int, minDecimals: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = settings.grouping
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        f.maximumFractionDigits = decimals
        f.minimumFractionDigits = minDecimals
        f.roundingMode = .halfUp
        let s = f.string(from: NSNumber(value: x)) ?? String(x)
        return s == "-0" ? "0" : s
    }

    private func scientific(_ x: Double) -> String {
        if x == 0 { return "0" }
        let e = Int(Foundation.floor(log10(Swift.abs(x))))
        let m = x / pow(10, Double(e))
        let mantissa = plain(m, decimals: Swift.max(settings.decimals, 2), minDecimals: 0)
        return "\(mantissa)e\(e)"
    }

    private func radix(_ x: Double, _ r: Int, _ prefix: String) -> String {
        guard Swift.abs(x) < 9.2e18 else { return scientific(x) }
        let n = Int64(x.rounded())
        let digits = String(n.magnitude, radix: r, uppercase: true)
        return (n < 0 ? "-" : "") + prefix + digits
    }

    // MARK: Dates

    public func format(_ d: DateValue) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeZone = d.timeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = d.timeZone
        let sameDay = cal.isDate(d.date, inSameDayAs: Date())
        let sameYear = cal.component(.year, from: d.date) == cal.component(.year, from: Date())
        if !d.hasTime {
            f.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEdMMMM" : "EEEEdMMMMyyyy")
            return f.string(from: d.date)
        }
        let time = settings.use24Hour ? "HHmm" : "hmma"
        var template = time
        if !sameDay { template = (sameYear ? "EEEdMMM" : "EEEdMMMyyyy") + template }
        f.setLocalizedDateFormatFromTemplate(template)
        var s = f.string(from: d.date)
        if d.timeZone.identifier != TimeZone.current.identifier {
            s += " " + (d.timeZone.abbreviation(for: d.date) ?? d.timeZone.identifier)
        }
        return s
    }
}
