import Foundation

/// Recursive-descent / precedence-climbing parser that evaluates as it parses.
final class Parser {
    private let toks: [Tok]
    private var i = 0
    private let scope: Scope
    private let aggregate: (Keyword) throws -> Value
    private(set) var usedAggregate = false

    init(_ toks: [Tok], scope: Scope, aggregate: @escaping (Keyword) throws -> Value) {
        self.toks = toks; self.scope = scope; self.aggregate = aggregate
    }

    func parse() throws -> Value {
        let v = try expression(0)
        if i < toks.count { throw CalcError("Didn't understand “\(text(toks[i]))”") }
        return v
    }

    // MARK: - Token helpers

    private func kind(_ j: Int) -> Tok.Kind? { j < toks.count ? toks[j].kind : nil }

    private func isOp(_ s: String, _ o: Int = 0) -> Bool {
        if case .op(let x)? = kind(i + o) { return x == s }
        return false
    }

    private func meanings(_ j: Int) -> [Meaning] {
        if case .phrase(_, let m)? = kind(j) { return m }
        return []
    }

    private func keyword(_ j: Int) -> Keyword? {
        for m in meanings(j) { if case .keyword(let k) = m { return k } }
        return nil
    }

    private func kw(_ k: Keyword, _ o: Int = 0) -> Bool { keyword(i + o) == k }

    private func timeZone(_ j: Int) -> TimeZone? {
        for m in meanings(j) { if case .timeZone(let tz) = m { return tz } }
        return nil
    }

    private func scale(_ j: Int) -> Double? {
        for m in meanings(j) { if case .scale(let s) = m { return s } }
        return nil
    }

    private func month(_ j: Int) -> Int? {
        for m in meanings(j) { if case .month(let x) = m { return x } }
        return nil
    }

    private func weekday(_ j: Int) -> Int? {
        for m in meanings(j) { if case .weekday(let x) = m { return x } }
        return nil
    }

    private func currencySymbol(_ j: Int) -> UnitDef? {
        if case .op(let s)? = kind(j), let code = CurrencyNames.symbols[s] {
            scope.engine.catalog.addCurrency(code)
            return scope.engine.catalog.unit(code)
        }
        return nil
    }

    private func number(_ j: Int) -> Double? {
        if case .number(let x, _)? = kind(j) { return x }
        return nil
    }

    private func text(_ t: Tok) -> String {
        switch t.kind {
        case .number(let x, _): return String(x)
        case .op(let s): return s
        case .phrase(let s, _): return s
        case .variable(let s): return s
        case .time: return "time"
        case .date: return "date"
        }
    }

    // MARK: - Binary operators

    private enum Bin { case convert, bitor, bitxor, bitand, shl, shr, add, sub, mul, div, mod, pow, of, on, off, implicitMul }

    private func prec(_ b: Bin) -> Int {
        switch b {
        case .convert: return 1
        case .bitor: return 2
        case .bitxor: return 3
        case .bitand: return 4
        case .shl, .shr: return 5
        case .add, .sub: return 6
        case .mul, .div, .mod, .of, .on, .off, .implicitMul: return 7
        case .pow: return 9
        }
    }

    /// Operator at the cursor and how many tokens it spans.
    private func peekBinary() -> (Bin, Int)? {
        guard let k = kind(i) else { return nil }
        switch k {
        case .op(let s):
            switch s {
            case "+": return (.add, 1)
            case "-": return (.sub, 1)
            case "*": return (.mul, 1)
            case "/": return (.div, 1)
            case "^": return (.pow, 1)
            case "&": return (.bitand, 1)
            case "|": return (.bitor, 1)
            case "<<": return (.shl, 1)
            case ">>": return (.shr, 1)
            case "(": return (.implicitMul, 0)
            default: return nil
            }
        case .variable: return (.implicitMul, 0)
        case .phrase(_, let ms):
            if let k = keyword(i) {
                switch k {
                case .in, .to, .as, .into: if isTarget(i + 1) { return (.convert, 1) }
                case .plus: return (.add, 1)
                case .minus: return (.sub, 1)
                case .times: return (.mul, 1)
                case .divide, .per: return (.div, 1)
                case .mod: return (.mod, 1)
                case .xor: return (.bitxor, 1)
                case .of: return (.of, 1)
                case .on: return (.on, 1)
                case .off: return (.off, 1)
                default: break
                }
            }
            for m in ms {
                switch m {
                case .function, .constant: return (.implicitMul, 0)
                default: continue
                }
            }
            return nil
        default: return nil
        }
    }

