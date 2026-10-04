import Foundation

/// An encrypted full-device backup: wallets, contacts, settings and activity.
///
/// The file is self-describing and identical to the web wallet's `um-wallet-backup`, so either app
/// can read the other's backups. To decrypt with any tool: PBKDF2-SHA256 the password with
/// `kdfSalt` and `kdfIterations` into a 256-bit key, then AES-GCM-decrypt `data` with `iv`.
public struct WalletBackup: Codable, Hashable, Sendable {
    public static let formatIdentifier = "um-wallet-backup"
    public static let currentVersion = 1

    public struct Encryption: Codable, Hashable, Sendable {
        public var kdf: String
        public var kdfHash: String
        public var kdfIterations: Int
        public var kdfSalt: String
        public var algorithm: String
        public var iv: String
    }

    /// The decrypted contents.
    public struct Payload: Codable, Hashable, Sendable {
        public var wallets: [WalletKeystore]
        public var activeWalletAddress: String?
        public var contacts: [Contact]
        public var settings: WalletSettings
        public var activity: [ActivityRecord]

        public init(wallets: [WalletKeystore], activeWalletAddress: String?, contacts: [Contact], settings: WalletSettings, activity: [ActivityRecord]) {
            self.wallets = wallets
            self.activeWalletAddress = activeWalletAddress
            self.contacts = contacts
            self.settings = settings
            self.activity = activity
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(wallets, forKey: .wallets)
            try container.encode(activeWalletAddress, forKey: .activeWalletAddress)
            try container.encode(contacts, forKey: .contacts)
            try container.encode(settings, forKey: .settings)
            try container.encode(activity, forKey: .activity)
        }
    }

    public enum Failure: LocalizedError, Equatable {
        case notABackup
        case unsupported

        public var errorDescription: String? {
            switch self {
            case .notABackup: "This file isn't an ETHnym backup."
            case .unsupported: "This backup uses an unsupported format version or cipher."
            }
        }
    }

    public var format: String
    public var version: Int
    /// ISO 8601 with milliseconds, like JavaScript's `toISOString()`.
    public var createdAt: String
    public var email: String?
    public var encryption: Encryption
    public var data: String

    public var sealed: BackupCrypto.Sealed {
        BackupCrypto.Sealed(kdfSalt: encryption.kdfSalt, iv: encryption.iv, data: data)
    }

    public static func make(_ payload: Payload, password: String, createdAt: Date = .now) async throws -> WalletBackup {
        let plaintext = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        let sealed = try await BackupCrypto.encrypt(plaintext, password: password)
        return WalletBackup(
            format: formatIdentifier,
            version: currentVersion,
            createdAt: createdAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)),
            email: nil,
            encryption: Encryption(
                kdf: "PBKDF2",
                kdfHash: "SHA-256",
                kdfIterations: BackupCrypto.kdfIterations,
                kdfSalt: sealed.kdfSalt,
                algorithm: "AES-GCM-256",
                iv: sealed.iv
            ),
            data: sealed.data
        )
    }

    public static func parse(_ data: Data) throws -> WalletBackup {
        guard let backup = try? JSONDecoder().decode(WalletBackup.self, from: data), backup.format == formatIdentifier else {
            throw Failure.notABackup
        }
        guard backup.version == currentVersion,
              backup.encryption.kdf == "PBKDF2",
              backup.encryption.kdfHash == "SHA-256",
              backup.encryption.algorithm == "AES-GCM-256"
        else { throw Failure.unsupported }
        return backup
    }

    /// Decrypts and decodes the payload.
    public func decrypt(password: String) async throws -> Payload {
        try open(try await BackupCrypto.decrypt(sealed, password: password, iterations: encryption.kdfIterations))
    }

    func open(_ plaintext: String) throws -> Payload {
        try JSONDecoder().decode(Payload.self, from: Data(plaintext.utf8))
    }

    public func exportedJSON() throws -> Data {
        try JSONEncoder.pretty.encode(self)
    }

    public static func suggestedFilename(on date: Date = .now) -> String {
        "ethnym-backup-\(date.formatted(.iso8601.year().month().day())).json"
    }
}
