import Foundation
import web3

/// Web3 Secret Storage v3 sealing of arbitrary bytes: PBKDF2-HMAC-SHA256 for the key,
/// AES-128-CTR for the cipher and a Keccak-256 MAC. Byte-compatible with `ox`'s `Keystore`.
public enum Keystore {
    /// `ox`'s default PBKDF2 iteration count.
    public static let defaultIterations = 262_144

    public enum Failure: LocalizedError, Equatable {
        case unsupportedKDF(String)
        case unsupportedCipher(String)
        case corrupt
        case wrongPassword

        public var errorDescription: String? {
            switch self {
            case let .unsupportedKDF(kdf): "Unsupported keystore key derivation: \(kdf)"
            case let .unsupportedCipher(cipher): "Unsupported keystore cipher: \(cipher)"
            case .corrupt: "The keystore is damaged and can't be read."
            case .wrongPassword: "Wrong password. Please try again."
            }
        }
    }

    /// Seals `plaintext`. Runs off the main actor; PBKDF2 is deliberately slow.
    @concurrent
    public static func encrypt(_ plaintext: Data, password: String, iterations: Int = defaultIterations) async throws -> KeystoreV3 {
        let salt = CommonCryptoPrimitives.randomBytes(32)
        let iv = CommonCryptoPrimitives.randomBytes(16)
        return try encrypt(plaintext, password: password, salt: salt, iv: iv, iterations: iterations, id: UUID().uuidString.lowercased())
    }

    static func encrypt(_ plaintext: Data, password: String, salt: Data, iv: Data, iterations: Int, id: String) throws -> KeystoreV3 {
        let derived = try CommonCryptoPrimitives.pbkdf2(password: password, salt: salt, iterations: iterations, keyLength: 32, prf: .sha256)
        let ciphertext = try CommonCryptoPrimitives.aesCTR(plaintext, key: derived.prefix(16), iv: iv)
        let mac = (derived.suffix(16) + ciphertext).web3.keccak256

        return KeystoreV3(
            crypto: .init(
                cipher: "aes-128-ctr",
                ciphertext: ciphertext.hexString.dropHexPrefix,
                cipherparams: .init(iv: iv.hexString.dropHexPrefix),
                kdf: "pbkdf2",
                kdfparams: .init(c: iterations, dklen: 32, prf: "hmac-sha256", salt: salt.hexString.dropHexPrefix),
                mac: mac.hexString.dropHexPrefix
            ),
            id: id
        )
    }

    /// Opens a keystore. A MAC mismatch means the password is wrong.
    @concurrent
    public static func decrypt(_ keystore: KeystoreV3, password: String) async throws -> Data {
        try decryptSynchronously(keystore, password: password)
    }

    static func decryptSynchronously(_ keystore: KeystoreV3, password: String) throws -> Data {
        let crypto = keystore.crypto
        guard crypto.kdf == "pbkdf2" else { throw Failure.unsupportedKDF(crypto.kdf) }
        guard crypto.cipher == "aes-128-ctr" else { throw Failure.unsupportedCipher(crypto.cipher) }

        let prf: CommonCryptoPrimitives.PRF
        switch crypto.kdfparams.prf ?? "hmac-sha256" {
        case "hmac-sha256": prf = .sha256
        case "hmac-sha512": prf = .sha512
        case let other: throw Failure.unsupportedKDF("pbkdf2 with \(other)")
        }

        guard let iterations = crypto.kdfparams.c, iterations > 0,
              crypto.kdfparams.dklen >= 32,
              let salt = Data(hexString: crypto.kdfparams.salt),
              let iv = Data(hexString: crypto.cipherparams.iv),
              let ciphertext = Data(hexString: crypto.ciphertext),
              let mac = Data(hexString: crypto.mac)
        else { throw Failure.corrupt }

        let derived = try CommonCryptoPrimitives.pbkdf2(password: password, salt: salt, iterations: iterations, keyLength: crypto.kdfparams.dklen, prf: prf)
        let expected = (derived[16 ..< 32] + ciphertext).web3.keccak256
        guard constantTimeEquals(expected, mac) else { throw Failure.wrongPassword }
        return try CommonCryptoPrimitives.aesCTR(ciphertext, key: derived.prefix(16), iv: iv)
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

extension String {
    var dropHexPrefix: String { hasPrefix("0x") ? String(dropFirst(2)) : self }
}
