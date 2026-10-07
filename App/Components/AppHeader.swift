import SwiftUI

/// The header every tab shares: the logo on the left, Settings on the right, and nothing else, so
/// nothing in it is easy to hit by accident. Log Out lives in Settings. Settings lives here because
/// the tab bar has room for five tabs, not six.
struct AppHeader: ToolbarContent {
    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarLeading) { AppLogo() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { AppLogo() }
        }
        ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
    }
}

extension View {
    /// Names a tab's root screen for VoiceOver and back buttons without showing a page title. Its
    /// sections carry their own headers instead, like the web wallet's cards.
    func tabTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
    }
}

/// The ETHnym logo, drawn as is. The Logo image set has a light and a dark SVG.
private struct AppLogo: View {
    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: 32, height: 32)
            .accessibilityLabel("ETHnym")
            .accessibilityAddTraits(.isImage)
    }
}

/// A default toolbar button: Liquid Glass on iOS 26 and later, a plain symbol before.
private struct SettingsButton: View {
    @State private var isPresented = false

    var body: some View {
        Button("Settings", systemImage: "gearshape") { isPresented = true }
            .sheet(isPresented: $isPresented) { SettingsView() }
    }
}
