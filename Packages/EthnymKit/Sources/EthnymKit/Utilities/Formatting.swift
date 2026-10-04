import Foundation

public enum Formatting {
    /// `0x1234...5678`. Prefer full, chunked addresses; this is for tight single-line spots.
    public static func truncateAddress(_ address: String?) -> String {
        guard let address, !address.isEmpty else { return "" }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    /// `0xabcd...90ab`.
    public static func truncateHash(_ hash: String?) -> String {
        truncateAddress(hash)
    }

    public static func chainName(_ chainId: Int) -> String? {
        switch chainId {
        case 1: "Ethereum"
        case 137: "Polygon"
        case 8453: "Base"
        default: nil
        }
    }

    /// The chain name, or "Chain 42161" when it's not one we know.
    public static func chainLabel(_ chainId: Int) -> String {
        chainName(chainId) ?? "Chain \(chainId)"
    }
}

public enum QRCodeParser {
    /// Pulls an address out of scanned QR data. Handles a plain address, ERC-3770 (`eth:0x…`),
    /// CAIP-10 (`eip155:1:0x…`) and EIP-681 (`ethereum:0x…@1/transfer?…`).
    public static func address(from raw: String) -> String? {
        var candidate = raw.trimmed
        if let last = candidate.split(separator: ":", omittingEmptySubsequences: false).last, candidate.contains(":") {
            candidate = String(last)
        }
        for separator in ["@", "/", "?"] {
            candidate = String(candidate.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        }
        return candidate.wholeMatch(of: /0x[0-9a-fA-F]{40}/) != nil ? candidate : nil
    }
}
