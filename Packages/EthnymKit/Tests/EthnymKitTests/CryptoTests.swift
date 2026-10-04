import BigInt
import Foundation
import Testing
@testable import EthnymKit

@Suite("Keystore")
struct KeystoreTests {
    @Test func `decrypts a keystore written by ox`() async throws {
        let wallet = try #require(WalletKeystore.parse(Fixtures.data("keystore")).first)
        let phrase = try await WalletCrypto.revealPhrase(wallet.keystore, password: Fixtures.password)
        #expect(phrase == Fixtures.phrase)
        #expect(wallet.address == Fixtures.address)
        #expect(wallet.meta == .current)
    }

    @Test func `unlocks an ox keystore to its recorded address`() async throws {
        let wallet = try #require(WalletKeystore.parse(Fixtures.data("keystore")).first)
        let account = try await WalletCrypto.unlock(wallet, password: Fixtures.password)
        #expect(account.address == Fixtures.address)
        #expect(account.privateKey.hexString == "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")
    }

    @Test func `wrong password is reported as such`() async throws {
        let wallet = try #require(WalletKeystore.parse(Fixtures.data("keystore")).first)
        await #expect(throws: Keystore.Failure.wrongPassword) {
            try await WalletCrypto.unlock(wallet, password: "nope")
        }
    }

    @Test func `encrypt round-trips with ox parameters`() async throws {
        let keystore = try await Keystore.encrypt(Data("hello".utf8), password: "pw", iterations: 1_000)
        #expect(keystore.version == 3)
        #expect(keystore.crypto.cipher == "aes-128-ctr")
        #expect(keystore.crypto.kdf == "pbkdf2")
        #expect(keystore.crypto.kdfparams.prf == "hmac-sha256")
        #expect(keystore.crypto.kdfparams.dklen == 32)
        #expect(keystore.crypto.kdfparams.salt.count == 64)
        #expect(keystore.crypto.cipherparams.iv.count == 32)
        #expect(keystore.id == keystore.id.lowercased())
        #expect(try await Keystore.decrypt(keystore, password: "pw") == Data("hello".utf8))
    }

    @Test func `encryption matches ox for fixed salt and iv`() throws {
        // Re-seal the fixture's plaintext with its own salt and IV: the ciphertext and MAC must match.
        let wallet = try #require(WalletKeystore.parse(Fixtures.data("keystore")).first)
        let resealed = try Keystore.encrypt(
            Data(Fixtures.phrase.utf8),
            password: Fixtures.password,
            salt: try #require(Data(hexString: wallet.crypto.kdfparams.salt)),
            iv: try #require(Data(hexString: wallet.crypto.cipherparams.iv)),
            iterations: Keystore.defaultIterations,
            id: wallet.id
        )
        #expect(resealed == wallet.keystore)
    }

    @Test func `rejects unsupported key derivation`() async throws {
        var keystore = try await Keystore.encrypt(Data("x".utf8), password: "pw", iterations: 10)
        keystore.crypto.kdf = "scrypt"
        await #expect(throws: Keystore.Failure.unsupportedKDF("scrypt")) {
            try await Keystore.decrypt(keystore, password: "pw")
        }
    }

    @Test func `keystore JSON keeps the web wallet shape`() throws {
        let original = try JSONSerialization.jsonObject(with: Fixtures.data("keystore")) as? NSDictionary
        let wallet = try #require(WalletKeystore.parse(Fixtures.data("keystore")).first)
        let reencoded = try JSONSerialization.jsonObject(with: wallet.exportedJSON()) as? NSDictionary
        #expect(original == reencoded)
    }

    @Test func `parses an array of keystores`() throws {
        let one = try String(decoding: Fixtures.data("keystore"), as: UTF8.self)
        let wallets = try WalletKeystore.parse(Data("[\(one), \(one)]".utf8))
        #expect(wallets.count == 2)
    }

    @Test func `rejects JSON that isn't a keystore`() {
        #expect(throws: KeystoreImportError.invalidFormat) {
            try WalletKeystore.parse(Data(#"{"hello": "world"}"#.utf8))
        }
    }
}

@Suite("HD wallet")
struct HDWalletTests {
    @Test func `derives Hardhat's first account`() throws {
        let account = try HDWallet.account(fromPhrase: Fixtures.phrase)
        #expect(account.address == Fixtures.address)
    }

    @Test func `matches BIP-32 test vector 1`() throws {
        let seed = try #require(Data(hexString: "000102030405060708090a0b0c0d0e0f"))
        let key = try HDWallet.derivePrivateKey(seed: seed, path: "m/0'/1/2'/2/1000000000")
        #expect(key.hexString == "0x471b76e389e528d6de6d816857e012c5455051cad6660850e58372a6c3e6e7c8")
    }

    @Test func `generates valid 12-word phrases`() throws {
        let phrase = try HDWallet.generatePhrase()
        #expect(phrase.split(separator: " ").count == 12)
        try HDWallet.validate(phrase)
    }

    @Test func `normalizes stray whitespace and case`() {
        #expect(HDWallet.normalize("  Test test\ntest  TEST ") == "test test test test")
    }

    @Test(arguments: [
        "test test test",
        "test test test test test test test test test test test test",
        "test test test test test test test test test test test zzzz",
    ])
    func `rejects invalid phrases`(phrase: String) {
        #expect(throws: HDWallet.Failure.self) { try HDWallet.validate(phrase) }
    }

    @Test func `parses hardened paths`() throws {
        #expect(try HDWallet.parse("m/44'/60'/0'/0/0") == [0x8000_002C, 0x8000_003C, 0x8000_0000, 0, 0])
        #expect(throws: HDWallet.Failure.invalidPath) { try HDWallet.parse("44'/60'") }
    }

