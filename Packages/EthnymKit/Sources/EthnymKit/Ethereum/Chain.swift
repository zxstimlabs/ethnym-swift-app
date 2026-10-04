import Foundation

public struct Chain: Hashable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let nativeCurrency: NativeCurrency
    public let explorer: URL
    /// Used when no custom RPC is active.
    public let defaultRPC: URL

    public struct NativeCurrency: Hashable, Sendable {
        public let name: String
        public let symbol: String
        public let decimals: Int
    }

    public static let mainnet = Chain(
        id: 1,
        name: "Ethereum",
        nativeCurrency: .init(name: "Ether", symbol: "ETH", decimals: 18),
        explorer: URL(string: "https://etherscan.io")!,
        defaultRPC: URL(string: "https://ethereum-rpc.publicnode.com")!
    )

    public func transactionURL(_ hash: String) -> URL {
        explorer.appending(path: "tx/\(hash)")
    }

    public func addressURL(_ address: String) -> URL {
        explorer.appending(path: "address/\(address)")
    }
}
