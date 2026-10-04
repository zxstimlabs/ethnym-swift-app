import Foundation

/// Wallet lifecycle: create, import, unlock, reveal. Every operation that touches key material
/// re-derives it from the keystore and password, and drops it when the call returns.
public enum WalletCrypto {
    public enum Failure: LocalizedError, Equatable {
        case emptyName
        case emptyPassword
        case addressMismatch

        public var errorDescription: String? {
            switch self {
            case .emptyName: "Please enter a name"
            case .emptyPassword: "Please enter a password"
            case .addressMismatch: "Wrong password. Please try again."
            }
        }
    }

    /// A new wallet from a freshly generated 12-word phrase.
    @concurrent
    public static func createWallet(name: String, password: String) async throws -> WalletKeystore {
        try await seal(phrase: try HDWallet.generatePhrase(), name: name, password: password, meta: .current)
    }

    /// A wallet from an existing phrase. The phrase is normalized and checksum-validated first.
    @concurrent
    public static func importWallet(name: String, password: String, phrase: String) async throws -> WalletKeystore {
        let normalized = HDWallet.normalize(phrase)
        try HDWallet.validate(normalized)
        return try await seal(phrase: normalized, name: name, password: password, meta: .current)
    }

    /// A standalone backup keystore for any phrase, as the keystore tool produces.
    @concurrent
    public static func backupKeystore(name: String, password: String, phrase: String) async throws -> WalletKeystore {
        let normalized = HDWallet.normalize(phrase)
        try HDWallet.validate(normalized)
        return try await seal(phrase: normalized, name: name, password: password, meta: .secretPhraseBackup)
    }

    /// The secret phrase sealed in any keystore.
    @concurrent
    public static func revealPhrase(_ keystore: KeystoreV3, password: String) async throws -> String {
        let plaintext = try Keystore.decryptSynchronously(keystore, password: password)
        guard let phrase = String(data: plaintext, encoding: .utf8) else { throw Keystore.Failure.corrupt }
        return phrase
    }

    /// Opens a wallet for signing and checks the derived address against the stored one.
    @concurrent
    public static func unlock(_ wallet: WalletKeystore, password: String) async throws -> DerivedAccount {
        let plaintext = try Keystore.decryptSynchronously(wallet.keystore, password: password)
        guard let phrase = String(data: plaintext, encoding: .utf8) else { throw Keystore.Failure.corrupt }
        let account = try HDWallet.account(fromPhrase: phrase)
        guard Address.isSame(account.address, wallet.address) else { throw Failure.addressMismatch }
        return account
    }

    private static func seal(phrase: String, name: String, password: String, meta: WalletKeystore.Meta) async throws -> WalletKeystore {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { throw Failure.emptyName }
        guard !password.isEmpty else { throw Failure.emptyPassword }
        let account = try HDWallet.account(fromPhrase: phrase)
        let keystore = try await Keystore.encrypt(Data(phrase.utf8), password: password)
        return WalletKeystore(keystore: keystore, meta: meta, name: trimmedName, address: account.address)
    }
}
