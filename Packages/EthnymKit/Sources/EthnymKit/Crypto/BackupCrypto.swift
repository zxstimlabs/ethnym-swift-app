import CryptoKit
import Foundation

/// Password encryption for full-device backups: PBKDF2-SHA256 (600,000 iterations) into an
/// AES-GCM-256 key, via CommonCrypto and CryptoKit. Matches the web wallet's `lib/crypto.ts`.
public enum BackupCrypto {
    public static let kdfIterations = 600_000

    public struct Sealed: Codable, Hashable, Sendable {
        /// Base64, 16 bytes.
        public var kdfSalt: String
        /// Base64, 12 bytes.
        public var iv: String
        /// Base64 ciphertext followed by the 16-byte GCM tag, as WebCrypto lays it out.
        public var data: String
    }

    @concurrent
    public static func encrypt(_ plaintext: String, password: String) async throws -> Sealed {
        let salt = CommonCryptoPrimitives.randomBytes(16)
        let iv = CommonCryptoPrimitives.randomBytes(12)
        let key = try deriveKey(password: password, salt: salt, iterations: kdfIterations)
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: key, nonce: AES.GCM.Nonce(data: iv))
        return Sealed(
            kdfSalt: salt.base64EncodedString(),
            iv: iv.base64EncodedString(),
            data: (box.ciphertext + box.tag).base64EncodedString()
        )
    }

    /// Throws when the password is wrong or the data was tampered with; GCM authenticates both.
    @concurrent
    public static func decrypt(_ sealed: Sealed, password: String, iterations: Int = kdfIterations) async throws -> String {
        guard let salt = Data(base64Encoded: sealed.kdfSalt),
              let iv = Data(base64Encoded: sealed.iv),
              let combined = Data(base64Encoded: sealed.data),
              combined.count >= 16
        else { throw Keystore.Failure.corrupt }

        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: combined.dropLast(16), tag: combined.suffix(16))
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw Keystore.Failure.wrongPassword
        }
        guard let text = String(data: plaintext, encoding: .utf8) else { throw Keystore.Failure.corrupt }
        return text
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        SymmetricKey(data: try CommonCryptoPrimitives.pbkdf2(password: password, salt: salt, iterations: iterations, keyLength: 32, prf: .sha256))
    }
}