    private func isTarget(_ j: Int) -> Bool {
        guard j < toks.count else { return false }
        if case .op(let s) = toks[j].kind { return s == "%" || CurrencyNames.symbols[s] != nil }
        if let k = keyword(j) {
            switch k {
            case .a, .percent, .hex, .bin, .oct, .sci, .dec, .unix: return true
            case .square, .cubic: return unitMeaning(j + 1) != nil
            default: break
            }
        }
        return unitMeaning(j) != nil || timeZone(j) != nil
    }

    private func unitMeaning(_ j: Int) -> (UnitDef, Int)? {
        for m in meanings(j) { if case .unit(let u, let p) = m { return (u, p) } }
        return currencySymbol(j).map { ($0, 1) }
    }

    // MARK: - Expressions

    private func expression(_ minPrec: Int) throws -> Value {
        var lhs = try unary()
        while let (op, n) = peekBinary(), prec(op) >= minPrec {
            i += n
            switch op {
            case .convert:
                lhs = try conversion(lhs)
            case .pow:
                let rhs = try expression(prec(.pow))
                lhs = try power(lhs, rhs)
            case .of, .on, .off:
                lhs = try percentOperation(lhs, op)
            default:
                let rhs = try expression(prec(op) + 1)
                lhs = try apply(op, lhs, rhs)
            }
        }
        return lhs
    }

    private func apply(_ op: Bin, _ a: Value, _ b: Value) throws -> Value {
        switch op {
        case .add: return try scope.add(a, b, sign: 1)
        case .sub: return try scope.add(a, b, sign: -1)
        case .mul, .implicitMul: return try scope.mul(a, b)
        case .div: return try scope.div(a, b)
        case .mod: return try scope.mod(a, b)
        case .bitand: return try scope.integerOp(a, b, &)
        case .bitor: return try scope.integerOp(a, b, |)
        case .bitxor: return try scope.integerOp(a, b, ^)
        case .shl: return try scope.integerOp(a, b) { $0 << $1 }
        case .shr: return try scope.integerOp(a, b) { $0 >> $1 }
        default: throw CalcError("Unsupported operator")
        }
    }

    private func power(_ a: Value, _ b: Value) throws -> Value {
        guard let e = b.plainNumber else { throw CalcError("Exponent must be a plain number") }
        switch a {
        case .quantity(let q): return .quantity(try scope.power(q, e))
        case .percent(let p): return .percent(pow(p / 100, e) * 100)
        case .date: throw CalcError("Can't raise a date to a power")
        }
    }

    private func scaled(_ v: Value, _ k: Double) -> Value {
        switch v {
        case .quantity(var q): q.value *= k; return .quantity(q)
        case .percent(let p): return .percent(p * k)
        case .date: return v
        }
    }

    /// 20% of 10 · 5% on 30 · 6% off 40 · 5% of what is 6
    private func percentOperation(_ lhs: Value, _ op: Bin) throws -> Value {
        guard case .percent(let p) = lhs else { throw CalcError("Expected a percentage before “of”") }
        let f = p / 100
        if kw(.what), kw(.is, 1) {
            i += 2
            let y = try expression(prec(.mul) + 1)
            switch op {
            case .of: return scaled(y, 1 / f)
            case .on: return scaled(y, 1 / (1 + f))
            default: return scaled(y, 1 / (1 - f))
            }
        }
        let y = try expression(prec(.mul) + 1)
        switch op {
        case .of: return scaled(y, f)
        case .on: return scaled(y, 1 + f)
        default: return scaled(y, 1 - f)
        }
    }

    private func unary() throws -> Value {
        if isOp("-") { i += 1; return try scope.negate(try expression(prec(.pow))) }
        if isOp("+") { i += 1; return try expression(prec(.pow)) }
        return try postfix(try primary())
    }

