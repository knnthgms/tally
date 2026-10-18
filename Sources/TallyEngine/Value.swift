import Foundation

public enum NumberStyle: Sendable, Equatable { case decimal, hex, binary, octal, scientific }

public struct Quantity: Sendable, Equatable {
    public var value: Double
    public var unit: CompoundUnit
    public var style: NumberStyle

    public init(_ value: Double, _ unit: CompoundUnit = .none, style: NumberStyle = .decimal) {
        self.value = value; self.unit = unit; self.style = style
    }
}

public struct DateValue: Sendable, Equatable {
    public var date: Date
    public var timeZone: TimeZone
    public var hasTime: Bool
}

public enum Value: Sendable, Equatable {
    case quantity(Quantity)
    case percent(Double)
    case date(DateValue)

    public static func number(_ x: Double) -> Value { .quantity(Quantity(x)) }

    /// Plain numeric value, if this is a unitless number.
    public var plainNumber: Double? {
        if case .quantity(let q) = self, q.unit.isEmpty { return q.value }
        return nil
    }
}

public struct CalcError: Error, CustomStringConvertible, Sendable {
    public let description: String
    init(_ s: String) { description = s }
}
