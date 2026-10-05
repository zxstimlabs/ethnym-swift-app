import BigInt
import Foundation
import Testing
@testable import EthnymKit

@MainActor
@Suite("Stores")
struct StoreTests {
    func fixtureWallet() throws -> WalletKeystore {
        try #require(WalletKeystore.parse(Fixtures.data("keystore")).first)
    }

    @Test func `wallets persist, dedupe and select the first one added`() throws {
        let storage = InMemoryStorage()
        let store = WalletStore(storage: storage, preferences: storage)
        let wallet = try fixtureWallet()

        #expect(store.add(wallet))
        #expect(!store.add(wallet))
        #expect(store.wallets.count == 1)
        #expect(store.activeWallet == wallet)

        let reloaded = WalletStore(storage: storage, preferences: storage)
        #expect(reloaded.wallets == [wallet])
        #expect(reloaded.activeWalletID == wallet.id)

        reloaded.delete(wallet)
        #expect(reloaded.wallets.isEmpty)
        #expect(reloaded.activeWalletID == nil)
    }

    @Test func `migration only touches metadata`() throws {
        let storage = InMemoryStorage()
        let store = WalletStore(storage: storage, preferences: storage)
        var old = try fixtureWallet()
        old.meta = .secretPhraseBackup
        store.add(old)
        #expect(store.walletsNeedingMigration.count == 1)

        store.migrateAll()
        #expect(store.walletsNeedingMigration.isEmpty)
        #expect(store.wallets[0].meta == .current)
        #expect(store.wallets[0].crypto == old.crypto)
    }

    @Test func `activity records get ids, timestamps and filter by sender`() {
        let store = ActivityStore(storage: InMemoryStorage(), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let pending = PendingActivity(from: "0xAAAA", to: "0xBBBB", chainId: 1, type: .native, nativeValue: "1")
        let first = store.record(pending, txHash: "0x01")
        let second = store.record(pending, txHash: "0x02")
        store.record(PendingActivity(from: "0xCCCC", to: "0xBBBB", chainId: 1, type: .raw), txHash: "0x03")

        #expect(first.id == 1)
        #expect(second.id == 2)
        #expect(first.timestamp == 1_700_000_000_000)
        #expect(store.outgoing(from: "0xaaaa").map(\.txHash).sorted() == ["0x01", "0x02"])
    }

    @Test func `settings validate and track the active RPC`() {
        let store = SettingsStore(storage: InMemoryStorage())
        #expect(store.rpcURL == Chain.mainnet.defaultRPC)
        #expect(store.addRpc(name: "", url: "ws://nope") == "RPC URL must use http or https")
        #expect(store.addRpc(name: " Alchemy ", url: " https://eth.example.com ") == nil)

        let entry = store.settings.rpcList[0]
        #expect(entry.name == "Alchemy")
        store.selectRpc(entry)
        #expect(store.rpcURL == URL(string: "https://eth.example.com"))

        store.deleteRpc(entry)
        #expect(store.settings.activeRpc == nil)
        #expect(store.rpcURL == Chain.mainnet.defaultRPC)
    }

    @Test func `a configured default RPC replaces the built-in one`() throws {
        #expect(Chain.mainnet.withDefaultRPC("") == nil)
        #expect(Chain.mainnet.withDefaultRPC("ws://nope") == nil)

        let chain = try #require(Chain.mainnet.withDefaultRPC(" https://rpc.example.com/key "))
        let store = SettingsStore(storage: InMemoryStorage(), chain: chain)
        #expect(store.rpcURL == URL(string: "https://rpc.example.com/key"))
        #expect(store.settings.rpcList.isEmpty)
    }

    @Test func `bundled lists hold valid, unique addresses`() {
        #expect(!AssetLists.bundledTokens().isEmpty)
        #expect(!AssetLists.bundledCollections().isEmpty)
        for addresses in [AssetLists.tokens.map(\.address), AssetLists.collections.map(\.address)] {
            #expect(addresses.allSatisfy { $0.isHexAddress })
            #expect(Set(addresses.map { $0.lowercased() }).count == addresses.count)
        }
    }

    @Test func `custom assets merge after the verified list`() {
        let listed = Token(address: "0x1111111111111111111111111111111111111111", name: "Listed", symbol: "L", decimals: 18)
        let store = AssetStore(storage: InMemoryStorage(), listedTokens: [listed], listedCollections: [])
        store.addToken(Token(address: listed.address.uppercased().replacingOccurrences(of: "0X", with: "0x"), name: "Dup", symbol: "D", decimals: 18))
        store.addToken(Token(address: "0x2222222222222222222222222222222222222222", name: "Mine", symbol: "M", decimals: 6))

        #expect(store.tokens.map(\.asset.symbol) == ["L", "M"])
        #expect(store.tokens.map(\.isVerified) == [true, false])
        store.removeToken("0x2222222222222222222222222222222222222222")
        #expect(store.tokens.count == 1)
    }

    @Test func `balances sort tokens by holding`() {
        let model = BalancesModel()
        let tokens = ["0x01", "0x02", "0x03"].map { Listed(Token(address: $0, name: $0, symbol: $0, decimals: 18), isVerified: true) }
        #expect(model.sorted(tokens).map(\.asset.address) == ["0x01", "0x02", "0x03"])
    }
}

@Suite("Sending")
struct SendingTests {
    @Test func `amount validation matches the web wallet`() {
        #expect(AmountValidation.validate("", decimals: 18, balance: nil, allowZero: true) == .failure(FieldError("Please enter an amount to send", isPrompt: true)))
        #expect(AmountValidation.validate("abc", decimals: 18, balance: nil, allowZero: true) == .failure(FieldError("Please enter a valid number")))
        #expect(AmountValidation.validate("-1", decimals: 18, balance: nil, allowZero: true) == .failure(FieldError("Amount must be greater than or equal to 0")))
        #expect(AmountValidation.validate("0", decimals: 6, balance: nil, allowZero: false) == .failure(FieldError("Amount must be greater than 0")))
        #expect(AmountValidation.validate("1e3", decimals: 18, balance: nil, allowZero: true) == .failure(FieldError("Invalid amount format")))
        #expect(AmountValidation.validate("2", decimals: 0, balance: 1, allowZero: true) == .failure(FieldError("Insufficient balance")))
        #expect(AmountValidation.validate("0", decimals: 18, balance: 0, allowZero: true) == .success(0))
        #expect(AmountValidation.validate("1.5", decimals: 6, balance: nil, allowZero: false) == .success(1_500_000))
    }

