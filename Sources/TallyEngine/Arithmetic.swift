import Foundation

/// Evaluation state for one document: variables plus access to rates and settings.
final class Scope {
    let engine: Engine
    var variables: [String: Value]
    var calendar: Calendar

    init(engine: Engine) {
        self.engine = engine
        variables = [:]
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = engine.timeZone
    }

    var now: Date { engine.now() }

    private var ppi: Double {
        if let v = variables["ppi"]?.plainNumber, v > 0 { return v }
        return 96
    }

    private var emPixels: Double {
        if case .quantity(let q)? = variables["em"] {
            if q.unit.isEmpty { return q.value }
            if q.unit.single?.kind == .pixel { return q.value }
        }
        return 16
    }

    func factor(_ u: UnitDef) -> Double {
        switch u.kind {
        case .currency: return 1 / (engine.rates.rate(u.id) ?? .nan)
        case .pixel: return 0.0254 / ppi
        case .em: return emPixels * 0.0254 / ppi
        default: return u.factor
        }
    }

    func factor(_ c: CompoundUnit) -> Double {
        c.terms.reduce(1.0) { $0 * pow(factor($1.unit), Double($1.power)) }
    }

    // MARK: Conversion

    func convert(_ q: Quantity, to target: CompoundUnit) throws -> Quantity {
        var q = q
        if target.isCurrency, case .quantity(let s) = settled(.quantity(q)) { q = s }
        if q.unit.isEmpty || target.isEmpty { return Quantity(q.value, target, style: q.style) }
        guard q.unit.dim == target.dim else {
            throw CalcError("Can't convert \(engine.formatter.unitText(q.unit, 2)) to \(engine.formatter.unitText(target, 2))")
        }
        if let a = q.unit.single, let b = target.single, a.kind == .temperature, b.kind == .temperature {
            let base = q.value * a.factor + a.offset
            return Quantity((base - b.offset) / b.factor, target, style: q.style)
        }
        return Quantity(q.value * factor(q.unit) / factor(target), target, style: q.style)
    }

    /// Value in base units (for comparing quantities of the same dimension).
    func baseValue(_ q: Quantity) -> Double { q.value * factor(q.unit) }

    // MARK: Units algebra

    /// Multiplies two quantities, merging units of the same dimension (2 m × 30 cm = 0.6 m²).
    func multiply(_ a: Quantity, _ b: Quantity, divide: Bool = false) -> Quantity {
        var value = divide ? a.value / b.value : a.value * b.value
        var terms = a.unit.terms
        for t in b.unit.terms {
            let p = divide ? -t.power : t.power
            if let k = terms.firstIndex(where: { $0.unit == t.unit }) {
                terms[k].power += p
            } else if let k = terms.firstIndex(where: { $0.unit.dim == t.unit.dim && $0.unit.kind != .temperature }) {
                value *= pow(factor(t.unit) / factor(terms[k].unit), Double(p))
                terms[k].power += p
            } else {
                terms.append(CompoundUnit.Term(unit: t.unit, power: p))
            }
        }
        terms.removeAll { $0.power == 0 }
        var unit = CompoundUnit(terms)
        if !unit.isEmpty && unit.dim.isNone {
            value *= factor(unit)
            unit = .none
        }
        let style = a.style != .decimal ? a.style : b.style
        return Quantity(value, unit, style: style)
    }

    /// Money times a count-like unit is just money (5 days × €45 = €225, not 225 d·EUR).
    /// Applied lazily, so rates still cancel (5 days × €45 / day = €225); per-unit prices (€/d) are kept.
    func settled(_ v: Value) -> Value {
        guard case .quantity(let q) = v else { return v }
        let money = q.unit.terms.filter { $0.unit.kind == .currency }
        guard q.unit.terms.count > 1, money.count == 1, money[0].power == 1,
              q.unit.terms.allSatisfy({ $0.power > 0 }) else { return v }
        return .quantity(Quantity(q.value, CompoundUnit(money[0].unit), style: q.style))
    }

    func power(_ a: Quantity, _ e: Double) throws -> Quantity {
        if a.unit.isEmpty { return Quantity(pow(a.value, e), style: a.style) }
        if e == e.rounded() {
            return Quantity(pow(a.value, e), a.unit.raised(Int(e)), style: a.style)
        }
        // Fractional powers only when every unit power divides evenly (sqrt of m² → m).
        let inv = 1 / e
        if inv == inv.rounded(), a.unit.terms.allSatisfy({ $0.power % Int(inv) == 0 }) {
            let terms = a.unit.terms.map { CompoundUnit.Term(unit: $0.unit, power: $0.power / Int(inv)) }
            return Quantity(pow(a.value, e), CompoundUnit(terms), style: a.style)
        }
        throw CalcError("Can't raise units to a fractional power")
    }

    // MARK: Value operations

