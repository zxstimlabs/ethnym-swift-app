import BigInt
import Foundation
import Observation

public enum LoadState: Hashable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)

    public var isLoading: Bool { self == .loading }

    public var errorMessage: String? {
        if case let .failed(message) = self { message } else { nil }
    }
}

/// Balances for the active wallet: ether, list and custom tokens, and owned NFTs.
/// Shared by the balances list and the token and NFT pickers, like a query cache.
@MainActor
@Observable
public final class BalancesModel {
    public private(set) var address: String?
    public private(set) var native: BigUInt?
    public private(set) var nativeState: LoadState = .idle
    /// Keyed by lowercased token address.
    public private(set) var tokenBalances: [String: BigUInt] = [:]
    public private(set) var tokensState: LoadState = .idle
    public private(set) var ownedNfts: [OwnedNft] = []
    public private(set) var nftsState: LoadState = .idle

    /// Bumped on every reset, so results for a previous wallet or endpoint are dropped.
    @ObservationIgnored private var generation = 0

    public init() {}

    public func balance(of token: String) -> BigUInt? {
        tokenBalances[token.lowercased()]
    }

    /// Clears everything, for a wallet switch or when going offline.
    public func reset(address: String?) {
        generation += 1
        self.address = address
        native = nil
        nativeState = .idle
        tokenBalances = [:]
        tokensState = .idle
        ownedNfts = []
        nftsState = .idle
    }

    public func refreshAll(address: String, service: EthereumService, tokens: [Listed<Token>], collections: [Listed<NftCollection>]) async {
        if self.address.map({ !Address.isSame($0, address) }) ?? true {
            reset(address: address)
        }
        async let native: Void = refreshNative(address: address, service: service)
        async let tokens: Void = refreshTokens(address: address, service: service, tokens: tokens)
        async let nfts: Void = refreshNfts(address: address, service: service, collections: collections)
        _ = await (native, tokens, nfts)
    }

    public func refreshNative(address: String, service: EthereumService) async {
        let generation = generation
        nativeState = .loading
        do {
            let balance = try await service.balance(of: address)
            guard generation == self.generation else { return }
            native = balance
            nativeState = .loaded
        } catch {
            guard generation == self.generation else { return }
            nativeState = error is CancellationError ? .idle : .failed(error.localizedDescription)
        }
    }

    public func refreshTokens(address: String, service: EthereumService, tokens: [Listed<Token>]) async {
        let generation = generation
        tokensState = .loading
        do {
            let balances = try await service.tokenBalances(tokens.map(\.asset.address), owner: address)
            guard generation == self.generation else { return }
            tokenBalances = balances
            tokensState = .loaded
        } catch {
            guard generation == self.generation else { return }
            tokensState = error is CancellationError ? .idle : .failed(error.localizedDescription)
        }
    }

    /// Refreshes one token, for its row's refresh button.
    public func refreshToken(_ token: String, address: String, service: EthereumService) async {
        let generation = generation
        guard let balance = try? await service.tokenBalance(token, owner: address), generation == self.generation else { return }
        tokenBalances[token.lowercased()] = balance
    }

    public func refreshNfts(address: String, service: EthereumService, collections: [Listed<NftCollection>]) async {
        let generation = generation
        nftsState = .loading
        do {
            let owned = try await service.ownedTokens(in: collections.map(\.asset.address), owner: address)
            guard generation == self.generation else { return }
            ownedNfts = collections.flatMap { collection in
                (owned[collection.asset.address.lowercased()] ?? []).map { OwnedNft(collection: collection, tokenId: String($0)) }
            }
            nftsState = .loaded
        } catch {
            guard generation == self.generation else { return }
            nftsState = error is CancellationError ? .idle : .failed(error.localizedDescription)
        }
    }

    /// Tokens with a balance first, largest first; the rest keep list order.
    public func sorted(_ tokens: [Listed<Token>]) -> [Listed<Token>] {
        tokens.enumerated().sorted { lhs, rhs in
            let a = balance(of: lhs.element.asset.address) ?? 0
            let b = balance(of: rhs.element.asset.address) ?? 0
            return a != b ? a > b : lhs.offset < rhs.offset
        }.map(\.element)
    }
}
