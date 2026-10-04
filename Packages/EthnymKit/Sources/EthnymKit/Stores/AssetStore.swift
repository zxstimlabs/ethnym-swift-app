import Foundation
import Observation

/// The bundled token and NFT lists plus the user's custom additions.
@MainActor
@Observable
public final class AssetStore {
    public private(set) var customTokens: [Token]
    public private(set) var customCollections: [NftCollection]
    public private(set) var storageError: String?
    public let chain: Chain

    @ObservationIgnored private let listedTokens: [Token]
    @ObservationIgnored private let listedCollections: [NftCollection]
    @ObservationIgnored private let storage: any DataStorage

    static let tokensKey = "customTokens"
    static let collectionsKey = "customNfts"

    public init(storage: any DataStorage, chain: Chain = .mainnet, listedTokens: [Token]? = nil, listedCollections: [NftCollection]? = nil) {
        self.storage = storage
        self.chain = chain
        self.listedTokens = listedTokens ?? AssetLists.bundledTokens(chainId: chain.id)
        self.listedCollections = listedCollections ?? AssetLists.bundledCollections(chainId: chain.id)
        self.customTokens = storage.decode([Token].self, for: Self.tokensKey) ?? []
        self.customCollections = storage.decode([NftCollection].self, for: Self.collectionsKey) ?? []
    }

    /// Verified list tokens, then custom tokens the list doesn't cover.
    public var tokens: [Listed<Token>] {
        AssetLists.merge(listed: listedTokens, custom: customTokens.filter { $0.chainId == chain.id }, address: \.address)
    }

    public var collections: [Listed<NftCollection>] {
        AssetLists.merge(listed: listedCollections, custom: customCollections.filter { $0.chainId == chain.id }, address: \.address)
    }

    public func isCustom(token address: String) -> Bool {
        customTokens.contains { Address.isSame($0.address, address) }
    }

    public func isCustom(collection address: String) -> Bool {
        customCollections.contains { Address.isSame($0.address, address) }
    }

    public func token(at address: String) -> Listed<Token>? {
        tokens.first { Address.isSame($0.asset.address, address) }
    }

    public func collection(at address: String) -> Listed<NftCollection>? {
        collections.first { Address.isSame($0.asset.address, address) }
    }

    public func addToken(_ token: Token) {
        guard !isCustom(token: token.address) else { return }
        customTokens.append(token)
        persist()
    }

    public func removeToken(_ address: String) {
        customTokens.removeAll { Address.isSame($0.address, address) }
        persist()
    }

    public func addCollection(_ collection: NftCollection) {
        guard !isCustom(collection: collection.address) else { return }
        customCollections.append(collection)
        persist()
    }

    public func removeCollection(_ address: String) {
        customCollections.removeAll { Address.isSame($0.address, address) }
        persist()
    }

    private func persist() {
        do {
            try storage.encode(customTokens, for: Self.tokensKey)
            try storage.encode(customCollections, for: Self.collectionsKey)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }
}
