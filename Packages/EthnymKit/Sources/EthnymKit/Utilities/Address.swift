import Foundation
import web3

/// Ethereum address helpers. Checksumming is web3.swift's EIP-55 implementation.
public enum Address {
    /// `0x` followed by 40 hex digits. Mixed case must also carry a valid EIP-55 checksum.
    public static func isValid(_ value: String) -> Bool {
        guard value.wholeMatch(of: /0x[0-9a-fA-F]{40}/) != nil else { return false }
        let body = value.dropFirst(2)
        let isSingleCase = body == body.lowercased() || body == body.uppercased()
        return isSingleCase || checksummed(value) == value
    }

    /// The EIP-55 checksummed form.
    public static func checksummed(_ value: String) -> String {
        EthereumAddress(value.lowercased()).toChecksumAddress()
    }

    public static func isSame(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lowercased() == rhs.lowercased()
    }

    /// Splits an address into groups of four after the prefix, so a full address reads in chunks:
    /// `0x f39F d6e5 1aad …`.
    public static func chunks(_ value: String, size: Int = 4) -> [String] {
        guard value.hasPrefix("0x") else { return [value] }
        let body = Array(value.dropFirst(2))
        let groups = stride(from: 0, to: body.count, by: size).map { String(body[$0 ..< min($0 + size, body.count)]) }
        return ["0x"] + groups
    }
}

public extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// `0x` and 40 hex digits, checksum not considered.
    var isHexAddress: Bool { wholeMatch(of: /0x[0-9a-fA-F]{40}/) != nil }

    /// Anything ending in `.eth` with a non-empty label, which is what the forms treat as ENS.
    var isENSName: Bool {
        let value = trimmed.lowercased()
        return value.hasSuffix(".eth") && value.count > 4 && !value.hasPrefix(".")
    }
}

public extension Data {
    /// Parses hex with or without a `0x` prefix. An odd digit count is left-padded.
    init?(hexString: String) {
        var hex = hexString.trimmed
        if hex.lowercased().hasPrefix("0x") { hex.removeFirst(2) }
        if hex.count % 2 == 1 { hex = "0" + hex }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    /// Lowercase hex with a `0x` prefix.
    var hexString: String {
        "0x" + map { String(format: "%02x", $0) }.joined()
    }
}
