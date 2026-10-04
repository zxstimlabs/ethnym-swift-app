import Foundation

/// An ERC-20 token, in Uniswap token-list shape.
public struct Token: Codable, Hashable, Sendable {
    public var chainId: Int
    public var address: String
    public var name: String
    public var symbol: String
    public var decimals: Int
    public var logoURI: String?

    public init(chainId: Int = Chain.mainnet.id, address: String, name: String, symbol: String, decimals: Int, logoURI: String? = nil) {
        self.chainId = chainId
        self.address = address
        self.name = name
        self.symbol = symbol
        self.decimals = decimals
        self.logoURI = logoURI
    }
}

/// An ERC-721 collection.
public struct NftCollection: Codable, Hashable, Sendable {
    public var chainId: Int
    public var address: String
    public var name: String
    public var symbol: String
    public var standard: String

    public init(chainId: Int = Chain.mainnet.id, address: String, name: String, symbol: String, standard: String = "ERC721") {
        self.chainId = chainId
        self.address = address
        self.name = name
        self.symbol = symbol
        self.standard = standard
    }
}

/// A token or collection with whether it came from the bundled (verified) list.
public struct Listed<Asset: Hashable & Sendable>: Hashable, Sendable {
    public var asset: Asset
    public var isVerified: Bool

    public init(_ asset: Asset, isVerified: Bool) {
        self.asset = asset
        self.isVerified = isVerified
    }
}

extension Listed: Identifiable where Asset == Token {
    public var id: String { asset.address.lowercased() }
}

/// One NFT the wallet owns.
public struct OwnedNft: Hashable, Sendable, Identifiable {
    public var collection: Listed<NftCollection>
    public var tokenId: String

    public init(collection: Listed<NftCollection>, tokenId: String) {
        self.collection = collection
        self.tokenId = tokenId
    }

    public var id: String { "\(collection.asset.address.lowercased())-\(tokenId)" }
}

/// The bundled token and NFT lists.
public enum AssetLists {
    /// The placeholder the token list uses for native ether.
    static let etherSentinel = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    private struct TokenList: Decodable { var tokens: [Token] }
    private struct NftList: Decodable { var collections: [NftCollection] }

    public static func bundledTokens(chainId: Int = Chain.mainnet.id) -> [Token] {
        guard let url = Bundle.module.url(forResource: "token-list", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode(TokenList.self, from: data)
        else { return [] }
        return list.tokens.filter { $0.chainId == chainId && $0.address.isHexAddress && $0.address.lowercased() != etherSentinel }
    }

    public static func bundledCollections(chainId: Int = Chain.mainnet.id) -> [NftCollection] {
        guard let url = Bundle.module.url(forResource: "nft-list", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode(NftList.self, from: data)
        else { return [] }
        return list.collections.filter { $0.chainId == chainId && $0.address.isHexAddress }
    }

    /// Verified list entries first, then custom entries the list doesn't already cover.
    public static func merge<Asset>(
        listed: [Asset],
        custom: [Asset],
        address: KeyPath<Asset, String>
    ) -> [Listed<Asset>] {
        let known = Set(listed.map { $0[keyPath: address].lowercased() })
        let extra = custom.filter { !known.contains($0[keyPath: address].lowercased()) }
        return listed.map { Listed($0, isVerified: true) } + extra.map { Listed($0, isVerified: false) }
    }
}
