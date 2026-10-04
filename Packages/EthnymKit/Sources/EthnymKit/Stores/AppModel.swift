import Foundation
import Observation

/// Everything the app holds, wired together.
@MainActor
@Observable
public final class AppModel {
    public let wallets: WalletStore
    public let contacts: ContactStore
    public let settings: SettingsStore
    public let assets: AssetStore
    public let activity: ActivityStore
    public let balances: BalancesModel
    public let transactions: TransactionMonitor

    @ObservationIgnored private var cachedService: EthereumService?

    public init(
        wallets: WalletStore,
        contacts: ContactStore,
        settings: SettingsStore,
        assets: AssetStore,
        activity: ActivityStore
    ) {
        self.wallets = wallets
        self.contacts = contacts
        self.settings = settings
        self.assets = assets
        self.activity = activity
        self.balances = BalancesModel()
        self.transactions = TransactionMonitor(activity: activity)
    }

    /// Keystores in the Keychain, everything else in Application Support.
    public static func live() -> AppModel {
        let files = FileStorage.applicationSupport
        return AppModel(
            wallets: WalletStore(storage: KeychainStorage(service: "com.ethnym.wallets"), preferences: files),
            contacts: ContactStore(storage: files),
            settings: SettingsStore(storage: files),
            assets: AssetStore(storage: files),
            activity: ActivityStore(storage: files)
        )
    }

    /// Nothing persisted; for previews and tests.
    public static func inMemory(wallets: [WalletKeystore] = [], contacts: [Contact] = [], activity: [ActivityRecord] = [], settings: WalletSettings = WalletSettings()) -> AppModel {
        let storage = InMemoryStorage()
        try? storage.encode(wallets, for: WalletStore.walletsKey)
        try? storage.encode(contacts, for: ContactStore.key)
        try? storage.encode(activity, for: ActivityStore.key)
        try? storage.encode(settings, for: SettingsStore.key)
        if let first = wallets.first { try? storage.encode(first.id, for: WalletStore.activeWalletKey) }
        return AppModel(
            wallets: WalletStore(storage: storage, preferences: storage),
            contacts: ContactStore(storage: storage),
            settings: SettingsStore(storage: storage),
            assets: AssetStore(storage: storage),
            activity: ActivityStore(storage: storage)
        )
    }

    public var chain: Chain { settings.chain }

    /// The RPC client, or nil in offline mode. Rebuilt only when the endpoint changes.
    public var service: EthereumService? {
        guard !settings.offlineMode else { return nil }
        let url = settings.rpcURL
        if let cachedService, cachedService.rpcURL == url { return cachedService }
        let service = EthereumService(rpcURL: url, chain: chain)
        cachedService = service
        return service
    }

    /// Identifies what balances depend on, for `task(id:)`.
    public var balanceContext: String {
        [wallets.activeWallet?.address ?? "-", settings.rpcURL.absoluteString, String(settings.offlineMode)].joined(separator: "|")
    }

    /// Reloads balances for the active wallet, or clears them when there's nothing to load.
    public func refreshBalances() async {
        guard let address = wallets.activeWallet?.address, let service else {
            balances.reset(address: wallets.activeWallet?.address)
            return
        }
        await balances.refreshAll(address: address, service: service, tokens: assets.tokens, collections: assets.collections)
    }
}
