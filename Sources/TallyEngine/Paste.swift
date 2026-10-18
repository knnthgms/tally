import Foundation

extension Engine {
    /// Removes results that Numi or Tally appended when copying ("debt = coral + regalia = INR 84,568.87"),
    /// keeping real assignments like "rent = 49500" intact.
    ///
    /// A trailing "= …" is only dropped when the text to its left evaluates, in the document so far,
    /// to the number on the right. `context` is the document text above the paste point.
    public func stripPastedResults(_ pasted: String, context: String = "") -> String {
        var doc = context.isEmpty ? [] : context.components(separatedBy: "\n")
        var out: [String] = []
        for line in pasted.components(separatedBy: "\n") {
            let kept = strippedLine(line, above: doc)
            out.append(kept)
            doc.append(kept)
        }
        return out.joined(separator: "\n")
    }

    private static let bareAssignment = try! NSRegularExpression(
        pattern: #"^\s*[\p{L}_][\p{L}0-9_]*(?: [\p{L}_][\p{L}0-9_]*){0,3}\s*$"#)

    private func strippedLine(_ line: String, above: [String]) -> String {
        guard let eq = line.range(of: "=", options: .backwards) else { return line }
        let left = String(line[..<eq.lowerBound]).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        let right = line[eq.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !right.isEmpty, !left.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
        // "rent = 49500" is an assignment, not a result: nothing to the left of "=" can be evaluated.
        let ns = left as NSString
        if Self.bareAssignment.firstMatch(in: left, range: NSRange(location: 0, length: ns.length)) != nil { return line }

        guard let value = evaluate((above + [left]).joined(separator: "\n")).last?.value,
              matches(value, right) else { return line }
        return left
    }

    private func matches(_ value: Value, _ text: String) -> Bool {
        let expected: Double
        switch value {
        case .date: return text.rangeOfCharacter(from: .alphanumerics) != nil
        case .percent(let p): expected = p
        case .quantity(let q): expected = q.value
        }
        guard let (shown, decimals) = Self.number(in: text) else { return false }
        let tolerance = 0.5 * pow(10, -Double(decimals)) + 1e-9 * Swift.abs(expected)
        return Swift.abs(shown - expected) <= tolerance
    }

    /// First number in a formatted result ("INR 1,20,599.21", "-$5", "0xFF", "1.2e4 m") and its decimal places.
    static func number(in text: String) -> (Double, Int)? {
        let t = text.replacingOccurrences(of: ",", with: "")
        if let m = t.range(of: #"-?0[xbo][0-9A-Fa-f]+"#, options: .regularExpression) {
            var s = String(t[m]); let neg = s.hasPrefix("-"); if neg { s.removeFirst() }
            let radix = s.dropFirst().first == "x" ? 16 : s.dropFirst().first == "b" ? 2 : 8
            guard let v = Int(s.dropFirst(2), radix: radix) else { return nil }
            return (Double(neg ? -v : v), 0)
        }
        guard let m = t.range(of: #"\d*\.?\d+(?:e-?\d+)?"#, options: .regularExpression),
              let v = Double(t[m]) else { return nil }
        // A minus sign anywhere before the digits ("-$5", "- 5") makes it negative.
        let negative = t[..<m.lowerBound].contains("-") || t[..<m.lowerBound].contains("−")
        let digits = String(t[m])
        let decimals = digits.contains("e") ? 12 : (digits.split(separator: ".").dropFirst().first?.count ?? 0)
        return (negative ? -v : v, decimals)
    }
}
