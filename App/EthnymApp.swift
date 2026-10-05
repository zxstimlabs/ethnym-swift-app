import EthnymKit
import SwiftUI

@main
struct EthnymApp: App {
    @State private var model = Self.makeModel()

    init() {
        Theme.registerFonts()
        Theme.configureAppearance()
    }

    /// Mainnet, defaulting to the `ETHEREUM_RPC_URL` in App/Secrets.plist when that git-ignored file sets one.
    private static var chain: Chain {
        let secrets = Bundle.main.url(forResource: "Secrets", withExtension: "plist").flatMap { NSDictionary(contentsOf: $0) }
        return (secrets?["ETHEREUM_RPC_URL"] as? String).flatMap(Chain.mainnet.withDefaultRPC) ?? .mainnet
    }

    private static func makeModel() -> AppModel {
        let chain = Self.chain
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-demo") {
            return DemoData.model(chain: chain)
        }
        if arguments.contains("-empty") {
            return .inMemory(settings: WalletSettings(offlineMode: arguments.contains("-offline")), chain: chain)
        }
        #endif
        return .live(chain: chain)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .font(.mono())
        }
    }
}
