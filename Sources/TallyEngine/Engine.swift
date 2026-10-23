import Foundation

public enum LineKind: Sendable { case empty, header, comment, text, value, error }

public enum TokenStyle: Sendable { case number, unit, keyword, variable, function, comment, header, label, date, op }

public struct HighlightSpan: Sendable, Equatable {
    /// UTF-16 offsets within the line.
    public let range: Range<Int>
    public let style: TokenStyle
}

public struct LineResult: Sendable {
    public var kind: LineKind
    public var value: Value?
    public var display: String?
    public var error: String?
    public var spans: [HighlightSpan] = []
    /// Lines using sum/avg are left out of the document total to avoid double counting.
    public var isAggregate = false
}

public final class Engine: @unchecked Sendable {
    public let catalog: UnitCatalog
    let lexicon: Lexicon
    public var rates: CurrencyRates
    public let formatter = ResultFormatter()
    public var timeZone: TimeZone = .current
    public var now: () -> Date = { Date() }
    /// Treat plain numbers in sin/cos/tan as degrees (and return degrees from asin/acos/atan).
    public var anglesInDegrees = false

    public init(rates: CurrencyRates = .fallback) {
        catalog = UnitCatalog()
        for (code, names) in CurrencyNames.words { catalog.addCurrency(code, names: names) }
        lexicon = Lexicon(catalog: catalog)
        self.rates = rates
    }

    // MARK: - Documents

    public func evaluate(_ document: String) -> [LineResult] {
        let scope = Scope(engine: self)
        var results: [LineResult] = []
        for line in document.components(separatedBy: "\n") {
            results.append(evaluateLine(line, scope: scope, previous: results))
        }
        return results
    }

    /// Single expression, evaluated on its own.
    public func evaluate(expression: String) -> LineResult {
        evaluate(expression).last ?? LineResult(kind: .empty)
    }

    /// Sum of every result that can be added to the first one (aggregate lines excluded).
    public func total(_ results: [LineResult]) -> Value? {
        let scope = Scope(engine: self)
        var total: Value?
        for r in results where r.kind == .value && !r.isAggregate {
            guard let v = r.value, case .quantity = v else { continue }
            if let t = total {
                if let s = try? scope.add(t, v, sign: 1) { total = s }
            } else {
                total = v
            }
        }
        return total
    }

    private static let labelRegex = try! NSRegularExpression(pattern: #"^\s*([^:=]*?[\p{L}][^:=]*?):(?!\d)"#)
    private static let nameRegex = try! NSRegularExpression(pattern: #"^[\p{L}_][\p{L}0-9_]*(?: [\p{L}_][\p{L}0-9_]*){0,3}$"#)
    private static let assignRegex = try! NSRegularExpression(pattern: #"^\s*([\p{L}_][\p{L}0-9_]*(?: [\p{L}_][\p{L}0-9_]*){0,3})\s*=(?!=)"#)

    private func evaluateLine(_ line: String, scope: Scope, previous: [LineResult]) -> LineResult {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let full = 0..<line.utf16.count
        if trimmed.isEmpty { return LineResult(kind: .empty) }
        if trimmed.hasPrefix("#") { return LineResult(kind: .header, spans: [HighlightSpan(range: full, style: .header)]) }
        if trimmed.hasPrefix("//") { return LineResult(kind: .comment, spans: [HighlightSpan(range: full, style: .comment)]) }

        var spans: [HighlightSpan] = []
        let ns = line as NSString
        var end = ns.length
        let comment = ns.range(of: "//")
        if comment.location != NSNotFound {
            end = comment.location
            spans.append(HighlightSpan(range: comment.location..<ns.length, style: .comment))
        }
        var start = 0
        var assignTo: String?
        let head = NSRange(location: 0, length: end)
        if let m = Self.assignRegex.firstMatch(in: line, range: head) {
            let name = ns.substring(with: m.range(at: 1))
            assignTo = name
            spans.append(HighlightSpan(range: m.range(at: 1).location..<NSMaxRange(m.range(at: 1)), style: .variable))
            start = NSMaxRange(m.range)
        } else if let m = Self.labelRegex.firstMatch(in: line, range: head) {
            spans.append(HighlightSpan(range: 0..<NSMaxRange(m.range), style: .label))
            start = NSMaxRange(m.range)
            // Labels double as variables ("Flights: 2 × €189" → Flights), unless they'd shadow a built-in word
            // like total/sum/time/hours, which only an explicit `name =` may do.
            let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let whole = NSRange(location: 0, length: (name as NSString).length)
            if Self.nameRegex.firstMatch(in: name, range: whole) != nil, lexicon.meanings(name, rates: rates).isEmpty {
                assignTo = name
            }
        }

        let expr = ns.substring(with: NSRange(location: start, length: end - start))
        let raw = Lexer.tokenize(expr, offset: start)
        let toks = lexicon.resolve(raw, variables: Set(scope.variables.keys), rates: rates)
        spans += toks.map { HighlightSpan(range: $0.range, style: style(of: $0)) }
        if toks.isEmpty { return LineResult(kind: .text, spans: spans) }

        let parser = Parser(toks, scope: scope) { [unowned self] k in
            try self.aggregate(k, previous: previous, scope: scope)
        }
        do {
            let v = scope.settled(try parser.parse())
            if let name = assignTo { scope.variables[name] = v }
            return LineResult(kind: .value, value: v, display: formatter.format(v), spans: spans,
                              isAggregate: parser.usedAggregate)
        } catch {
            // Lines with nothing value-like in them are prose, not mistakes.
            let hasValue = toks.contains { t in
                switch t.kind {
                case .number, .variable, .time, .date: return true
                case .op(let s): return CurrencyNames.symbols[s] != nil
                case .phrase(_, let ms):
                    return ms.contains { if case .keyword = $0 { return false }; return true }
                }
            }
            return LineResult(kind: hasValue ? .error : .text, error: "\(error)", spans: spans)
        }
    }

    private func aggregate(_ k: Keyword, previous: [LineResult], scope: Scope) throws -> Value {
        if k == .prev {
            guard let v = previous.last(where: { $0.value != nil })?.value else { throw CalcError("No previous result") }
            return v
        }
        var block: [Value] = []
        for r in previous.reversed() {
            if r.kind == .empty || r.kind == .header { break }
            if let v = r.value { block.append(v) }
        }
        block.reverse()
        var sum: Value?
        var count = 0
        for v in block {
            if let s = sum {
                if let n = try? scope.add(s, v, sign: 1) { sum = n; count += 1 }
            } else if case .quantity = v {
                sum = v; count = 1
            }
        }
        guard let total = sum else { return .number(0) }
        if k == .avg { return try scope.div(total, .number(Double(count))) }
        return total
    }

    private func style(of t: Tok) -> TokenStyle {
        switch t.kind {
        case .number: return .number
        case .op: return .op
        case .time, .date: return .date
        case .variable: return .variable
        case .phrase(_, let ms):
            switch ms.first {
            case .unit?: return .unit
            case .keyword?: return .keyword
            case .function?: return .function
            case .constant?, .scale?: return .number
            case .timeZone?, .month?, .weekday?: return .date
            case nil: return .keyword
            }
        }
    }
}
