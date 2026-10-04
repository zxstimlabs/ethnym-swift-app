import Foundation
import Testing

/// Files generated with the web wallet's own `ox` and `viem`, so these tests prove byte compatibility.
enum Fixtures {
    static let phrase = "test test test test test test test test test test test junk"
    static let password = "correct horse battery staple"
    /// Hardhat's first account for `phrase`.
    static let address = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func string(_ name: String) throws -> String {
        try #require(String(data: data(name), encoding: .utf8))
    }
}
