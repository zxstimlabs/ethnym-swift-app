// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EthnymKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "EthnymKit", targets: ["EthnymKit"]),
    ],
    dependencies: [
        // Ethereum: JSON-RPC, ABI, ENS, multicall, keccak, RLP and secp256k1 signing.
        .package(url: "https://github.com/argentlabs/web3.swift", from: "2.0.0"),
        // BIP-39 mnemonics.
        .package(url: "https://github.com/zcash/swift-bip39", from: "2.2.5"),
        // The same libsecp256k1 web3.swift links, used for BIP-32 child key derivation.
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", .upToNextMinor(from: "0.23.2"), traits: ["recovery"]),
        .package(url: "https://github.com/attaswift/BigInt", from: "5.7.0"),
    ],
    targets: [
        .target(
            name: "EthnymKit",
            dependencies: [
                .product(name: "web3.swift", package: "web3.swift"),
                .product(name: "MnemonicSwift", package: "swift-bip39"),
                .product(name: "libsecp256k1", package: "swift-secp256k1"),
                .product(name: "BigInt", package: "BigInt"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "EthnymKitTests",
            dependencies: ["EthnymKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ]
)
