import EthnymKit
import SwiftUI

@main
struct EthnymApp: App {
    @State private var model = Self.makeModel()

    init() {
        Theme.registerFonts()
        Theme.configureAppearance()
    }

    private static func makeModel() -> AppModel {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-demo") {
            return DemoData.model()
        }
        if arguments.contains("-empty") {
            return .inMemory(settings: WalletSettings(offlineMode: arguments.contains("-offline")))
        }
        #endif
        return .live()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .font(.mono())
        }
    }
}
