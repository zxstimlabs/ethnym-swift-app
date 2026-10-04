import Foundation

/// A Web3 Secret Storage (v3) keystore, field for field as `ox` writes it.
///
/// The encrypted payload is whatever bytes were sealed. ETHnym seals the UTF-8 secret phrase, not a
/// private key, which is why this type exists instead of reusing a private-key keystore.
public struct KeystoreV3: Codable, Hashable, Sendable {
    public struct Crypto: Codable, Hashable, Sendable {
        public var cipher: String
        public var ciphertext: String
        public var cipherparams: CipherParams
        public var kdf: String
        public var kdfparams: KDFParams
        public var mac: String

        public init(cipher: String, ciphertext: String, cipherparams: CipherParams, kdf: String, kdfparams: KDFParams, mac: String) {
            self.cipher = cipher
            self.ciphertext = ciphertext
            self.cipherparams = cipherparams
            self.kdf = kdf
            self.kdfparams = kdfparams
            self.mac = mac
        }
    }

    public struct CipherParams: Codable, Hashable, Sendable {
        public var iv: String

        public init(iv: String) {
            self.iv = iv
        }
    }

    /// PBKDF2 fills `c`, `prf`; scrypt fills `n`, `r`, `p`. Both share `dklen` and `salt`.
    public struct KDFParams: Codable, Hashable, Sendable {
        public var c: Int?
        public var dklen: Int
        public var prf: String?
        public var salt: String
        public var n: Int?
        public var r: Int?
        public var p: Int?

        public init(c: Int? = nil, dklen: Int, prf: String? = nil, salt: String, n: Int? = nil, r: Int? = nil, p: Int? = nil) {
            self.c = c
            self.dklen = dklen
            self.prf = prf
            self.salt = salt
            self.n = n
            self.r = r
            self.p = p
        }
    }

    public var crypto: Crypto
    public var id: String
    public var version: Int

    public init(crypto: Crypto, id: String, version: Int = 3) {
        self.crypto = crypto
        self.id = id
        self.version = version
    }
}

/// A stored wallet: a v3 keystore of the secret phrase plus the metadata the web wallet adds
/// (`UmKeystore`). The JSON shape is identical, so keystore files move freely between the two.
public struct WalletKeystore: Codable, Hashable, Sendable, Identifiable {
    public struct Meta: Codable, Hashable, Sendable {
        public var type: String
        public var note: String
        public var umVersion: String?

        public init(type: String, note: String, umVersion: String?) {
            self.type = type
            self.note = note
            self.umVersion = umVersion
        }

        public static let current = Meta(
            type: WalletKeystore.currentMetaType,
            note: WalletKeystore.metaNote,
            umVersion: WalletKeystore.currentUmVersion
        )

        /// The metadata the keystore tool writes for a standalone backup.
        public static let secretPhraseBackup = Meta(type: "secret-phrase", note: WalletKeystore.metaNote, umVersion: nil)
    }

    public static let currentUmVersion = "0.0.1"
    public static let currentMetaType = "password-keystore-seedphrase"
    static let metaNote = "the 12 words secret phrase (aka mnemonic phrase) is encrypted with the password using the keystore encryption process"

    public var crypto: KeystoreV3.Crypto
    public var id: String
    public var version: Int
    public var meta: Meta
    public var name: String
    public var address: String

    public init(keystore: KeystoreV3, meta: Meta, name: String, address: String) {
        self.crypto = keystore.crypto
        self.id = keystore.id
        self.version = keystore.version
        self.meta = meta
        self.name = name
        self.address = address
    }

    public var keystore: KeystoreV3 {
        KeystoreV3(crypto: crypto, id: id, version: version)
    }

    /// Wallets are unique by keystore id and address, the same pair the web wallet deletes by.
    public func isSameWallet(as other: WalletKeystore) -> Bool {
        id == other.id && address.lowercased() == other.address.lowercased()
    }

    /// Pretty-printed JSON for keystore files.
    public func exportedJSON() throws -> Data {
        try JSONEncoder.pretty.encode(self)
    }

    /// Parses a keystore file or pasted contents: one wallet object or an array of them.
    public static func parse(_ data: Data) throws -> [WalletKeystore] {
        let decoder = JSONDecoder()
        if let wallets = try? decoder.decode([WalletKeystore].self, from: data) {
            return wallets
        }
        do {
            return [try decoder.decode(WalletKeystore.self, from: data)]
        } catch {
            throw KeystoreImportError.invalidFormat
        }
    }
}

public enum KeystoreImportError: LocalizedError, Equatable {
    case invalidFormat

    public var errorDescription: String? {
        "Not a wallet keystore. Expected a JSON object with crypto, id, version, name and address."
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
