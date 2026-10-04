import BigInt
import Foundation
import Testing
@testable import EthnymKit

// Ported from the web wallet's tests/*.test.ts, plus the checks this app adds.

@Suite("QR code parsing")
struct QRCodeParserTests {
    static let lower = "0x1234567890abcdef1234567890abcdef12345678"
    static let checksum = "0x1234567890AbCdEf1234567890AbCdEf12345678"

    @Test(arguments: [
        (lower, lower),
        (checksum, checksum),
        ("0xABCDEF1234567890ABCDEF1234567890ABCDEF12", "0xABCDEF1234567890ABCDEF1234567890ABCDEF12"),
        ("  \(lower)  ", lower),
        ("eth:\(lower)", lower),
        ("arb1:\(lower)", lower),
        ("base:\(lower)", lower),
        ("matic:\(lower)", lower),
        ("eip155:1:\(lower)", lower),
        ("eip155:137:\(lower)", lower),
        ("eip155:8453:\(lower)", lower),
        ("ethereum:\(lower)@1", lower),
        ("ethereum:\(lower)/transfer?value=1000000", lower),
        ("ethereum:\(lower)@1/transfer?uint256=1000", lower),
        ("ethereum:\(lower)", lower),
        ("0x" + String(repeating: "a", count: 40), "0x" + String(repeating: "a", count: 40)),
        ("  eth:\(lower)  ", lower),
        ("  eip155:1:\(lower)  ", lower),
    ])
    func `extracts the address`(raw: String, expected: String) {
        #expect(QRCodeParser.address(from: raw) == expected)
    }

    @Test(arguments: [
        "0x" + String(repeating: "a", count: 39),
        "0x" + String(repeating: "a", count: 41),
        "",
        "not-an-address",
        "0x1234567890abcdef",
        "\(lower)FF",
        "0xGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        "vitalik.eth",
        "   ",
        "0x",
        "1234567890abcdef1234567890abcdef12345678",
        "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
    ])
    func `returns nil for anything else`(raw: String) {
        #expect(QRCodeParser.address(from: raw) == nil)
    }
}

@Suite("RPC URL validation")
struct RpcValidationTests {
    @Test(arguments: [
        "https://eth-mainnet.g.alchemy.com/v2/key",
        "http://localhost:8545",
        "https://rpc.example.com/v2?token=abc",
        "https://rpc.example.com/",
        "  https://rpc.example.com  ",
    ])
    func `accepts http and https`(url: String) {
        #expect(RpcValidation.validateURL(url) == nil)
    }

    @Test(arguments: [
        ("", "RPC URL is required"),
        ("   ", "RPC URL is required"),
        ("ws://rpc.example.com", "RPC URL must use http or https"),
        ("wss://rpc.example.com", "RPC URL must use http or https"),
        ("ftp://rpc.example.com", "RPC URL must use http or https"),
        ("rpc.example.com", "Invalid URL"),
        ("//rpc.example.com", "Invalid URL"),
        ("notaurl", "Invalid URL"),
        ("https://", "Invalid URL"),
    ])
    func `explains what is wrong`(url: String, message: String) {
        #expect(RpcValidation.validateURL(url) == message)
    }
}

@Suite("Transaction JSON validation")
struct PreparedTransactionTests {
    static let address = "0x1234567890abcdef1234567890abcdef12345678"

