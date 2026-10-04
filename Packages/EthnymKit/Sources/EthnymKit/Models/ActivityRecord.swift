import BigInt
import Foundation

public enum TxType: String, Codable, Hashable, Sendable, CaseIterable {
    case native
    case erc20
    case erc721
    case raw
}

/// An outgoing transaction, recorded once its receipt arrives.
public struct ActivityRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: Int?
    public var txHash: String
    public var from: String
    public var to: String
    public var chainId: Int
    public var type: TxType
    /// Wei, as a decimal string.
    public var nativeValue: String?
    /// Token base units, as a decimal string.
    public var tokenValue: String?
    public var nftId: String?
    public var tokenAddress: String?
    public var tokenSymbol: String?
    public var tokenDecimals: Int?
    /// Wei per gas at send time, as a decimal string.
    public var gasPrice: String?
    /// The ENS name, when the recipient was entered as one.
    public var ensName: String?
    /// Milliseconds since 1970, like `Date.now()`.
    public var timestamp: Int64

    public init(
        id: Int? = nil,
        txHash: String,
        from: String,
        to: String,
        chainId: Int,
        type: TxType,
        nativeValue: String? = nil,
        tokenValue: String? = nil,
        nftId: String? = nil,
        tokenAddress: String? = nil,
        tokenSymbol: String? = nil,
        tokenDecimals: Int? = nil,
        gasPrice: String? = nil,
        ensName: String? = nil,
        timestamp: Int64
    ) {
        self.id = id
        self.txHash = txHash
        self.from = from
        self.to = to
        self.chainId = chainId
        self.type = type
        self.nativeValue = nativeValue
        self.tokenValue = tokenValue
        self.nftId = nftId
        self.tokenAddress = tokenAddress
        self.tokenSymbol = tokenSymbol
        self.tokenDecimals = tokenDecimals
        self.gasPrice = gasPrice
        self.ensName = ensName
        self.timestamp = timestamp
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }

    /// "0.5 ETH", "12 USDC", "Token ID: 42", or nil for raw transactions.
    public var formattedValue: String? {
        switch type {
        case .native:
            guard let nativeValue, let wei = BigUInt(nativeValue) else { return nil }
            return "\(Units.format(wei, decimals: 18)) ETH"
        case .erc20:
            guard let tokenValue, let amount = BigUInt(tokenValue) else { return nil }
            let formatted = Units.format(amount, decimals: tokenDecimals ?? 18)
            return "\(formatted) \(tokenSymbol ?? "")".trimmed
        case .erc721:
            guard let nftId else { return nil }
            return "Token ID: \(nftId)"
        case .raw:
            return nil
        }
    }
}

/// The parts of an `ActivityRecord` known when a transaction is sent, before its hash.
public struct PendingActivity: Hashable, Sendable {
    public var from: String
    public var to: String
    public var chainId: Int
    public var type: TxType
    public var nativeValue: String?
    public var tokenValue: String?
    public var nftId: String?
    public var tokenAddress: String?
    public var tokenSymbol: String?
    public var tokenDecimals: Int?
    public var gasPrice: String?
    public var ensName: String?

    public init(
        from: String,
        to: String,
        chainId: Int,
        type: TxType,
        nativeValue: String? = nil,
        tokenValue: String? = nil,
        nftId: String? = nil,
        tokenAddress: String? = nil,
        tokenSymbol: String? = nil,
        tokenDecimals: Int? = nil,
        gasPrice: String? = nil,
        ensName: String? = nil
    ) {
        self.from = from
        self.to = to
        self.chainId = chainId
        self.type = type
        self.nativeValue = nativeValue
        self.tokenValue = tokenValue
        self.nftId = nftId
        self.tokenAddress = tokenAddress
        self.tokenSymbol = tokenSymbol
        self.tokenDecimals = tokenDecimals
        self.gasPrice = gasPrice
        self.ensName = ensName
    }

    public func record(txHash: String, timestamp: Int64) -> ActivityRecord {
        ActivityRecord(
            txHash: txHash,
            from: from,
            to: to,
            chainId: chainId,
            type: type,
            nativeValue: nativeValue,
            tokenValue: tokenValue,
            nftId: nftId,
            tokenAddress: tokenAddress,
            tokenSymbol: tokenSymbol,
            tokenDecimals: tokenDecimals,
            gasPrice: gasPrice,
            ensName: ensName,
            timestamp: timestamp
        )
    }
}