    private func postfix(_ value: Value) throws -> Value {
        var v = value
        while true {
            if isOp("!"), let x = v.plainNumber {
                i += 1; v = .number(factorial(x))
            } else if isOp("%"), case .quantity(let q) = v, q.unit.isEmpty {
                i += 1; v = .percent(q.value)
            } else if kw(.percent), case .quantity(let q) = v, q.unit.isEmpty {
                i += 1; v = .percent(q.value)
            } else if isOp("²") || kw(.squared) {
                i += 1; v = try power(v, .number(2))
            } else if isOp("³") || kw(.cubed) {
                i += 1; v = try power(v, .number(3))
            } else if kw(.ago), case .quantity(let q) = v {
                i += 1; v = .date(try scope.shift(nowValue(), by: q, sign: -1))
            } else if kw(.fromNow), case .quantity(let q) = v {
                i += 1; v = .date(try scope.shift(nowValue(), by: q, sign: 1))
            } else {
                return v
            }
        }
    }

    // MARK: - Primary values

    private func primary() throws -> Value {
        guard let t = kind(i) else { throw CalcError("Expected a value") }
        switch t {
        case .number(let x, _):
            i += 1
            return try numberLiteral(x)
        case .op(let s):
            if s == "(" {
                i += 1
                var v = try expression(0)
                if isOp(")") { i += 1 } else if i < toks.count { throw CalcError("Missing “)”") }
                if case .quantity(var q) = v, q.unit.isEmpty, let u = unitExpression(allowInch: true) {
                    q.unit = u; v = .quantity(q)
                }
                return v
            }
            if let cur = currencySymbol(i) {
                i += 1
                let inner = try primary()
                guard case .quantity(var q) = inner else { throw CalcError("Expected an amount after \(s)") }
                if q.unit.isEmpty { q.unit = CompoundUnit(cur) }
                return .quantity(q)
            }
            throw CalcError("Unexpected “\(s)”")
        case .time(let h, let m, let s):
            i += 1
            return timeLiteral(h, m, s)
        case .date(let y, let m, let d):
            i += 1
            return try dateLiteral(y, m, d)
        case .variable(let name):
            i += 1
            guard let v = scope.variables[name] else { throw CalcError("Unknown variable \(name)") }
            return v
        case .phrase:
            return try phrasePrimary()
        }
    }

    private func numberLiteral(_ x: Double) throws -> Value {
        // 3 pm · 3am
        if kw(.am) || kw(.pm) { return timeLiteral(Int(x), 0, 0) }
        // 12 March [2026]
        if let m = month(i), x == x.rounded(), (1...31).contains(x) {
            i += 1
            var year: Int?
            if let y = number(i), y >= 1000, y == y.rounded() { year = Int(y); i += 1 }
            return try calendarDate(year, m, Int(x))
        }
        var value = x
        while let s = scale(i), unitMeaning(i) == nil || isScaleWord(i) { value *= s; i += 1 }
        var q = Quantity(value)
        if let u = unitExpression(allowInch: true) {
            q.unit = u
            // Juxtaposed quantities of the same kind add up: 5 feet 3 inches, 1 hour 30 min.
            while let y = number(i) {
                let save = i
                i += 1
                if let u2 = unitExpression(allowInch: true), u2.dim == q.unit.dim {
                    let part = try scope.convert(Quantity(y, u2), to: q.unit)
                    q.value += part.value
                } else {
                    i = save; break
                }
            }
        }
        return .quantity(q)
    }

    private func isScaleWord(_ j: Int) -> Bool {
        // "M" (million) and "k" are scales; unit meanings win elsewhere.
        if case .phrase(let s, _)? = kind(j) { return s == "M" || s == "k" }
        return false
    }

