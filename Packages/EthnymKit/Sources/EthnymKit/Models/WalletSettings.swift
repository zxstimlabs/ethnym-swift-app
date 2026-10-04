import Foundation

/// A user-defined RPC endpoint.
public struct RpcEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Optional label, such as "Alchemy Mainnet".
    public var name: String?
    public var url: String
    public var chainId: Int

    public init(id: String = UUID().uuidString.lowercased(), name: String?, url: String, chainId: Int = Chain.mainnet.id) {
        self.id = id
        self.name = name
        self.url = url
        self.chainId = chainId
    }
}

/// Network settings, in the same JSON shape the web wallet keeps under `wallet-settings`.
public struct WalletSettings: Codable, Hashable, Sendable {
    public var rpcList: [RpcEntry]
    /// The active endpoint, or nil to use the built-in default.
    public var activeRpc: RpcEntry?
    /// Suppresses every network request. Transactions can still be signed and broadcast elsewhere.
    public var offlineMode: Bool

    public init(rpcList: [RpcEntry] = [], activeRpc: RpcEntry? = nil, offlineMode: Bool = false) {
        self.rpcList = rpcList
        self.activeRpc = activeRpc
        self.offlineMode = offlineMode
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rpcList, forKey: .rpcList)
        try container.encode(activeRpc, forKey: .activeRpc)
        try container.encode(offlineMode, forKey: .offlineMode)
    }
}

public enum RpcValidation {
    /// Returns an error message, or nil when the URL is a usable http(s) endpoint.
    public static func validateURL(_ value: String) -> String? {
        let trimmed = value.trimmed
        if trimmed.isEmpty { return "RPC URL is required" }
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased() else {
            return "Invalid URL"
        }
        guard let host = components.host, !host.isEmpty else { return "Invalid URL" }
        guard scheme == "http" || scheme == "https" else { return "RPC URL must use http or https" }
        return nil
    }
}
