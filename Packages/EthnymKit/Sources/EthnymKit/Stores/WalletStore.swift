import Foundation
import Observation

/// The encrypted wallets and which one is active.
@MainActor
@Observable
public final class WalletStore {
    public private(set) var wallets: [WalletKeystore]
    public private(set) var activeWalletID: String?
    /// The last persistence failure, if any.
    public private(set) var storageError: String?

    @ObservationIgnored private let storage: any DataStorage
    @ObservationIgnored private let preferences: any DataStorage

    static let walletsKey = "wallets"
    static let activeWalletKey = "active-wallet"

    /// - Parameters:
    ///   - storage: Where keystores live; the Keychain in the app.
    ///   - preferences: Where the active wallet id lives.
    public init(storage: any DataStorage, preferences: any DataStorage) {
        self.storage = storage
        self.preferences = preferences
        self.wallets = storage.decode([WalletKeystore].self, for: Self.walletsKey) ?? []
        let activeID = preferences.decode(String.self, for: Self.activeWalletKey)
        self.activeWalletID = wallets.contains { $0.id == activeID } ? activeID : nil
    }

    public var activeWallet: WalletKeystore? {
        wallets.first { $0.id == activeWalletID }
    }

    public func select(_ id: WalletKeystore.ID?) {
        activeWalletID = id
        persistActive()
    }

    /// Adds a wallet. Returns false, and changes nothing, if it's already here.
    @discardableResult
    public func add(_ wallet: WalletKeystore) -> Bool {
        add(contentsOf: [wallet]).added == 1
    }

    /// Adds wallets, skipping any already stored. Selects the first new one if none is active.
    @discardableResult
    public func add(contentsOf newWallets: [WalletKeystore]) -> (added: Int, skipped: Int) {
        var added: [WalletKeystore] = []
        for wallet in newWallets where !(wallets + added).contains(where: { $0.isSameWallet(as: wallet) }) {
            added.append(wallet)
        }
        guard !added.isEmpty else { return (0, newWallets.count) }
        wallets += added
        persistWallets()
        if activeWallet == nil {
            select(added[0].id)
        }
        return (added.count, newWallets.count - added.count)
    }

    public func delete(_ wallet: WalletKeystore) {
        wallets.removeAll { $0.isSameWallet(as: wallet) }
        persistWallets()
        if activeWalletID == wallet.id {
            select(nil)
        }
    }

    // MARK: - Storage format migration

    /// Wallets written by an older web wallet version, missing `umVersion` or with an old type.
    public var walletsNeedingMigration: [WalletKeystore] {
        wallets.filter(Self.needsMigration)
    }

    public static func needsMigration(_ wallet: WalletKeystore) -> Bool {
        wallet.meta.umVersion != WalletKeystore.currentUmVersion || wallet.meta.type != WalletKeystore.currentMetaType
    }

    /// Updates metadata only. Keys and ciphertext are untouched.
    public func migrateAll() {
        wallets = wallets.map { wallet in
            guard Self.needsMigration(wallet) else { return wallet }
            var migrated = wallet
            migrated.meta.type = WalletKeystore.currentMetaType
            migrated.meta.umVersion = WalletKeystore.currentUmVersion
            return migrated
        }
        persistWallets()
    }

    // MARK: - Persistence

    private func persistWallets() {
        do {
            try storage.encode(wallets, for: Self.walletsKey)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func persistActive() {
        do {
            if let activeWalletID {
                try preferences.encode(activeWalletID, for: Self.activeWalletKey)
            } else {
                try preferences.remove(Self.activeWalletKey)
            }
        } catch {
            storageError = error.localizedDescription
        }
    }
}