    private func phrasePrimary() throws -> Value {
        let ms = meanings(i)
        if let k = keyword(i) {
            switch k {
            case .prev, .sum, .avg:
                i += 1
                if k != .prev { usedAggregate = true }
                return try aggregate(k)
            case .now, .time:
                i += 1
                return .date(nowValue())
            case .today, .tomorrow, .yesterday:
                i += 1
                let start = scope.startOfToday(scope.engine.timeZone)
                let delta = k == .today ? 0 : k == .tomorrow ? 1 : -1
                let d = scope.calendar.date(byAdding: .day, value: delta, to: start) ?? start
                return .date(DateValue(date: d, timeZone: scope.engine.timeZone, hasTime: false))
            case .next, .last, .this:
                i += 1
                if let wd = weekday(i) { i += 1; return .date(weekdayDate(wd, k)) }
                if let (u, _) = unitMeaning(i), u.isTime {
                    i += 1
                    let today = DateValue(date: scope.startOfToday(scope.engine.timeZone),
                                          timeZone: scope.engine.timeZone, hasTime: false)
                    return .date(try scope.shift(today, by: Quantity(k == .last ? -1 : k == .next ? 1 : 0, CompoundUnit(u)), sign: 1))
                }
                throw CalcError("Expected a weekday after “\(k.rawValue)”")
            case .root:
                i += 1
                let n = try primary()
                let x = try primary()
                guard let deg = n.plainNumber, case .quantity(let q) = x else { throw CalcError("root needs a degree and a value") }
                return .quantity(try scope.power(q, 1 / deg))
            default:
                break
            }
        }
        for m in ms {
            switch m {
            case .function(let f):
                i += 1
                return try call(f)
            case .constant(let c):
                i += 1
                return .number(c)
            case .month(let mo):
                if let d = number(i + 1), d == d.rounded() {
                    i += 2
                    var year: Int?
                    if isOp(","), let y = number(i + 1), y >= 1000 { i += 2; year = Int(y) }
                    else if let y = number(i), y >= 1000, y == y.rounded() { i += 1; year = Int(y) }
                    return try calendarDate(year, mo, Int(d))
                }
            case .weekday(let wd):
                i += 1
                // "Saturday, 17 October" — the weekday is decoration on an explicit date.
                if isOp(",") && (month(i + 1) != nil || number(i + 1) != nil) { i += 1 }
                if month(i) != nil || (number(i) != nil && month(i + 1) != nil) { return try primary() }
                if case .date? = kind(i) { return try primary() }
                return .date(weekdayDate(wd, .this))
            default:
                continue
            }
        }
        if unitMeaning(i) != nil, let u = unitExpression(allowInch: false) {
            return .quantity(Quantity(1, u))
        }
        if let tz = timeZone(i) {
            i += 1
            if kw(.time) { i += 1 }
            var d = nowValue(); d.timeZone = tz
            return .date(d)
        }
        if let s = scale(i) { i += 1; return .number(s) }
        if case .phrase(let s, _)? = kind(i) { throw CalcError("Unexpected “\(s)”") }
        throw CalcError("Expected a value")
    }

    // MARK: - Units

    /// km · km/h · m² · square feet · cubic cm · m^3 · $
    private func unitExpression(allowInch: Bool) -> CompoundUnit? {
        guard var cu = unitFactor(allowInch: allowInch) else { return nil }
        while true {
            let save = i
            if isOp("/") || kw(.per) {
                i += 1
                if let f = unitFactor(allowInch: allowInch) {
                    cu = CompoundUnit(cu.terms + f.raised(-1).terms)
                    continue
                }
                i = save
            }
            break
        }
        return cu
    }

    private func unitFactor(allowInch: Bool) -> CompoundUnit? {
        let save = i
        var power = 1
        if kw(.square) { power = 2; i += 1 } else if kw(.cubic) { power = 3; i += 1 }
        var found: (UnitDef, Int)?
        if let m = unitMeaning(i) {
            found = m
        } else if allowInch, power == 1, kw(.in), !isTarget(i + 1) {
            found = (scope.engine.catalog.unit("in")!, 1)
        }
        guard let (u, p) = found else { i = save; return nil }
        i += 1
        power *= p
        if isOp("²") || kw(.squared) { power *= 2; i += 1 }
        else if isOp("³") || kw(.cubed) { power *= 3; i += 1 }
        else if isOp("^"), let e = number(i + 1), e == e.rounded(), abs(e) <= 4 { power *= Int(e); i += 2 }
        return CompoundUnit(u, power)
    }

    // MARK: - Conversions

