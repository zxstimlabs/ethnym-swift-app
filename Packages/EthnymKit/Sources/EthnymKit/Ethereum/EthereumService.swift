import BigInt
import Foundation
import web3

public struct TokenMetadata: Hashable, Sendable {
    public var name: String
    public var symbol: String
    public var decimals: Int
}

public struct CollectionMetadata: Hashable, Sendable {
    public var name: String
    public var symbol: String
}

public enum ReceiptStatus: Hashable, Sendable {
    case success
    case reverted
}

/// A JSON-RPC failure, reduced to a message worth showing.
public struct EthereumServiceError: LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }

    static func wrapping(_ error: any Error) -> EthereumServiceError {
        if let error = error as? EthereumServiceError { return error }
        if let error = error as? EthereumClientError {
            switch error {
            case let .executionError(detail): return .init(detail.message)
            case .noResultFound, .unexpectedReturnValue, .decodeIssue: return .init("The RPC endpoint returned an unexpected response.")
            default: return .init("The RPC request couldn't be completed.")
            }
        }
        if let error = error as? JSONRPCError {
            switch error {
            case let .executionError(result): return .init(result.error.message)
            case .requestRejected: return .init("The RPC endpoint rejected the request.")
            default: return .init("Network request failed. Check your connection and RPC endpoint.")
            }
        }
        if let error = error as? Multicall.MulticallError, case let .executionFailed(underlying?) = error {
            return wrapping(underlying)
        }
        if error is EthereumNameServiceError { return .init("Failed to resolve ENS") }
        return .init(error.localizedDescription)
    }
}

/// Reads and broadcasts through one RPC endpoint, using web3.swift's client, ABI functions,
/// multicall and ENS resolver.
public struct EthereumService: Sendable {
    public let chain: Chain
    public let rpcURL: URL
    private let client: EthereumHttpClient

    /// Receipt polling interval; about a third of a mainnet block.
    public static let receiptPollInterval: Duration = .seconds(4)

