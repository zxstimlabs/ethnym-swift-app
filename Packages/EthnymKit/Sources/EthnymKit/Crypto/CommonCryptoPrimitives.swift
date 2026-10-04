import CommonCrypto
import Foundation
import Security

/// Thin wrappers over Apple's CommonCrypto and Security frameworks. No primitive is implemented here.
enum CommonCryptoPrimitives {
    enum Failure: Error {
        case status(Int32)
    }

    enum PRF {
        case sha256
        case sha512

        var algorithm: CCPseudoRandomAlgorithm {
            switch self {
            case .sha256: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
            case .sha512: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
            }
        }
    }

    /// PBKDF2 over the password's UTF-8 bytes, matching WebCrypto and noble-hashes.
    static func pbkdf2(password: String, salt: Data, iterations: Int, keyLength: Int, prf: PRF) throws -> Data {
        try pbkdf2(password: Data(password.utf8), salt: salt, iterations: iterations, keyLength: keyLength, prf: prf)
    }

    static func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int, prf: PRF) throws -> Data {
        var derived = Data(count: keyLength)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                        passwordBytes.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        saltBytes.count,
                        prf.algorithm,
                        UInt32(iterations),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.status(status) }
        return derived
    }

    /// AES in CTR mode with a big-endian counter. Encryption and decryption are the same operation.
    static func aesCTR(_ input: Data, key: Data, iv: Data) throws -> Data {
        var cryptor: CCCryptorRef?
        let created = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivBytes.baseAddress,
                    keyBytes.baseAddress,
                    keyBytes.count,
                    nil,
                    0,
                    0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
            }
        }
        guard created == kCCSuccess, let cryptor else { throw Failure.status(created) }
        defer { CCCryptorRelease(cryptor) }

        var output = Data(count: input.count)
        var moved = 0
        let updated = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                CCCryptorUpdate(cryptor, inputBytes.baseAddress, inputBytes.count, outputBytes.baseAddress, outputBytes.count, &moved)
            }
        }
        guard updated == kCCSuccess else { throw Failure.status(updated) }
        return output.prefix(moved)
    }

    /// Bytes from the system CSPRNG.
    static func randomBytes(_ count: Int) -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "The system random number generator failed.")
        return bytes
    }
}