    @Test func `imports and creates wallets`() async throws {
        let imported = try await WalletCrypto.importWallet(name: " Mine ", password: "pw", phrase: "  TEST test test test test test test test test test test junk\n")
        #expect(imported.name == "Mine")
        #expect(imported.address == Fixtures.address)
        #expect(try await WalletCrypto.revealPhrase(imported.keystore, password: "pw") == Fixtures.phrase)

        let created = try await WalletCrypto.createWallet(name: "New", password: "pw")
        #expect(Address.isValid(created.address))
        #expect(created.meta.umVersion == WalletKeystore.currentUmVersion)
    }
}

@Suite("EIP-1559 signing")
struct SigningTests {
    struct Fixture: Decodable {
        struct Case: Decodable {
            struct Tx: Decodable {
                var chainId: Int
                var nonce: Int
                var to: String
                var value: String
                var gas: String
                var maxFeePerGas: String
                var maxPriorityFeePerGas: String
                var data: String?
            }

            var tx: Tx
            var raw: String
        }

        var privateKey: String
        var eth: Case
        var token: Case
    }

    @Test(arguments: ["eth", "token"])
    func `signs exactly like viem`(name: String) throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Fixtures.data("signed-transactions"))
        let expected = name == "eth" ? fixture.eth : fixture.token
        let tx = EIP1559Transaction(
            chainId: expected.tx.chainId,
            nonce: expected.tx.nonce,
            maxPriorityFeePerGas: try #require(BigUInt(expected.tx.maxPriorityFeePerGas)),
            maxFeePerGas: try #require(BigUInt(expected.tx.maxFeePerGas)),
            gasLimit: try #require(BigUInt(expected.tx.gas)),
            to: expected.tx.to,
            value: try #require(BigUInt(expected.tx.value)),
            data: expected.tx.data.flatMap { Data(hexString: $0) } ?? Data()
        )
        let signed = try tx.signed(with: try #require(Data(hexString: fixture.privateKey)))
        #expect(signed.rawHex == expected.raw)
        #expect(signed.hash.count == 66)
    }

    @Test func `encodes ERC-20 transfers like viem`() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Fixtures.data("signed-transactions"))
        let data = try Contracts.erc20Transfer(token: fixture.token.tx.to, to: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", amount: 1_234_567)
        #expect(data.hexString == fixture.token.tx.data)
    }

    @Test func `rejects an invalid recipient`() {
        let tx = EIP1559Transaction(chainId: 1, nonce: 0, maxPriorityFeePerGas: 1, maxFeePerGas: 1, gasLimit: 21_000, to: "vitalik.eth", value: 0)
        #expect(throws: EIP1559Transaction.Failure.self) { try tx.signed(with: Data(repeating: 1, count: 32)) }
    }
}

@Suite("Backup encryption")
struct BackupCryptoTests {
    @Test func `opens a backup made by the web wallet`() async throws {
        let backup = try WalletBackup.parse(Fixtures.data("backup"))
        let plaintext = try await BackupCrypto.decrypt(backup.sealed, password: Fixtures.password, iterations: backup.encryption.kdfIterations)
        #expect(plaintext == (try Fixtures.string("backup-plaintext")))
        let payload = try backup.open(plaintext)
        #expect(payload.wallets.first?.address == Fixtures.address)
        #expect(payload.activeWalletAddress == Fixtures.address)
    }

    @Test func `round-trips and rejects the wrong password`() async throws {
        let sealed = try await BackupCrypto.encrypt("こんにちは • привет", password: "p4$$w0rd🔑")
        #expect(Data(base64Encoded: sealed.kdfSalt)?.count == 16)
        #expect(Data(base64Encoded: sealed.iv)?.count == 12)
        #expect(try await BackupCrypto.decrypt(sealed, password: "p4$$w0rd🔑") == "こんにちは • привет")
        await #expect(throws: Keystore.Failure.wrongPassword) {
            try await BackupCrypto.decrypt(sealed, password: "wrong")
        }
    }

    @Test func `tampered ciphertext fails`() async throws {
        var sealed = try await BackupCrypto.encrypt("secret", password: "pw")
        sealed.data = Data(count: 32).base64EncodedString()
        await #expect(throws: (any Error).self) { try await BackupCrypto.decrypt(sealed, password: "pw") }
    }

    @Test func `each backup gets a fresh salt and IV`() async throws {
        let a = try await BackupCrypto.encrypt("same", password: "same")
        let b = try await BackupCrypto.encrypt("same", password: "same")
        #expect(a.kdfSalt != b.kdfSalt)
        #expect(a.iv != b.iv)
        #expect(a.data != b.data)
    }

    @Test func `backup file has the web wallet's shape`() async throws {
        let payload = WalletBackup.Payload(wallets: [], activeWalletAddress: nil, contacts: [], settings: WalletSettings(), activity: [])
        let backup = try await WalletBackup.make(payload, password: "pw", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let json = try #require(try JSONSerialization.jsonObject(with: backup.exportedJSON()) as? [String: Any])
        #expect(Set(json.keys) == ["format", "version", "createdAt", "encryption", "data"])
        #expect(json["format"] as? String == "um-wallet-backup")
        #expect(json["version"] as? Int == 1)
        #expect(json["createdAt"] as? String == "2023-11-14T22:13:20.000Z")
        let encryption = try #require(json["encryption"] as? [String: Any])
        #expect(encryption["kdf"] as? String == "PBKDF2")
        #expect(encryption["kdfHash"] as? String == "SHA-256")
        #expect(encryption["kdfIterations"] as? Int == 600_000)
        #expect(encryption["algorithm"] as? String == "AES-GCM-256")
    }
}