    func add(_ a: Value, _ b: Value, sign: Double) throws -> Value {
        switch (settled(a), settled(b)) {
        case (.quantity(let x), .quantity(let y)):
            if x.unit.isEmpty && !y.unit.isEmpty {
                // 5 + $3 → $8
                return .quantity(Quantity(x.value + sign * y.value, y.unit, style: x.style))
            }
            if y.unit.isEmpty { return .quantity(Quantity(x.value + sign * y.value, x.unit, style: x.style)) }
            let yc = try convert(y, to: x.unit)
            return .quantity(Quantity(x.value + sign * yc.value, x.unit, style: x.style))
        case (.quantity(let x), .percent(let p)):
            return .quantity(Quantity(x.value * (1 + sign * p / 100), x.unit, style: x.style))
        case (.percent(let p), .percent(let r)):
            return .percent(p + sign * r)
        case (.percent(let p), .quantity(let y)):
            return .quantity(Quantity(p / 100 + sign * y.value, y.unit))
        case (.date(let d), .quantity(let q)):
            return .date(try shift(d, by: q, sign: sign))
        case (.quantity(let q), .date(let d)) where sign > 0:
            return .date(try shift(d, by: q, sign: 1))
        case (.date(let x), .date(let y)) where sign < 0:
            return .quantity(difference(x, y))
        default:
            throw CalcError("Can't \(sign > 0 ? "add" : "subtract") those")
        }
    }

    func mul(_ a: Value, _ b: Value) throws -> Value {
        switch (a, b) {
        case (.quantity(let x), .quantity(let y)): return .quantity(multiply(x, y))
        case (.quantity(let x), .percent(let p)): return .quantity(Quantity(x.value * p / 100, x.unit, style: x.style))
        case (.percent(let p), .quantity(let y)):
            return .quantity(Quantity(y.value * p / 100, y.unit, style: y.style))
        case (.percent(let p), .percent(let r)): return .percent(p * r / 100)
        default: throw CalcError("Can't multiply those")
        }
    }

    func div(_ a: Value, _ b: Value) throws -> Value {
        switch (a, b) {
        case (.quantity(let x), .quantity(let y)): return .quantity(multiply(x, y, divide: true))
        case (.quantity(let x), .percent(let p)): return .quantity(Quantity(x.value / (p / 100), x.unit, style: x.style))
        case (.percent(let p), .quantity(let y)) where y.unit.isEmpty: return .percent(p / y.value)
        case (.percent(let p), .percent(let r)): return .number(p / r)
        default: throw CalcError("Can't divide those")
        }
    }

    func mod(_ a: Value, _ b: Value) throws -> Value {
        guard case .quantity(let x) = a, case .quantity(let y) = b else { throw CalcError("Can't take modulo of those") }
        let yc = y.unit.isEmpty ? y : try convert(y, to: x.unit)
        let r = x.value.truncatingRemainder(dividingBy: yc.value)
        return .quantity(Quantity(r, x.unit, style: x.style))
    }

    func integerOp(_ a: Value, _ b: Value, _ f: (Int64, Int64) -> Int64) throws -> Value {
        guard case .quantity(let x) = a, case .quantity(let y) = b, x.unit.isEmpty, y.unit.isEmpty,
              abs(x.value) < 9.2e18, abs(y.value) < 9.2e18 else { throw CalcError("Bitwise operations need whole numbers") }
        let r = f(Int64(x.value.rounded()), Int64(y.value.rounded()))
        return .quantity(Quantity(Double(r), style: x.style != .decimal ? x.style : y.style))
    }

    func negate(_ v: Value) throws -> Value {
        switch v {
        case .quantity(var q): q.value = -q.value; return .quantity(q)
        case .percent(let p): return .percent(-p)
        case .date: throw CalcError("Can't negate a date")
        }
    }

    // MARK: Dates

    func shift(_ d: DateValue, by q: Quantity, sign: Double) throws -> DateValue {
        guard q.unit.dim == .time || q.unit.isEmpty else { throw CalcError("Can only add durations to dates") }
        var cal = calendar
        cal.timeZone = d.timeZone
        let unit = q.unit.single
        let calendarUnits: [String: (Calendar.Component, Int)] = [
            "day": (.day, 1), "week": (.day, 7), "fortnight": (.day, 14), "month": (.month, 1),
            "year": (.year, 1), "decade": (.year, 10), "century": (.year, 100),
        ]
        if q.unit.isEmpty {
            // Bare numbers added to dates count as days.
            let n = q.value * sign
            if n == n.rounded(), let r = cal.date(byAdding: .day, value: Int(n), to: d.date) {
                return DateValue(date: r, timeZone: d.timeZone, hasTime: d.hasTime)
            }
        }
        if let u = unit, let (comp, mult) = calendarUnits[u.id], q.value == q.value.rounded(),
           let r = cal.date(byAdding: comp, value: Int(q.value * sign) * mult, to: d.date) {
            return DateValue(date: r, timeZone: d.timeZone, hasTime: d.hasTime)
        }
        let seconds = (q.unit.isEmpty ? q.value * 86400 : q.value * factor(q.unit)) * sign
        let wholeDays = (seconds / 86400).rounded() == seconds / 86400
        return DateValue(date: d.date.addingTimeInterval(seconds), timeZone: d.timeZone, hasTime: d.hasTime || !wholeDays)
    }

    func difference(_ a: DateValue, _ b: DateValue) -> Quantity {
        let cat = engine.catalog
        if !a.hasTime && !b.hasTime {
            var cal = calendar; cal.timeZone = a.timeZone
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: b.date), to: cal.startOfDay(for: a.date)).day ?? 0
            return Quantity(Double(days), CompoundUnit(cat.unit("day")!))
        }
        let s = a.date.timeIntervalSince(b.date)
        let id = abs(s) >= 86400 ? "day" : abs(s) >= 3600 ? "h" : abs(s) >= 60 ? "min" : "s"
        let u = cat.unit(id)!
        return Quantity(s / u.factor, CompoundUnit(u))
    }

    func startOfToday(_ tz: TimeZone) -> Date {
        var cal = calendar; cal.timeZone = tz
        return cal.startOfDay(for: now)
    }
}
