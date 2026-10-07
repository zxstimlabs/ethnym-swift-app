# ETHnym

Native iOS Ethereum wallet. SwiftUI, the iPhone counterpart of `ethnym-android-app`.

It has the same features and structure as the UnitMetal web wallet: wallets encrypted from a BIP-39 secret phrase, sending ETH, ERC-20 tokens and ERC-721 NFTs, signing transaction JSON (offline too), ENS, QR scanning, an address book, local activity history, keystore tools, encrypted full-device backups and custom RPC endpoints. Keystores and backups use the web wallet's file formats, so they move between the two apps.

## Requirements

- iOS 18 or later.
- Xcode 16 or later. The project is built with Xcode 27.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Setup

```sh
brew install xcodegen   # once
xcodegen generate       # creates Ethnym.xcodeproj from project.yml
open Ethnym.xcodeproj
```

Run the `Ethnym` scheme.

Local settings live in `App/Secrets.plist`, which is git-ignored. `xcodegen generate` creates it from the committed `App/Secrets.example.plist` when it's missing, and never overwrites it. Set `ETHEREUM_RPC_URL` there to use your own RPC endpoint as the default instead of `ethereum-rpc.publicnode.com`. Add any new key to the example too, with an empty value.

The URL is built into the app, so anyone with the build can read it. RPCs saved in Settings still take priority, and "Reset to Default" goes back to this one.

The `.xcodeproj` is generated and not committed. Edit `project.yml` instead, and run `xcodegen generate` again after adding or removing files.

## Tests

Package tests, including compatibility checks against keystores, backups and signed transactions produced by the web wallet's own `ox` and `viem`:

```sh
cd Packages/EthnymKit && swift test
ETHNYM_LIVE_TESTS=1 swift test   # also hits a public mainnet RPC
```

UI tests, which tour every screen and drive create, import and offline signing:

```sh
xcodebuild test -project Ethnym.xcodeproj -scheme Ethnym -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Debug builds accept launch arguments that swap in an in-memory model, leaving the Keychain and files untouched: `-demo` (sample wallets, contacts and activity), `-empty`, `-offline` (with `-empty`), and `-tab addressBook|send|activity|backup`.

## Layout

- `project.yml`: XcodeGen spec. Targets `Ethnym` (bundle ID `com.ethnym`, iPhone only) and `EthnymUITests`.
- `App/`: the SwiftUI app, one folder per tab plus shared pieces.
  - `Home/`: wallet picker, balances, receive, and create / import / export / delete.
  - `Send/`: the ETH, token, NFT and Sign forms, pickers and transaction status.
  - `AddressBook/`, `Activity/`, `Backup/`: the other tabs. `Settings/` opens from the header, which every tab shares (`Components/AppHeader.swift`).
  - `Assets.xcassets/Logo.imageset`: the header logo, `ethnym-symbol-dark.svg` (black tile, light mode) and `ethnym-symbol-light.svg` (white tile, dark mode).
  - `Components/`, `Theme/`: shared views, JetBrains Mono and the black-and-white theme.
  - `Fonts/`: JetBrains Mono (SIL Open Font License, see `OFL.txt`).
  - `AppIcon.icon`: the app icon, an Icon Composer file. Xcode generates the flat icons for iOS 18 from it.
  - `Preview Content/`: demo data for previews and `-demo`, debug builds only.
- `Packages/EthnymKit/`: all non-UI logic, with tests. It also lists macOS as a platform so `swift test` runs on the Mac.
  - `Crypto/`: keystores, backups, BIP-39 / BIP-32 derivation and wallet operations.
  - `Ethereum/`: the RPC service, EIP-1559 transactions, ABI call data and units.
  - `Sending/`: the send pipeline, ENS resolution, gas presets and receipt monitoring.
  - `Stores/`, `Persistence/`, `Models/`, `Utilities/`.
- `UITests/`: XCUITest flows.

## Cryptography

Nothing is implemented from scratch. The pieces come from:

- [web3.swift](https://github.com/argentlabs/web3.swift): JSON-RPC, ABI encoding, ENS (including off-chain lookups), multicall, Keccak-256, RLP and secp256k1 signing.
- [MnemonicSwift](https://github.com/zcash/swift-bip39): BIP-39 phrase generation and checksum validation.
- libsecp256k1 (the copy web3.swift links) and CryptoKit's HMAC-SHA512: BIP-32 child keys.
- CommonCrypto: PBKDF2 and AES-128-CTR for v3 keystores. CryptoKit: AES-GCM-256 for backups.

web3.swift has no BIP-39, BIP-32 or EIP-1559 support, so those are composed from the primitives above and checked against BIP-32 test vectors and transactions signed by viem.

## Storage

- Wallet keystores: the Keychain, this device only, readable while unlocked. They're already encrypted with the wallet password.
- Contacts, settings, custom tokens and activity: JSON in Application Support, encrypted at rest while the device is locked.

Keystores don't travel to a new phone through iCloud. Export them, or make a local device backup, to move wallets.
