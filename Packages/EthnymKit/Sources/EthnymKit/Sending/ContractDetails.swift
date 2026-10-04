import BigInt
import Foundation
import Observation

/// Name, symbol, decimals and the wallet's balance for whatever ERC-20 contract is entered.
@MainActor
@Observable
public final class TokenDetails {
    public private(set) var contract: String?
    public private(set) var metadata: TokenMetadata?
    public private(set) var balance: BigUInt?
    public private(set) var state: LoadState = .idle

    public init() {}

    /// Loads details for `contract`. Known tokens use their list metadata; only the balance is fetched.
    public func load(contract: String?, owner: String?, known: Token?, service: EthereumService?) async {
        guard let contract, contract.isHexAddress else {
            clear()
            return
        }
        if self.contract.map({ !Address.isSame($0, contract) }) ?? true {
            metadata = known.map { TokenMetadata(name: $0.name, symbol: $0.symbol, decimals: $0.decimals) }
            balance = nil
        }
        self.contract = contract
        guard let service else {
            state = .idle
            return
        }
        state = .loading
        do {
            async let fetchedMetadata: TokenMetadata = if let metadata { metadata } else { try await service.tokenMetadata(contract) }
            async let fetchedBalance: BigUInt? = if let owner { try await service.tokenBalance(contract, owner: owner) } else { nil }
            let (newMetadata, newBalance) = try await (fetchedMetadata, fetchedBalance)
            guard self.contract == contract else { return }
            metadata = newMetadata
            balance = newBalance
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard self.contract == contract else { return }
            state = .failed("Couldn't read this token contract.")
        }
    }

    public func clear() {
        contract = nil
        metadata = nil
        balance = nil
        state = .idle
    }
}

/// Name, symbol and the current owner of a token ID, for whatever ERC-721 contract is entered.
@MainActor
@Observable
public final class NftDetails {
    public private(set) var contract: String?
    public private(set) var metadata: CollectionMetadata?
    public private(set) var owner: String?
    public private(set) var tokenId: BigUInt?
    public private(set) var state: LoadState = .idle

    public init() {}

    public func load(contract: String?, tokenId: BigUInt?, known: NftCollection?, service: EthereumService?) async {
        guard let contract, contract.isHexAddress else {
            clear()
            return
        }
        if self.contract.map({ !Address.isSame($0, contract) }) ?? true {
            metadata = known.map { CollectionMetadata(name: $0.name, symbol: $0.symbol) }
        }
        self.contract = contract
        self.tokenId = tokenId
        owner = nil
        guard let service else {
            state = .idle
            return
        }
        state = .loading
        do {
            async let fetchedMetadata: CollectionMetadata? = if let metadata { metadata } else { try? await service.collectionMetadata(contract) }
            async let fetchedOwner: String? = if let tokenId { try await service.owner(of: tokenId, in: contract) } else { nil }
            let (newMetadata, newOwner) = try await (fetchedMetadata, fetchedOwner)
            guard self.contract == contract, self.tokenId == tokenId else { return }
            metadata = newMetadata
            owner = newOwner
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard self.contract == contract else { return }
            state = .failed("Couldn't read this NFT contract.")
        }
    }

    public func clear() {
        contract = nil
        metadata = nil
        owner = nil
        tokenId = nil
        state = .idle
    }
}
