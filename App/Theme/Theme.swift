import CoreText
import SwiftUI
import UIKit

/// JetBrains Mono on a black-and-white palette.
enum Theme {
    /// Registers the bundled JetBrains Mono faces. Call before any view or appearance proxy uses them.
    static func registerFonts() {
        let urls = JetBrainsMono.allCases.compactMap { Bundle.main.url(forResource: $0.rawValue, withExtension: "ttf") }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    /// Fonts for the UIKit chrome SwiftUI doesn't reach: navigation bars, tab bar, segmented pickers.
    static func configureAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithDefaultBackground()
        navigation.titleTextAttributes = [.font: JetBrainsMono.semiBold.uiFont(.headline)]
        navigation.largeTitleTextAttributes = [.font: JetBrainsMono.bold.uiFont(.largeTitle, size: 30)]
        let buttons = UIBarButtonItemAppearance()
        buttons.normal.titleTextAttributes = [.font: JetBrainsMono.regular.uiFont(.body)]
        navigation.buttonAppearance = buttons
        navigation.doneButtonAppearance = buttons
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.titleTextAttributes = navigation.titleTextAttributes
        scrollEdge.largeTitleTextAttributes = navigation.largeTitleTextAttributes
        scrollEdge.buttonAppearance = buttons
        scrollEdge.doneButtonAppearance = buttons
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdge

        // Black on light, white on dark, everywhere UIKit draws a tint: alerts, menus, bars.
        UIWindow.appearance().tintColor = .label
        UITabBar.appearance().tintColor = .label

        let tabItem = UITabBarItemAppearance()
        tabItem.normal.titleTextAttributes = [.font: JetBrainsMono.medium.uiFont(.caption2), .foregroundColor: UIColor.secondaryLabel]
        tabItem.normal.iconColor = .secondaryLabel
        tabItem.selected.titleTextAttributes = [.font: JetBrainsMono.semiBold.uiFont(.caption2), .foregroundColor: UIColor.label]
        tabItem.selected.iconColor = .label
        let tabBar = UITabBarAppearance()
        tabBar.configureWithDefaultBackground()
        tabBar.stackedLayoutAppearance = tabItem
        tabBar.inlineLayoutAppearance = tabItem
        tabBar.compactInlineLayoutAppearance = tabItem
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
        UITabBarItem.appearance().setTitleTextAttributes([.font: JetBrainsMono.medium.uiFont(.caption2)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: JetBrainsMono.medium.uiFont(.footnote)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: JetBrainsMono.semiBold.uiFont(.footnote)], for: .selected)
    }

    /// The switch track. White in dark mode would hide the white thumb, so dark mode uses gray.
    static let toggleTint = Color(UIColor { $0.userInterfaceStyle == .dark ? .systemGray : .label })

    /// Fills behind grouped content and code blocks.
    static let fill = Color(.secondarySystemFill)
}

enum JetBrainsMono: String, CaseIterable {
    case regular = "JetBrainsMono-Regular"
    case italic = "JetBrainsMono-Italic"
    case medium = "JetBrainsMono-Medium"
    case semiBold = "JetBrainsMono-SemiBold"
    case bold = "JetBrainsMono-Bold"

    init(_ weight: Font.Weight) {
        switch weight {
        case .medium: self = .medium
        case .semibold: self = .semiBold
        case .bold, .heavy, .black: self = .bold
        default: self = .regular
        }
    }

    func uiFont(_ style: UIFont.TextStyle, size: CGFloat? = nil) -> UIFont {
        let base = UIFont(name: rawValue, size: size ?? Font.TextStyle(style).monoSize) ?? .preferredFont(forTextStyle: style)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}

extension Font {
    /// JetBrains Mono at a text style's size, scaling with Dynamic Type.
    static func mono(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .custom(JetBrainsMono(weight).rawValue, size: style.monoSize, relativeTo: style)
    }

    /// The italic face, for field hints.
    static func monoItalic(_ style: Font.TextStyle = .footnote) -> Font {
        .custom(JetBrainsMono.italic.rawValue, size: style.monoSize, relativeTo: style)
    }

    /// A fixed size that still scales with Dynamic Type, for the big amount fields.
    static func mono(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(JetBrainsMono(weight).rawValue, size: size, relativeTo: style)
    }
}

extension Font.TextStyle {
    /// Monospaced glyphs run wide, so each style sits a step below the system size.
    var monoSize: CGFloat {
        switch self {
        case .largeTitle: 31
        case .title: 25
        case .title2: 20
        case .title3: 18
        case .headline: 15
        case .body: 15
        case .callout: 14
        case .subheadline: 13
        case .footnote: 12
        case .caption: 11
        case .caption2: 10
        default: 15
        }
    }

    init(_ style: UIFont.TextStyle) {
        switch style {
        case .largeTitle: self = .largeTitle
        case .title1: self = .title
        case .title2: self = .title2
        case .title3: self = .title3
        case .headline: self = .headline
        case .callout: self = .callout
        case .subheadline: self = .subheadline
        case .footnote: self = .footnote
        case .caption1: self = .caption
        case .caption2: self = .caption2
        default: self = .body
        }
    }
}

/// The appearance the user picked in Settings.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Applies to every window with a short cross-fade, so the switch doesn't flash.
    @MainActor
    func apply(animated: Bool) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != interfaceStyle {
                if animated {
                    UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                        window.overrideUserInterfaceStyle = interfaceStyle
                    }
                } else {
                    window.overrideUserInterfaceStyle = interfaceStyle
                }
            }
        }
    }
}
