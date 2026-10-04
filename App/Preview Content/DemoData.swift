#if DEBUG
import EthnymKit
import Foundation

/// Sample data for SwiftUI previews and the `-demo` launch argument. Debug builds only.
///
/// The wallet is the public Hardhat test phrase ("test test … junk"), password
/// "correct horse battery staple". Never send real funds to it.
enum DemoData {
    static let hardhat: WalletKeystore = {
        let json = #"{"crypto":{"cipher":"aes-128-ctr","ciphertext":"1f2fe56d94ef66c1cbc2da3621b97b67052999c093a7d3cb2f96434862bba5638b875ae049e89d74293f02a3d1b588e945ae31b0909c57c9a806b9","cipherparams":{"iv":"248a1a20c8af2158e16ba888a87a78c1"},"kdf":"pbkdf2","kdfparams":{"c":262144,"dklen":32,"prf":"hmac-sha256","salt":"49a9886a0ae51c87091930e0417802d4d9d3d2ca5d1b08b45f24755e9b5287a4"},"mac":"957e8b1223d667f843c1593d33e0759b7a038d4131876da4751a678556ee154a"},"id":"8040b190-c567-4e54-a229-17bd073e4c2a","version":3,"meta":{"type":"password-keystore-seedphrase","note":"the 12 words secret phrase (aka mnemonic phrase) is encrypted with the password using the keystore encryption process","umVersion":"0.0.1"},"name":"Test Wallet","address":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"}"#
        return try! WalletKeystore.parse(Data(json.utf8))[0]
    }()

    /// Shows a well-funded address. It can't sign: the keystore belongs to another address.
    static let watchOnly: WalletKeystore = {
        var wallet = hardhat
        wallet.id = "00000000-0000-4000-8000-000000000001"
        wallet.name = "vitalik.eth (view only)"
        wallet.address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        return wallet
    }()

    static let contacts = [
        Contact(address: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", name: "Alice", chain: 1, metadata: .init(tags: ["team", "defi"], note: "Treasury multisig signer")),
        Contact(address: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", name: "Bob", chain: nil, metadata: .init(tags: ["personal"], note: "")),
    ]

    static let activity = [
        ActivityRecord(id: 1, txHash: "0x5c504ed432cb51138bcf09aa5e8a410dd4a1e204ef84bfed1be16dfba1b22060", from: hardhat.address, to: contacts[0].address, chainId: 1, type: .native, nativeValue: "250000000000000000", timestamp: 1_759_000_000_000),
        ActivityRecord(id: 2, txHash: "0x9fc76417374aa880d4449a1f7f31ec597f00b1f6f3dd2d66f4c9c6c445836d8b", from: hardhat.address, to: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", chainId: 1, type: .erc20, tokenValue: "125000000", tokenAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", tokenSymbol: "USDC", tokenDecimals: 6, ensName: "vitalik.eth", timestamp: 1_759_100_000_000),
    ]

    @MainActor
    static func model(wallets: [WalletKeystore] = [watchOnly, hardhat]) -> AppModel {
        .inMemory(wallets: wallets, contacts: contacts, activity: activity)
    }
}
#endif
