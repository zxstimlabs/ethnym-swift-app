import CryptoKit
import Foundation
import libsecp256k1
import MnemonicSwift
import web3

/// An account derived from a secret phrase. Holds the private key only for as long as the value lives.
public struct DerivedAccount: Sendable {
    public let privateKey: Data
    /// EIP-55 checksummed.
    public let address: String
}

/// BIP-39 secret phrases and BIP-32/44 key derivation.
///
/// Phrase generation and checksum validation come from MnemonicSwift. Child keys are derived with
/// libsecp256k1's scalar tweak (the library web3.swift signs with) and CryptoKit's HMAC-SHA512.
public enum HDWallet {
    /// The first account on Ethereum's BIP-44 path, which viem's `mnemonicToAccount` uses.
    public static let ethereumPath = "m/44'/60'/0'/0/0"

    public enum Failure: LocalizedError, Equatable {
        case invalidPhrase(String)
        case invalidPath
        case invalidKey

        public var errorDescription: String? {
            switch self {
            case let .invalidPhrase(reason): reason
            case .invalidPath: "Invalid derivation path."
            case .invalidKey: "Key derivation produced an invalid key."
            }
        }
    }

    /// A fresh 12-word English phrase from 128 bits of system randomness.
    public static func generatePhrase() throws -> String {
        try Mnemonic.generateMnemonic(strength: 128)
    }

    /// Lowercases and collapses whitespace, so pasted phrases with stray spaces or newlines still work.
    public static func normalize(_ phrase: String) -> String {
        phrase.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Checks word count, words and checksum. Pass a normalized phrase.
    public static func validate(_ phrase: String) throws(Failure) {
        do {
            try Mnemonic.validate(mnemonic: phrase)
        } catch let error as MnemonicError {
            switch error {
            case .wrongWordCount: throw .invalidPhrase("A secret phrase has 12, 15, 18, 21 or 24 words.")
            case let .invalidWord(word): throw .invalidPhrase("“\(word)” isn't a secret phrase word.")
            case .checksumError: throw .invalidPhrase("The secret phrase checksum doesn't match. Check the words and their order.")
            default: throw .invalidPhrase("Invalid secret phrase.")
            }
        } catch {
            throw .invalidPhrase("Invalid secret phrase.")
        }
    }

    /// Derives the account for a phrase exactly as viem does: NFKD, no checksum check, so phrases
    /// stored by the web wallet always open to the address recorded with them.
    public static func account(fromPhrase phrase: String, path: String = ethereumPath) throws -> DerivedAccount {
        let normalized = phrase.decomposedStringWithCompatibilityMapping
        let wordCount = normalized.split(separator: " ", omittingEmptySubsequences: false).count
        guard [12, 15, 18, 21, 24].contains(wordCount) else {
            throw Failure.invalidPhrase("A secret phrase has 12, 15, 18, 21 or 24 words.")
        }
        let seed = try CommonCryptoPrimitives.pbkdf2(
            password: Data(normalized.utf8),
            salt: Data("mnemonic".decomposedStringWithCompatibilityMapping.utf8),
            iterations: 2048,
            keyLength: 64,
            prf: .sha512
        )
        let privateKey = try derivePrivateKey(seed: seed, path: path)
        return DerivedAccount(privateKey: privateKey, address: try address(forPrivateKey: privateKey))
    }

    public static func address(forPrivateKey privateKey: Data) throws -> String {
        let publicKey = try KeyUtil.generatePublicKey(from: privateKey)
        return KeyUtil.generateAddress(from: publicKey).toChecksumAddress()
    }

    // MARK: - BIP-32

    static func derivePrivateKey(seed: Data, path: String) throws -> Data {
        let master = Data(HMAC<SHA512>.authenticationCode(for: seed, using: SymmetricKey(data: Data("Bitcoin seed".utf8))))
        var key = master.prefix(32)
        var chainCode = master.suffix(32)
        guard isValidPrivateKey(key) else { throw Failure.invalidKey }

        for index in try parse(path) {
            var data = Data()
            if index >= hardenedOffset {
                data.append(0)
                data.append(key)
            } else {
                data.append(try compressedPublicKey(for: key))
            }
            withUnsafeBytes(of: index.bigEndian) { data.append(contentsOf: $0) }

            let digest = Data(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: chainCode)))
            key = try addScalar(digest.prefix(32), to: key)
            chainCode = digest.suffix(32)
        }
        return Data(key)
    }

    private static let hardenedOffset: UInt32 = 0x8000_0000

    static func parse(_ path: String) throws -> [UInt32] {
        let components = path.split(separator: "/")
        guard components.first == "m" else { throw Failure.invalidPath }
        return try components.dropFirst().map { component in
            let hardened = component.hasSuffix("'") || component.hasSuffix("h")
            guard let value = UInt32(hardened ? component.dropLast() : component), value < hardenedOffset else {
                throw Failure.invalidPath
            }
            return hardened ? value + hardenedOffset : value
        }
    }

    private static func withContext<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_NONE)) else { throw Failure.invalidKey }
        defer { secp256k1_context_destroy(context) }
        return try body(context)
    }

    private static func isValidPrivateKey(_ key: Data) -> Bool {
        (try? withContext { context in
            Data(key).withUnsafeBytes { secp256k1_ec_seckey_verify(context, $0.bindMemory(to: UInt8.self).baseAddress!) == 1 }
        }) ?? false
    }

    /// `(key + tweak) mod n`. libsecp256k1 rejects a tweak ≥ n or a zero result, the cases BIP-32 skips.
    private static func addScalar(_ tweak: Data, to key: Data) throws -> Data {
        try withContext { context in
            var result = [UInt8](key)
            let tweakBytes = [UInt8](tweak)
            guard secp256k1_ec_seckey_tweak_add(context, &result, tweakBytes) == 1 else { throw Failure.invalidKey }
            return Data(result)
        }
    }

    private static func compressedPublicKey(for key: Data) throws -> Data {
        try withContext { context in
            var publicKey = secp256k1_pubkey()
            let keyBytes = [UInt8](key)
            guard secp256k1_ec_pubkey_create(context, &publicKey, keyBytes) == 1 else { throw Failure.invalidKey }
            var output = [UInt8](repeating: 0, count: 33)
            var length = output.count
            secp256k1_ec_pubkey_serialize(context, &output, &length, &publicKey, UInt32(SECP256K1_EC_COMPRESSED))
            return Data(output.prefix(length))
        }
    }
}