    @Test func `parses the required fields`() throws {
        let tx = try PreparedTransaction.validate(#"{"to": "\#(Self.address)", "chainId": 1}"#).get()
        #expect(tx.to == Self.address)
        #expect(tx.chainId == 1)
    }

    @Test func `parses optional fields`() throws {
        let tx = try PreparedTransaction.validate(#"{"to": "\#(Self.address)", "chainId": 137, "value": "0x38D7EA4C68000", "gas": "0x5208", "nonce": 42}"#).get()
        #expect(tx.chainId == 137)
        #expect(tx.nonce == 42)
        #expect(tx.valueAmount == BigUInt(1_000_000_000_000_000))
        #expect(tx.gasAmount == 21_000)
    }

    @Test(arguments: [
        #"{"to": "\#(address)", "chainId": 1, "type": "eip1559"}"#,
        #"{"to": "\#(address)", "chainId": 1, "type": "legacy"}"#,
        #"{"to": "\#(address)", "chainId": 1, "maxFeePerGas": "0x3B9ACA00"}"#,
        #"{"to": "\#(address)", "chainId": 1, "maxPriorityFeePerGas": "0x3B9ACA00"}"#,
        #"{"to": "\#(address)", "chainId": 1, "data": "0xabcdef"}"#,
        #"{"to": "\#(address)", "chainId": 1, "account": "\#(address)"}"#,
        #"{"to": "\#(address)", "chainId": 1, "from": "\#(address)"}"#,
        #"{"to": "\#(address)", "chainId": 8453}"#,
        #"{"to": "\#(address)", "chainId": 42161}"#,
    ])
    func `accepts`(json: String) {
        #expect((try? PreparedTransaction.validate(json).get()) != nil)
    }

    @Test(arguments: [
        ("", PreparedTransaction.ValidationError.empty),
        ("   ", .invalidJSON),
        ("{not json}", .invalidJSON),
        ("[1, 2, 3]", .missingTo),
        (#""just a string""#, .missingTo),
        ("42", .missingTo),
        ("null", .invalidJSON),
        (#"{"chainId": 1}"#, .missingTo),
        (#"{"to": 12345, "chainId": 1}"#, .missingTo),
        (#"{"to": null, "chainId": 1}"#, .missingTo),
        (#"{"to": {}, "chainId": 1}"#, .missingTo),
        (#"{"to": "\#(address)"}"#, .invalidChainId),
        (#"{"to": "\#(address)", "chainId": "1"}"#, .invalidChainId),
        (#"{"to": "\#(address)", "chainId": null}"#, .invalidChainId),
        (#"{"to": "\#(address)", "chainId": true}"#, .invalidChainId),
        ("{}", .missingTo),
        (#"{"to": "\#(address)", "chainId": 1, "gas": "lots"}"#, .invalidQuantity("gas")),
        (#"{"to": "\#(address)", "chainId": 1, "data": "0xzz"}"#, .invalidData),
    ])
    func `rejects`(json: String, error: PreparedTransaction.ValidationError) {
        #expect(PreparedTransaction.validate(json) == .failure(error))
    }

    @Test func `messages match the web wallet`() {
        #expect(PreparedTransaction.ValidationError.empty.errorDescription == "Please enter the transaction JSON")
        #expect(PreparedTransaction.ValidationError.invalidJSON.errorDescription == "Invalid JSON format")
        #expect(PreparedTransaction.ValidationError.missingTo.errorDescription == "Missing 'to' address")
        #expect(PreparedTransaction.ValidationError.invalidChainId.errorDescription == "Missing or invalid 'chainId' (must be a number)")
    }
}

@Suite("Contacts")
struct ContactTests {
    static let a = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    static let b = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    static let sample = [
        Contact(id: "1", address: a, name: "Alice", chain: 1, metadata: .init(tags: ["defi", "team"], note: "main wallet")),
        Contact(id: "2", address: b, name: "Bob", chain: 137, metadata: .init(tags: ["personal"], note: "polygon user")),
    ]

    @Test func `name is required`() {
        #expect(ContactValidation.validateName("Alice") == nil)
        #expect(ContactValidation.validateName("") == "Please enter a name")
        #expect(ContactValidation.validateName("   ") == "Please enter a name")
        #expect(ContactValidation.validateName("こんにちは") == nil)
    }

    @Test func `address is required and unique`() {
        #expect(ContactValidation.validateAddress(Self.a, existingAddresses: []) == nil)
        #expect(ContactValidation.validateAddress("", existingAddresses: []) == "Please enter an address")
        #expect(ContactValidation.validateAddress("   ", existingAddresses: []) == "Please enter an address")
        #expect(ContactValidation.validateAddress(Self.a, existingAddresses: [Self.a]) == "Address already in address book")
        #expect(ContactValidation.validateAddress(Self.a.uppercased().replacingOccurrences(of: "0X", with: "0x"), existingAddresses: [Self.a]) == "Address already in address book")
        #expect(ContactValidation.validateAddress("  \(Self.a)  ", existingAddresses: [Self.a]) == "Address already in address book")
        #expect(ContactValidation.validateAddress("vitalik.eth", existingAddresses: []) == nil)
        #expect(ContactValidation.validateAddress("nonsense", existingAddresses: []) == "Enter a 0x address or an ENS name")
    }

    @Test func `chain is optional but numeric`() {
        #expect(ContactValidation.validateChain("") == nil)
        #expect(ContactValidation.validateChain("1") == nil)
        #expect(ContactValidation.validateChain("137") == nil)
        #expect(ContactValidation.validateChain("   ") == nil)
        #expect(ContactValidation.validateChain("mainnet") == "Chain must be a numeric chain ID")
        #expect(ContactValidation.validateChain("1abc") == "Chain must be a numeric chain ID")
    }

    @Test(arguments: [
        ("defi,team,hot", ["defi", "team", "hot"]),
        ("defi , team , hot", ["defi", "team", "hot"]),
        ("defi,,team", ["defi", "team"]),
        ("", []),
        ("   ", []),
        ("defi", ["defi"]),
        ("  defi  ", ["defi"]),
        ("defi,team,", ["defi", "team"]),
    ])
    func `parses tags`(raw: String, tags: [String]) {
        #expect(ContactValidation.parseTags(raw) == tags)
    }

    @Test func `filters by name, address, tag and note`() {
        #expect(ContactValidation.filter(Self.sample, query: "").count == 2)
        #expect(ContactValidation.filter(Self.sample, query: "alice").map(\.name) == ["Alice"])
        #expect(ContactValidation.filter(Self.sample, query: "aaaaaa").map(\.name) == ["Alice"])
        #expect(ContactValidation.filter(Self.sample, query: "DEFI").map(\.name) == ["Alice"])
        #expect(ContactValidation.filter(Self.sample, query: "polygon user").map(\.name) == ["Bob"])
        #expect(ContactValidation.filter(Self.sample, query: "zzz-no-match").isEmpty)
        #expect(ContactValidation.filter([], query: "alice").isEmpty)
    }

    @Test func `encodes chain as null when chain-agnostic`() throws {
        let contact = Contact(address: Self.a, name: "Any", chain: nil, metadata: .init())
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(contact)) as? [String: Any])
        #expect(json["chain"] is NSNull)
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test func `truncates addresses and hashes`() {
        #expect(Formatting.truncateAddress("0x1234567890abcdef1234567890abcdef12345678") == "0x1234...5678")
        #expect(Formatting.truncateAddress(nil) == "")
        #expect(Formatting.truncateAddress("") == "")
        #expect(Formatting.truncateHash("0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab") == "0xabcd...90ab")
    }

    @Test func `names known chains`() {
        #expect(Formatting.chainName(1) == "Ethereum")
        #expect(Formatting.chainName(137) == "Polygon")
        #expect(Formatting.chainName(8453) == "Base")
        #expect(Formatting.chainName(9999) == nil)
        #expect(Formatting.chainLabel(9999) == "Chain 9999")
    }

    @Test func `chunks addresses for reading`() {
        #expect(Address.chunks("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266") == ["0x", "f39F", "d6e5", "1aad", "88F6", "F4ce", "6aB8", "8272", "79cf", "fFb9", "2266"])
    }
}

@Suite("Addresses")
struct AddressTests {
    @Test func `validates format and checksum`() {
        #expect(Address.isValid("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"))
        #expect(Address.isValid("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"))
        #expect(Address.isValid("0xF39FD6E51AAD88F6F4CE6AB8827279CFFFB92266"))
        #expect(!Address.isValid("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92267"))
        #expect(!Address.isValid("0xF39fd6e51aad88F6F4ce6aB8827279cffFb92266"))
        #expect(!Address.isValid("f39fd6e51aad88f6f4ce6ab8827279cfffb92266"))
        #expect(!Address.isValid("vitalik.eth"))
    }

    @Test func `checksums`() {
        #expect(Address.checksummed("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266") == "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
    }

    @Test func `recognizes ENS names`() {
        #expect("vitalik.eth".isENSName)
        #expect(" Vitalik.ETH ".isENSName)
        #expect(!".eth".isENSName)
        #expect(!"vitalik".isENSName)
    }
}

@Suite("Units")
struct UnitsTests {
    @Test(arguments: [
        (BigUInt(0), 18, "0"),
        (BigUInt(1), 18, "0.000000000000000001"),
        (BigUInt(1_500_000_000_000_000_000), 18, "1.5"),
        (BigUInt(1_000_000), 6, "1"),
        (BigUInt(1_234_567), 6, "1.234567"),
        (BigUInt(30_123_456_789), 9, "30.123456789"),
        (BigUInt(42), 0, "42"),
    ])
    func `formats like viem`(value: BigUInt, decimals: Int, expected: String) {
        #expect(Units.format(value, decimals: decimals) == expected)
    }

    @Test(arguments: [
        ("1.5", 18, BigUInt(1_500_000_000_000_000_000)),
        (".5", 18, BigUInt(500_000_000_000_000_000)),
        ("1.", 6, BigUInt(1_000_000)),
        ("0", 18, BigUInt(0)),
        ("  2  ", 0, BigUInt(2)),
        ("1.0000005", 6, BigUInt(1_000_001)),
        ("1.0000004", 6, BigUInt(1_000_000)),
    ])
    func `parses like viem`(text: String, decimals: Int, expected: BigUInt) throws {
        #expect(try Units.parse(text, decimals: decimals) == expected)
    }

    @Test(arguments: ["", ".", "abc", "1.2.3", "-1", "1e18", "1,5"])
    func `rejects malformed amounts`(text: String) {
        #expect(throws: Units.ParseError.invalidFormat) { try Units.parse(text, decimals: 18) }
    }

    @Test func `truncates for display`() {
        #expect(Units.format(BigUInt(1_234_567_891_234_567_891), decimals: 18, maxFractionDigits: 6) == "1.234567")
        #expect(Units.format(BigUInt(1_000_000_000_000_000_000), decimals: 18, maxFractionDigits: 6) == "1")
        #expect(Units.format(BigUInt(1), decimals: 18, maxFractionDigits: 6) == "<0.000001")
        #expect(Units.format(BigUInt(0), decimals: 18, maxFractionDigits: 6) == "0")
        #expect(Units.format(BigUInt(1_500_000), decimals: 6, maxFractionDigits: 2) == "1.5")
    }

    @Test func `reads JSON-RPC quantities`() {
        #expect(Units.quantity("0x5208") == 21_000)
        #expect(Units.quantity("0x") == 0)
        #expect(Units.quantity("21000") == 21_000)
        #expect(Units.quantity("0xzz") == nil)
        #expect(Units.quantity("") == nil)
    }
}

@Suite("Activity")
struct ActivityFormattingTests {
    @Test func `formats values by type`() {
        let base = ActivityRecord(txHash: "0x1", from: "0x1", to: "0x2", chainId: 1, type: .native, nativeValue: "1500000000000000000", timestamp: 0)
        #expect(base.formattedValue == "1.5 ETH")

        var token = base
        token.type = .erc20
        token.tokenValue = "1000000"
        token.tokenDecimals = 6
        token.tokenSymbol = "USDC"
        #expect(token.formattedValue == "1 USDC")

        var nft = base
        nft.type = .erc721
        nft.nftId = "42"
        #expect(nft.formattedValue == "Token ID: 42")

        var raw = base
        raw.type = .raw
        #expect(raw.formattedValue == nil)
    }
}
