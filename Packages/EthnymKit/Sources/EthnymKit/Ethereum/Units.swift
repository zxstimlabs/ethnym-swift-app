import BigInt
import Foundation

/// Decimal conversion for token amounts, with viem's `formatUnits` / `parseUnits` semantics.
public enum Units {
    public static let etherDecimals = 18
    public static let gweiDecimals = 9

    public enum ParseError: LocalizedError, Equatable {
        case invalidFormat

        public var errorDescription: String? { "Invalid amount format" }
    }

    /// `1500000000000000000` with 18 decimals is "1.5". Trailing zeros are dropped.
    public static func format(_ value: BigUInt, decimals: Int) -> String {
        var digits = String(value)
        if digits.count < decimals {
            digits = String(repeating: "0", count: decimals - digits.count) + digits
        }
        let integer = String(digits.dropLast(decimals))
        var fraction = String(digits.suffix(decimals))
        while fraction.hasSuffix("0") { fraction.removeLast() }
        let whole = integer.isEmpty ? "0" : integer
        return fraction.isEmpty ? whole : "\(whole).\(fraction)"
    }

    /// Like `format`, but keeps at most `maxFractionDigits` decimals, truncating rather than rounding
    /// so a balance is never overstated. Tiny non-zero amounts show as "<0.000001".
    public static func format(_ value: BigUInt, decimals: Int, maxFractionDigits: Int) -> String {
        let full = format(value, decimals: decimals)
        guard let dot = full.firstIndex(of: ".") else { return full }
        let integer = full[..<dot]
        var fraction = String(full[full.index(after: dot)...].prefix(maxFractionDigits))
        while fraction.hasSuffix("0") { fraction.removeLast() }
        if fraction.isEmpty {
            return integer == "0" && value > 0 ? "<0." + String(repeating: "0", count: max(maxFractionDigits - 1, 0)) + "1" : String(integer)
        }
        return "\(integer).\(fraction)"
    }

    /// "1.5" with 18 decimals is `1500000000000000000`. Digits past `decimals` round half up, as in viem.
    public static func parse(_ text: String, decimals: Int) throws(ParseError) -> BigUInt {
        let trimmed = text.trimmed
        let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard !trimmed.isEmpty, parts.count <= 2 else { throw .invalidFormat }
        let integer = String(parts[0])
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        guard !(integer.isEmpty && fraction.isEmpty),
              integer.allSatisfy(\.isASCIIDigit),
              fraction.allSatisfy(\.isASCIIDigit)
        else { throw .invalidFormat }

        var roundUp = false
        if fraction.count > decimals {
            let next = fraction[fraction.index(fraction.startIndex, offsetBy: decimals)]
            roundUp = next >= "5"
            fraction = String(fraction.prefix(decimals))
        } else {
            fraction += String(repeating: "0", count: decimals - fraction.count)
        }
        guard var value = BigUInt((integer.isEmpty ? "0" : integer) + fraction) else { throw .invalidFormat }
        if roundUp { value += 1 }
        return value
    }

    public static func formatEther(_ wei: BigUInt) -> String { format(wei, decimals: etherDecimals) }
    public static func parseEther(_ text: String) throws(ParseError) -> BigUInt { try parse(text, decimals: etherDecimals) }
    public static func formatGwei(_ wei: BigUInt) -> String { format(wei, decimals: gweiDecimals) }
    public static func parseGwei(_ text: String) throws(ParseError) -> BigUInt { try parse(text, decimals: gweiDecimals) }

    /// A JSON-RPC quantity: "0x"-prefixed hex, or a decimal string.
    public static func quantity(_ text: String) -> BigUInt? {
        let trimmed = text.trimmed
        if trimmed.lowercased().hasPrefix("0x") {
            let hex = trimmed.dropFirst(2)
            return hex.isEmpty ? 0 : BigUInt(String(hex), radix: 16)
        }
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCIIDigit) else { return nil }
        return BigUInt(trimmed)
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
