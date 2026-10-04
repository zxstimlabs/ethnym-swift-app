import Foundation
import Observation

/// RPC endpoints and offline mode.
@MainActor
@Observable
public final class SettingsStore {
    public private(set) var settings: WalletSettings
    public private(set) var storageError: String?
    public let chain: Chain

    @ObservationIgnored private let storage: any DataStorage
    static let key = "wallet-settings"

    public init(storage: any DataStorage, chain: Chain = .mainnet) {
        self.storage = storage
        self.chain = chain
        self.settings = storage.decode(WalletSettings.self, for: Self.key) ?? WalletSettings()
    }

    public var offlineMode: Bool {
        get { settings.offlineMode }
        set {
            settings.offlineMode = newValue
            persist()
        }
    }

    public var isUsingCustomRpc: Bool { settings.activeRpc != nil }

    /// The active endpoint, or the chain's default.
    public var rpcURL: URL {
        settings.activeRpc.flatMap { URL(string: $0.url) } ?? chain.defaultRPC
    }

    /// Saves an endpoint. Returns a validation message instead when the URL is unusable.
    public func addRpc(name: String, url: String) -> String? {
        if let error = RpcValidation.validateURL(url) { return error }
        let trimmedName = name.trimmed
        settings.rpcList.append(RpcEntry(name: trimmedName.isEmpty ? nil : trimmedName, url: url.trimmed, chainId: chain.id))
        persist()
        return nil
    }

    public func selectRpc(_ entry: RpcEntry) {
        settings.activeRpc = entry
        persist()
    }

    public func resetRpcToDefault() {
        settings.activeRpc = nil
        persist()
    }

    public func deleteRpc(_ entry: RpcEntry) {
        settings.rpcList.removeAll { $0.id == entry.id }
        if settings.activeRpc?.id == entry.id {
            settings.activeRpc = nil
        }
        persist()
    }

    private func persist() {
        do {
            try storage.encode(settings, for: Self.key)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }
}
