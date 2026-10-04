import BigInt
import Foundation

/// What to send. Unset fields are filled from the network, or must be set when signing offline.
public struct TransactionRequest: Hashable, Sendable {
    public var chainId: Int
    public var to: String
    public var value: BigUInt
    public var data: Data
    public var nonce: Int?
    public var gasLimit: BigUInt?
    public var maxFeePerGas: BigUInt?
    public var maxPriorityFeePerGas: BigUInt?

    public init(
        chainId: Int = Chain.mainnet.id,
        to: String,
        value: BigUInt = 0,
        data: Data = Data(),
        nonce: Int? = nil,
        gasLimit: BigUInt? = nil,
        maxFeePerGas: BigUInt? = nil,
        maxPriorityFeePerGas: BigUInt? = nil
    ) {
        self.chainId = chainId
        self.to = to
        self.value = value
        self.data = data
        self.nonce = nonce
        self.gasLimit = gasLimit
        self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
    }

    /// From pasted transaction JSON. Always sent as EIP-1559, like the web wallet.
    public init(_ prepared: PreparedTransaction) {
        self.init(
            chainId: prepared.chainId,
            to: prepared.to,
            value: prepared.valueAmount ?? 0,
            data: prepared.callData,
            nonce: prepared.nonce,
            gasLimit: prepared.gasAmount,
            maxFeePerGas: prepared.maxFeeAmount,
            maxPriorityFeePerGas: prepared.maxPriorityFeeAmount
        )
    }
}

public enum TransactionSender {
    public enum Failure: LocalizedError, Equatable {
        case offline
        case unsupportedChain(Int)
        case missingOfflineFields([String])

        public var errorDescription: String? {
            switch self {
            case .offline:
                "Offline mode is on. Turn it off in Settings to broadcast, or sign the transaction JSON offline."
            case let .unsupportedChain(id):
                "This wallet broadcasts on Ethereum (chain 1) only, not chain \(id). Turn on offline mode to sign it without broadcasting."
            case let .missingOfflineFields(fields):
                "Signing offline needs every field filled in. Missing: \(fields.joined(separator: ", "))."
            }
        }
    }

    /// Fills nonce, gas and fees from the network.
    ///
    /// The fee cap defaults to 120% of the network gas price; the tip is the node's suggestion,
    /// never above the cap. Contract calls get 10% headroom over the gas estimate.
    public static func prepare(_ request: TransactionRequest, from sender: String, service: EthereumService) async throws -> EIP1559Transaction {
        guard request.chainId == service.chain.id else { throw Failure.unsupportedChain(request.chainId) }

        async let nonce: Int = if let nonce = request.nonce { nonce } else { try await service.nonce(for: sender) }
        async let maxFee: BigUInt = if let fee = request.maxFeePerGas { fee } else { try await service.gasPrice() * 12 / 10 }
        async let tip: BigUInt = if let tip = request.maxPriorityFeePerGas { tip } else { await service.maxPriorityFeePerGas() }
        async let gasLimit: BigUInt = if let gas = request.gasLimit {
            gas
        } else {
            try await withHeadroom(service.estimateGas(from: sender, to: request.to, value: request.value, data: request.data))
        }

        let cap = try await maxFee
        return try await EIP1559Transaction(
            chainId: request.chainId,
            nonce: nonce,
            maxPriorityFeePerGas: min(tip, cap),
            maxFeePerGas: cap,
            gasLimit: gasLimit,
            to: request.to,
            value: request.value,
            data: request.data
        )
    }

    private static func withHeadroom(_ estimate: BigUInt) -> BigUInt {
        estimate > 21_000 ? estimate * 11 / 10 : estimate
    }

    /// Builds the transaction without the network. Every field must be set.
    public static func prepareOffline(_ request: TransactionRequest) throws -> EIP1559Transaction {
        var missing: [String] = []
        if request.nonce == nil { missing.append("nonce") }
        if request.gasLimit == nil { missing.append("gas") }
        if request.maxFeePerGas == nil { missing.append("maxFeePerGas") }
        if request.maxPriorityFeePerGas == nil { missing.append("maxPriorityFeePerGas") }
        guard missing.isEmpty, let nonce = request.nonce, let gas = request.gasLimit, let maxFee = request.maxFeePerGas, let tip = request.maxPriorityFeePerGas else {
            throw Failure.missingOfflineFields(missing)
        }
        return EIP1559Transaction(
            chainId: request.chainId,
            nonce: nonce,
            maxPriorityFeePerGas: min(tip, maxFee),
            maxFeePerGas: maxFee,
            gasLimit: gas,
            to: request.to,
            value: request.value,
            data: request.data
        )
    }
}
