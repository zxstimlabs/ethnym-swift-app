import EthnymKit
import SwiftUI

/// The tab structure follows the web wallet's navigation: Home (wallets and balances), Address Book,
/// Send, Activity and Backup. The tab bar fits five tabs, so Settings opens from the header instead.
struct RootView: View {
    enum Destination: Hashable {
        case home
        case addressBook
        case send
        case activity
        case backup
    }

    @Environment(AppModel.self) private var app
    @AppStorage("theme") private var theme: AppTheme = .system
    @State private var selection: Destination = Self.initialSelection

    /// `-tab send` and friends pick the starting tab in debug builds, for screenshots.
    private static var initialSelection: Destination {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), arguments.indices.contains(index + 1) {
            switch arguments[index + 1] {
            case "addressBook": return .addressBook
            case "send": return .send
            case "activity": return .activity
            case "backup": return .backup
            default: return .home
            }
        }
        #endif
        return .home
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: .home) {
                HomeView()
            } label: {
                TabLabel("Home", symbol: "wallet.bifold")
            }
            Tab(value: .addressBook) {
                AddressBookView()
            } label: {
                TabLabel("Address Book", symbol: "person.crop.rectangle.stack")
            }
            Tab(value: .send) {
                SendView()
            } label: {
                TabLabel("Send", symbol: "arrow.up.right")
            }
            Tab(value: .activity) {
                ActivityView()
            } label: {
                TabLabel("Activity", symbol: "list.bullet.rectangle")
            }
            Tab(value: .backup) {
                BackupView()
            } label: {
                TabLabel("Backup", symbol: "externaldrive")
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

/// A tab bar icon. The title isn't shown, but VoiceOver and the UI tests use it.
private struct TabLabel: View {
    let title: LocalizedStringKey
    let symbol: String

    init(_ title: LocalizedStringKey, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label { Text(title) } icon: { icon }
            .labelStyle(.iconOnly)
    }

    /// Before iOS 26 the tab bar places symbols as if a title sat under them, which leaves icon-only
    /// tabs against its top edge, but it centers plain images. So there the symbol is drawn into one
    /// at the bar's own symbol size, filled like the bar fills symbols when a fill exists (Send's arrow
    /// has none). iOS 26's Liquid Glass bar
    /// centers symbols itself.
    private var icon: Image {
        if #available(iOS 26, *) { return Image(systemName: symbol) }
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium, scale: .large)
        guard let image = UIImage(systemName: "\(symbol).fill", withConfiguration: configuration)
            ?? UIImage(systemName: symbol, withConfiguration: configuration)
        else {
            return Image(systemName: symbol)
        }
        let flat = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
        return Image(uiImage: flat.withRenderingMode(.alwaysTemplate))
    }
}

#if DEBUG
#Preview {
    RootView()
        .environment(DemoData.model())
        .font(.mono())
}
#endif