    private func conversion(_ v: Value) throws -> Value {
        if kw(.a) { i += 1 }
        if isOp("%") || kw(.percent) {
            i += 1
            if let k = keyword(i), k == .of || k == .on || k == .off {
                i += 1
                let y = try expression(prec(.convert) + 1)
                let ratio = try self.ratio(v, y)
                switch k {
                case .of: return .percent(ratio * 100)
                case .on: return .percent((ratio - 1) * 100)
                default: return .percent((1 - ratio) * 100)
                }
            }
            if case .percent = v { return v }
            guard let x = v.plainNumber else { throw CalcError("Can't express that as a percentage") }
            return .percent(x * 100)
        }
        if let k = keyword(i) {
            let styles: [Keyword: NumberStyle] = [.hex: .hex, .bin: .binary, .oct: .octal, .sci: .scientific, .dec: .decimal]
            if let style = styles[k] {
                i += 1
                switch v {
                case .quantity(var q): q.style = style; return .quantity(q)
                case .percent(let p): return .quantity(Quantity(p, style: style))
                case .date: throw CalcError("Can't show a date in \(k.rawValue)")
                }
            }
            if k == .unix {
                i += 1
                guard case .date(let d) = v else { throw CalcError("Only dates convert to unix time") }
                return .number(d.date.timeIntervalSince1970.rounded())
            }
        }
        if case .date(var d) = v {
            if let tz = timeZone(i) {
                i += 1
                if kw(.time) { i += 1 }
                d.timeZone = tz
                d.hasTime = true
                return .date(d)
            }
        }
        guard let target = unitExpression(allowInch: false) else {
            if let tz = timeZone(i) { _ = tz; throw CalcError("Only times convert to a time zone") }
            throw CalcError("Unknown unit")
        }
        switch v {
        case .quantity(let q): return .quantity(try scope.convert(q, to: target))
        case .percent(let p): return .quantity(Quantity(p / 100, target))
        case .date: throw CalcError("Can't convert a date to \(scope.engine.formatter.unitText(target, 2))")
        }
    }

    private func ratio(_ a: Value, _ b: Value) throws -> Double {
        guard case .quantity(let x) = a, case .quantity(let y) = b else { throw CalcError("Expected two amounts") }
        if x.unit.isEmpty || y.unit.isEmpty { return x.value / y.value }
        return x.value / (try scope.convert(y, to: x.unit)).value
    }

    // MARK: - Functions

    private func call(_ f: MathFunction) throws -> Value {
        var args: [Value] = []
        if (f == .log) && !isOp("("), let base = number(i), isOp("(", 1) {
            // log 2 (8)
            i += 1
            let x = try primary()
            guard let v = x.plainNumber else { throw CalcError("log needs a number") }
            return .number(Foundation.log(v) / Foundation.log(base))
        }
        if isOp("(") {
            i += 1
            if !isOp(")") {
                args.append(try expression(0))
                while isOp(";") || isOp(",") { i += 1; args.append(try expression(0)) }
            }
            if isOp(")") { i += 1 } else if i < toks.count { throw CalcError("Missing “)”") }
        } else {
            args.append(try expression(prec(.pow)))
        }
        guard let first = args.first else { throw CalcError("\(f.rawValue) needs a value") }

        func quantity(_ v: Value) throws -> Quantity {
            switch v {
            case .quantity(let q): return q
            case .percent(let p): return Quantity(p / 100)
            case .date: throw CalcError("\(f.rawValue) needs a number")
            }
        }
        let q = try quantity(first)

        func radians() throws -> Double {
            if q.unit.dim == .angle { return try scope.convert(q, to: CompoundUnit(scope.engine.catalog.unit("rad")!)).value }
            guard q.unit.isEmpty else { throw CalcError("\(f.rawValue) needs an angle") }
            return scope.engine.anglesInDegrees ? q.value * .pi / 180 : q.value
        }
        func plain() throws -> Double {
            guard q.unit.isEmpty else { throw CalcError("\(f.rawValue) needs a plain number") }
            return q.value
        }
        func keep(_ x: Double) -> Value { .quantity(Quantity(x, q.unit, style: q.style)) }

        switch f {
        case .sqrt: return .quantity(try scope.power(q, 0.5))
        case .cbrt: return .quantity(try scope.power(q, 1.0 / 3))
        case .abs: return keep(Swift.abs(q.value))
        case .round:
            let places = args.count > 1 ? (args[1].plainNumber ?? 0) : 0
            let m = pow(10, places)
            return keep((q.value * m).rounded() / m)
        case .ceil: return keep(Foundation.ceil(q.value))
        case .floor: return keep(Foundation.floor(q.value))
        case .trunc: return keep(q.value.rounded(.towardZero))
        case .log:
            if args.count > 1, let b = args[1].plainNumber { return .number(Foundation.log(try plain()) / Foundation.log(b)) }
            return .number(log10(try plain()))
        case .ln: return .number(Foundation.log(try plain()))
        case .exp: return .number(Foundation.exp(try plain()))
        case .fact: return .number(factorial(try plain()))
        case .sin: return .number(Foundation.sin(try radians()))
        case .cos: return .number(Foundation.cos(try radians()))
        case .tan: return .number(Foundation.tan(try radians()))
        case .asin: return .number(angleOut(Foundation.asin(try plain())))
        case .acos: return .number(angleOut(Foundation.acos(try plain())))
        case .atan: return .number(angleOut(Foundation.atan(try plain())))
        case .sinh: return .number(Foundation.sinh(try plain()))
        case .cosh: return .number(Foundation.cosh(try plain()))
        case .tanh: return .number(Foundation.tanh(try plain()))
        case .fromunix:
            var seconds = try plain()
            if seconds > 1e11 { seconds /= 1000 } // milliseconds
            return .date(DateValue(date: Date(timeIntervalSince1970: seconds), timeZone: scope.engine.timeZone, hasTime: true))
        }
    }

