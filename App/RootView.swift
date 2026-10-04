import EthnymKit
import SwiftUI

/// The tab structure follows the web wallet's navigation: Home (wallets, balances, send),
/// Address Book, Activity, Backup and Settings.
struct RootView: View {
    enum Destination: Hashable {
        case home
        case addressBook
        case activity
        case backup
        case settings
    }

    @Environment(AppModel.self) private var app
    @AppStorage("theme") private var theme: AppTheme = .system
    @State private var selection: Destination = Self.initialSelection

    /// `-tab settings` and friends pick the starting tab in debug builds, for screenshots.
    private static var initialSelection: Destination {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), arguments.indices.contains(index + 1) {
            switch arguments[index + 1] {
            case "addressBook": return .addressBook
            case "activity": return .activity
            case "backup": return .backup
            case "settings": return .settings
            default: return .home
            }
        }
        #endif
        return .home
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "wallet.bifold", value: .home) {
                HomeView()
            }
            Tab("Address Book", systemImage: "person.crop.rectangle.stack", value: .addressBook) {
                AddressBookView()
            }
            Tab("Activity", systemImage: "list.bullet.rectangle", value: .activity) {
                ActivityView()
            }
            Tab("Backup", systemImage: "externaldrive", value: .backup) {
                BackupView()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .tint(.primary)
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear { theme.apply(animated: false) }
        .onChange(of: theme) { theme.apply(animated: true) }
        .task(id: app.balanceContext) {
            await app.refreshBalances()
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .environment(DemoData.model())
        .font(.mono())
}
#endif