    public init(rpcURL: URL, chain: Chain = .mainnet) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        self.chain = chain
        self.rpcURL = rpcURL
        self.client = EthereumHttpClient(
            url: rpcURL,
            sessionConfig: configuration,
            network: chain.id == 1 ? .mainnet : .custom(String(chain.id))
        )
    }

    private func rpc<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EthereumServiceError.wrapping(error)
        }
    }

    // MARK: - Account and gas

    public func balance(of address: String) async throws -> BigUInt {
        try await rpc { try await client.eth_getBalance(address: EthereumAddress(address), block: .Latest) }
    }

    public func gasPrice() async throws -> BigUInt {
        try await rpc { try await client.eth_gasPrice() }
    }

    /// The node's suggested tip. Falls back to 1 gwei when the method isn't supported.
    public func maxPriorityFeePerGas() async -> BigUInt {
        let fallback = BigUInt(1_000_000_000)
        guard let hex = try? await client.networkProvider.send(method: "eth_maxPriorityFeePerGas", params: [String](), receive: String.self) as? String else {
            return fallback
        }
        return BigUInt(hex: hex) ?? fallback
    }

    /// The next nonce, counting pending transactions.
    public func nonce(for address: String) async throws -> Int {
        try await rpc { try await client.eth_getTransactionCount(address: EthereumAddress(address), block: .Pending) }
    }

    public func estimateGas(from: String, to: String, value: BigUInt, data: Data) async throws -> BigUInt {
        let transaction = EthereumTransaction(
            from: EthereumAddress(from),
            to: EthereumAddress(to),
            value: value,
            data: data,
            nonce: nil,
            gasPrice: nil,
            gasLimit: nil,
            chainId: chain.id
        )
        return try await rpc { try await client.eth_estimateGas(transaction) }
    }

    // MARK: - Broadcast and receipts

    /// Returns the transaction hash.
    public func sendRawTransaction(_ raw: Data) async throws -> String {
        try await rpc {
            let result = try await client.networkProvider.send(method: "eth_sendRawTransaction", params: [raw.hexString], receive: String.self)
            guard let hash = result as? String else { throw EthereumServiceError("The RPC endpoint returned an unexpected response.") }
            return hash
        }
    }

    private struct ReceiptBody: Decodable, Sendable {
        var status: String?
    }

    /// The receipt status, or nil while the transaction is still pending.
    public func receiptStatus(for hash: String) async throws -> ReceiptStatus? {
        try await rpc {
            let result = try await client.networkProvider.send(method: "eth_getTransactionReceipt", params: [hash], receive: ReceiptBody?.self)
            guard let body = result as? ReceiptBody? else { throw EthereumServiceError("The RPC endpoint returned an unexpected response.") }
            guard let body else { return nil }
            return body.status.flatMap { BigUInt(hex: $0) } == 0 ? .reverted : .success
        }
    }

    /// Polls until the transaction is mined. Cancelling the calling task stops the polling.
    public func waitForReceipt(_ hash: String) async throws -> ReceiptStatus {
        var transientFailures = 0
        while true {
            try Task.checkCancellation()
            do {
                if let status = try await receiptStatus(for: hash) { return status }
                transientFailures = 0
            } catch let error as EthereumServiceError {
                transientFailures += 1
                if transientFailures >= 5 { throw error }
            }
            try await Task.sleep(for: Self.receiptPollInterval)
        }
    }

    // MARK: - ENS

    /// The address an ENS name points to, or nil if it doesn't resolve.
    public func resolveENS(_ name: String) async throws -> String? {
        let service = EthereumNameService(client: client)
        do {
            let address = try await service.resolve(ens: name.trimmed.lowercased(), mode: .allowOffchainLookup)
            return address == .zero ? nil : address.toChecksumAddress()
        } catch EthereumNameServiceError.ensUnknown {
            return nil
        } catch {
            throw EthereumServiceError.wrapping(error)
        }
    }

    // MARK: - ERC-20

    public func tokenMetadata(_ token: String) async throws -> TokenMetadata {
        let erc20 = ERC20(client: client)
        let contract = EthereumAddress(token)
        return try await rpc {
            async let name = erc20.name(tokenContract: contract)
            async let symbol = erc20.symbol(tokenContract: contract)
            async let decimals = erc20.decimals(tokenContract: contract)
            return try await TokenMetadata(name: name, symbol: symbol, decimals: Int(decimals))
        }
    }

    public func tokenBalance(_ token: String, owner: String) async throws -> BigUInt {
        try await rpc { try await ERC20(client: client).balanceOf(tokenContract: EthereumAddress(token), address: EthereumAddress(owner)) }
    }

    /// `balanceOf` for many tokens in a few multicalls. Tokens whose call fails are left out.
    public func tokenBalances(_ tokens: [String], owner: String) async throws -> [String: BigUInt] {
        let tokens = tokens.filter(\.isHexAddress)
        let calls = tokens.map { token in
            { try Multicall.Call(function: ERC20Functions.balanceOf(contract: EthereumAddress(token), account: EthereumAddress(owner))) }
        }
        let outputs = try await multicall(calls)
        var balances: [String: BigUInt] = [:]
        for (token, output) in zip(tokens, outputs) {
            if case let .success(data) = output, data.isABIWord, let response = (try? ERC20Responses.balanceResponse(data: data)) ?? nil {
                balances[token.lowercased()] = response.value
            }
        }
        return balances
    }

    // MARK: - ERC-721

    public func collectionMetadata(_ contract: String) async throws -> CollectionMetadata {
        let address = EthereumAddress(contract)
        return try await rpc {
            async let name = ERC721MetadataFunctions.name(contract: address).call(withClient: client, responseType: ERC721MetadataResponses.nameResponse.self)
            async let symbol = ERC721MetadataFunctions.symbol(contract: address).call(withClient: client, responseType: ERC721MetadataResponses.symbolResponse.self)
            return try await CollectionMetadata(name: name.value, symbol: symbol.value)
        }
    }

    /// The owner of a token, or nil when the token doesn't exist.
    public func owner(of tokenId: BigUInt, in contract: String) async throws -> String? {
        do {
            let owner = try await ERC721(client: client).ownerOf(contract: EthereumAddress(contract), tokenId: tokenId)
            return owner.toChecksumAddress()
        } catch EthereumClientError.executionError {
            return nil
        } catch {
            throw EthereumServiceError.wrapping(error)
        }
    }

    /// Token IDs the owner holds in each ERC-721 Enumerable collection, keyed by lowercased address.
    /// At most `limit` tokens are listed per collection.
    public func ownedTokens(in collections: [String], owner: String, limit: Int = 50) async throws -> [String: [BigUInt]] {
        let collections = collections.filter(\.isHexAddress)
        let ownerAddress = EthereumAddress(owner)
        let balanceCalls = collections.map { contract in
            { try Multicall.Call(function: ERC721Functions.balanceOf(contract: EthereumAddress(contract), owner: ownerAddress)) }
        }
        let balanceOutputs = try await multicall(balanceCalls)

        var requests: [(collection: String, index: Int)] = []
        for (collection, output) in zip(collections, balanceOutputs) {
            guard case let .success(data) = output, data.isABIWord, let count = (try? ERC721Responses.balanceResponse(data: data))??.value, count > 0 else { continue }
            requests += (0 ..< min(Int(count), limit)).map { (collection, $0) }
        }

        let indexCalls = requests.map { request in
            {
                try Multicall.Call(function: ERC721EnumerableFunctions.tokenOfOwnerByIndex(
                    contract: EthereumAddress(request.collection),
                    address: ownerAddress,
                    index: BigUInt(request.index)
                ))
            }
        }
        let indexOutputs = try await multicall(indexCalls)

        var owned: [String: [BigUInt]] = [:]
        for (request, output) in zip(requests, indexOutputs) {
            if case let .success(data) = output, data.isABIWord, let tokenId = (try? ERC721EnumerableResponses.numberResponse(data: data))??.value {
                owned[request.collection.lowercased(), default: []].append(tokenId)
            }
        }
        return owned
    }

    // MARK: - Multicall

    private static let multicallBatchSize = 150

    /// Runs calls through Multicall2 `tryAggregate`, so one failing call doesn't sink the batch.
    private func multicall(_ calls: [() throws -> Multicall.Call]) async throws -> [Multicall.Output] {
        guard !calls.isEmpty else { return [] }
        let built = try calls.map { try $0() }
        let multicall = Multicall(client: client)
        var outputs: [Multicall.Output] = []
        for start in stride(from: 0, to: built.count, by: Self.multicallBatchSize) {
            let batch = Array(built[start ..< min(start + Self.multicallBatchSize, built.count)])
            let response = try await rpc { try await multicall.tryAggregate(requireSuccess: false, calls: batch) }
            outputs += response.outputs
        }
        return outputs
    }
}

private extension String {
    /// Hex return data holding at least one 32-byte word. A call to a function the contract
    /// doesn't implement, or to an address without code, can "succeed" with empty data.
    var isABIWord: Bool { count >= 66 }
}