    private func angleOut(_ radians: Double) -> Double {
        scope.engine.anglesInDegrees ? radians * 180 / .pi : radians
    }

    private func factorial(_ x: Double) -> Double {
        if x == x.rounded(), x >= 0, x <= 170 { return (0..<Int(x)).reduce(1.0) { $0 * Double($1 + 1) } }
        return tgamma(x + 1)
    }

    // MARK: - Dates & times

    private func nowValue() -> DateValue {
        DateValue(date: scope.now, timeZone: scope.engine.timeZone, hasTime: true)
    }

    private func timeLiteral(_ h: Int, _ m: Int, _ s: Int) -> Value {
        var hour = h
        if kw(.am) { i += 1; if hour == 12 { hour = 0 } }
        else if kw(.pm) { i += 1; if hour < 12 { hour += 12 } }
        var tz = scope.engine.timeZone
        if let z = timeZone(i) { tz = z; i += 1 }
        var cal = scope.calendar
        cal.timeZone = tz
        var comps = cal.dateComponents([.year, .month, .day], from: scope.now)
        comps.hour = hour; comps.minute = m; comps.second = s
        let date = cal.date(from: comps) ?? scope.now
        return .date(DateValue(date: date, timeZone: tz, hasTime: true))
    }

    private func calendarDate(_ year: Int?, _ month: Int, _ day: Int) throws -> Value {
        var cal = scope.calendar
        cal.timeZone = scope.engine.timeZone
        let y = year ?? cal.component(.year, from: scope.now)
        guard let d = cal.date(from: DateComponents(year: y, month: month, day: day)) else { throw CalcError("Invalid date") }
        var value = DateValue(date: d, timeZone: scope.engine.timeZone, hasTime: false)
        if case .time(let h, let m, let s)? = kind(i) {
            i += 1
            if case .date(let t) = timeLiteral(h, m, s) {
                let tc = cal.dateComponents([.hour, .minute, .second], from: t.date)
                value.date = cal.date(bySettingHour: tc.hour ?? 0, minute: tc.minute ?? 0, second: tc.second ?? 0, of: d) ?? d
                value.hasTime = true
            }
        }
        return .date(value)
    }

    private func dateLiteral(_ y: Int, _ m: Int, _ d: Int) throws -> Value {
        try calendarDate(y, m, d)
    }

    private func weekdayDate(_ wd: Int, _ mode: Keyword) -> DateValue {
        let tz = scope.engine.timeZone
        let today = scope.startOfToday(tz)
        let current = scope.calendar.component(.weekday, from: today)
        var delta = (wd - current + 7) % 7
        switch mode {
        case .next: if delta == 0 { delta = 7 }
        case .last:
            delta = -((current - wd + 7) % 7)
            if delta == 0 { delta = -7 }
        default: break
        }
        let d = scope.calendar.date(byAdding: .day, value: delta, to: today) ?? today
        return DateValue(date: d, timeZone: tz, hasTime: false)
    }
}
