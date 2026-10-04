import BigInt
import Foundation
import web3

/// A type-2 (EIP-1559) transaction. Serialized with web3.swift's RLP encoder and signed with its
/// secp256k1 signer. web3.swift itself only builds legacy transactions.
public struct EIP1559Transaction: Hashable, Sendable {
    public var chainId: Int
    public var nonce: Int
    public var maxPriorityFeePerGas: BigUInt
    public var maxFeePerGas: BigUInt
    public var gasLimit: BigUInt
    public var to: String
    public var value: BigUInt
    public var data: Data

    public init(chainId: Int, nonce: Int, maxPriorityFeePerGas: BigUInt, maxFeePerGas: BigUInt, gasLimit: BigUInt, to: String, value: BigUInt, data: Data = Data()) {
        self.chainId = chainId
        self.nonce = nonce
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.maxFeePerGas = maxFeePerGas
        self.gasLimit = gasLimit
        self.to = to
        self.value = value
        self.data = data
    }

    public enum Failure: LocalizedError {
        case invalidRecipient
        case encoding
        case signing

        public var errorDescription: String? {
            switch self {
            case .invalidRecipient: "The recipient isn't a valid address."
            case .encoding: "The transaction couldn't be encoded."
            case .signing: "The transaction couldn't be signed."
            }
        }
    }

    public struct Signed: Hashable, Sendable {
        /// `0x02 || rlp([...fields, yParity, r, s])`, ready for `eth_sendRawTransaction`.
        public let raw: Data
        public let hash: String

        public var rawHex: String { raw.hexString }
    }

    private static let typePrefix: UInt8 = 0x02

    private func fields() throws -> [Any] {
        guard Address.isValid(to), let recipient = Data(hexString: to) else { throw Failure.invalidRecipient }
        let accessList: [Any] = []
        return [chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, recipient, value, data, accessList]
    }

    /// The bytes whose Keccak-256 hash gets signed.
    public func signingPayload() throws -> Data {
        guard let encoded = RLP.encode(try fields()) else { throw Failure.encoding }
        return Data([Self.typePrefix]) + encoded
    }

    public func signed(with privateKey: Data) throws -> Signed {
        let payload = try signingPayload()
        let signature: Data
        do {
            signature = try KeyUtil.sign(message: payload, with: privateKey, hashing: true)
        } catch {
            throw Failure.signing
        }
        guard signature.count == 65 else { throw Failure.signing }

        // r and s are integers in RLP, so they must lose any leading zero bytes.
        let r = BigUInt(signature[0 ..< 32])
        let s = BigUInt(signature[32 ..< 64])
        let yParity = Int(signature[64])
        guard let encoded = RLP.encode(try fields() + [yParity, r, s]) else { throw Failure.encoding }

        let raw = Data([Self.typePrefix]) + encoded
        return Signed(raw: raw, hash: raw.web3.keccak256.hexString)
    }
}
