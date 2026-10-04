import BigInt
import CoreFoundation
import Foundation

/// A transaction request pasted as JSON, such as wagmi's `prepareTransactionRequest` output.
/// Quantities are hex (or decimal) strings, `chainId` and `nonce` are numbers.
public struct PreparedTransaction: Hashable, Sendable {
    public var to: String
    public var chainId: Int
    public var value: String?
    public var account: String?
    public var from: String?
    public var type: String?
    public var gas: String?
    public var nonce: Int?
    public var maxFeePerGas: String?
    public var maxPriorityFeePerGas: String?
    public var data: String?

    public init(
        to: String,
        chainId: Int,
        value: String? = nil,
        account: String? = nil,
        from: String? = nil,
        type: String? = nil,
        gas: String? = nil,
        nonce: Int? = nil,
        maxFeePerGas: String? = nil,
        maxPriorityFeePerGas: String? = nil,
        data: String? = nil
    ) {
        self.to = to
        self.chainId = chainId
        self.value = value
        self.account = account
        self.from = from
        self.type = type
        self.gas = gas
        self.nonce = nonce
        self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.data = data
    }

    public enum ValidationError: LocalizedError, Equatable {
        case empty
        case invalidJSON
        case missingTo
        case invalidChainId
        case invalidQuantity(String)
        case invalidData

        public var errorDescription: String? {
            switch self {
            case .empty: "Please enter the transaction JSON"
            case .invalidJSON: "Invalid JSON format"
            case .missingTo: "Missing 'to' address"
            case .invalidChainId: "Missing or invalid 'chainId' (must be a number)"
            case let .invalidQuantity(field): "Invalid '\(field)' (must be a hex or decimal number)"
            case .invalidData: "Invalid 'data' (must be 0x-prefixed hex)"
            }
        }
    }

    /// Parses and checks pasted JSON. Mirrors the web wallet's `validateTransaction`.
    public static func validate(_ text: String) -> Result<PreparedTransaction, ValidationError> {
        if text.isEmpty { return .failure(.empty) }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              !(json is NSNull)
        else { return .failure(.invalidJSON) }

        let object = json as? [String: Any] ?? [:]
        guard let to = object["to"] as? String else { return .failure(.missingTo) }
        guard let chainId = integer(object["chainId"]) else { return .failure(.invalidChainId) }

        let transaction = PreparedTransaction(
            to: to,
            chainId: chainId,
            value: object["value"] as? String,
            account: object["account"] as? String,
            from: object["from"] as? String,
            type: object["type"] as? String,
            gas: object["gas"] as? String,
            nonce: integer(object["nonce"]) ?? (object["nonce"] as? String).flatMap { Units.quantity($0) }.flatMap { Int(exactly: $0) },
            maxFeePerGas: object["maxFeePerGas"] as? String,
            maxPriorityFeePerGas: object["maxPriorityFeePerGas"] as? String,
            data: object["data"] as? String
        )

        for (field, value) in [("value", transaction.value), ("gas", transaction.gas), ("maxFeePerGas", transaction.maxFeePerGas), ("maxPriorityFeePerGas", transaction.maxPriorityFeePerGas)] {
            if let value, Units.quantity(value) == nil { return .failure(.invalidQuantity(field)) }
        }
        if let hex = transaction.data, Data(hexString: hex) == nil { return .failure(.invalidData) }
        return .success(transaction)
    }

    /// A JSON number that is an integer. Booleans are rejected, which `NSNumber` would otherwise allow.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, let int = Int(exactly: double) else { return nil }
        return int
    }

    public var valueAmount: BigUInt? { value.flatMap(Units.quantity) }
    public var gasAmount: BigUInt? { gas.flatMap(Units.quantity) }
    public var maxFeeAmount: BigUInt? { maxFeePerGas.flatMap(Units.quantity) }
    public var maxPriorityFeeAmount: BigUInt? { maxPriorityFeePerGas.flatMap(Units.quantity) }
    public var callData: Data { data.flatMap { Data(hexString: $0) } ?? Data() }
}