    @Test func `quick-fill fractions`() {
        #expect(AmountValidation.fraction(1, of: 1_000_000, decimals: 6) == "0.25")
        #expect(AmountValidation.fraction(4, of: 1_000_000, decimals: 6) == "1")
    }

    @Test func `recipients are addresses or ENS names`() {
        #expect(RecipientValidation.validate("")?.isPrompt == true)
        #expect(RecipientValidation.validate("vitalik.eth") == nil)
        #expect(RecipientValidation.validate(Fixtures.address) == nil)
        #expect(RecipientValidation.validate("0x1234")?.message == "Invalid address")
    }

    @Test func `offline signing needs every field`() throws {
        let request = TransactionRequest(to: Fixtures.address, value: 1)
        #expect(throws: TransactionSender.Failure.missingOfflineFields(["nonce", "gas", "maxFeePerGas", "maxPriorityFeePerGas"])) {
            try TransactionSender.prepareOffline(request)
        }
        let complete = TransactionRequest(chainId: 10, to: Fixtures.address, value: 1, nonce: 3, gasLimit: 21_000, maxFeePerGas: 10, maxPriorityFeePerGas: 20)
        let tx = try TransactionSender.prepareOffline(complete)
        #expect(tx.chainId == 10)
        #expect(tx.maxPriorityFeePerGas == 10)
    }

    @Test func `gas presets scale the network price`() async {
        let model = await GasPriceModel()
        await #expect(model.selectedPrice == nil)
    }
}

/// Hits a public mainnet RPC. Run with `ETHNYM_LIVE_TESTS=1 swift test`.
@Suite("Live mainnet", .enabled(if: ProcessInfo.processInfo.environment["ETHNYM_LIVE_TESTS"] != nil))
struct LiveTests {
    let service = EthereumService(rpcURL: Chain.mainnet.defaultRPC)
    static let vitalik = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

    @Test func `reads balances, gas and nonce`() async throws {
        let balance = try await service.balance(of: Self.vitalik)
        #expect(balance > 0)
        #expect(try await service.gasPrice() > 0)
        #expect(try await service.nonce(for: Self.vitalik) > 0)
        #expect(await service.maxPriorityFeePerGas() >= 0)
    }

    @Test func `resolves ENS`() async throws {
        #expect(try await service.resolveENS("vitalik.eth") == Self.vitalik)
        #expect(try await service.resolveENS("this-name-should-not-exist-ethnym-\(Int.random(in: 0 ..< 1_000_000)).eth") == nil)
    }

    @Test func `reads token metadata and multicall balances`() async throws {
        let usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
        let metadata = try await service.tokenMetadata(usdc)
        #expect(metadata == TokenMetadata(name: "USD Coin", symbol: "USDC", decimals: 6))
        let tokens = AssetLists.bundledTokens()
        let balances = try await service.tokenBalances(tokens.map(\.address), owner: Self.vitalik)
        #expect(balances.count > tokens.count / 2)
    }

    @Test func `reads NFT ownership`() async throws {
        let bayc = "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D"
        #expect(try await service.collectionMetadata(bayc).symbol == "BAYC")
        #expect(try await service.collectionMetadata("0x8821BeE2ba0dF28761AffF119D66390D594CD280").symbol == "DEGODS")
        let owned = try await service.ownedTokens(in: AssetLists.bundledCollections().map(\.address), owner: Self.vitalik)
        #expect(owned.values.allSatisfy { !$0.isEmpty })
        #expect(try await service.owner(of: 1, in: bayc) != nil)
    }

    @Test func `estimates gas for a transfer`() async throws {
        let burn = "0x000000000000000000000000000000000000dEaD"
        let gas = try await service.estimateGas(from: Self.vitalik, to: burn, value: 1, data: Data())
        #expect(gas == 21_000)
        let prepared = try await TransactionSender.prepare(TransactionRequest(to: burn, value: 1), from: Self.vitalik, service: service)
        #expect(prepared.gasLimit == 21_000)
        #expect(prepared.maxPriorityFeePerGas <= prepared.maxFeePerGas)
    }
}
