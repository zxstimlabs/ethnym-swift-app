import SwiftUI

/// Responds on touch-down: the button settles slightly into the page and springs back on release.
/// Critically damped, so there's no wobble; reduced motion keeps only the opacity change.
private struct PressFeedback: ViewModifier {
    let isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.25, bounce: 0), value: isPressed)
    }
}

/// Keeps the label on one line, clear of the edges, at any text size. Where it doesn't fit, as with
/// two buttons side by side under large Dynamic Type, it gives up side padding first, then its
/// icon, and only then shrinks the text, rather than breaking a word across lines. The icon sits
/// close to the title, so a pair of buttons keeps both icons as long as it can.
private struct FittingLabel: View {
    let label: ButtonStyleConfiguration.Label

    var body: some View {
        ViewThatFits(in: .horizontal) {
            label.padding(.horizontal, 20)
            label.padding(.horizontal, 12)
            label.labelStyle(.titleOnly).padding(.horizontal, 12)
            label.labelStyle(.titleOnly).minimumScaleFactor(0.5).padding(.horizontal, 8)
        }
        .labelStyle(.adaptive(iconOnly: false))
        .lineLimit(1)
        .padding(.vertical, 12)
    }
}

/// Solid black on light, solid white on dark. For the one primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        FittingLabel(label: configuration.label)
            .font(.mono(.body, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Color(.systemBackground))
            .background(Color.primary.opacity(isEnabled ? 1 : 0.3), in: .rect(cornerRadius: 14))
            .modifier(PressFeedback(isPressed: configuration.isPressed))
            .contentShape(.rect)
    }
}

/// An outlined companion to the primary style.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        FittingLabel(label: configuration.label)
            .font(.mono(.body, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Color.primary.opacity(isEnabled ? 1 : 0.3))
            .background(Theme.fill, in: .rect(cornerRadius: 14))
            .modifier(PressFeedback(isPressed: configuration.isPressed))
            .contentShape(.rect)
    }
}

/// Small text buttons such as 25% / 50% / Max, with press feedback but no chrome.
struct ChipButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(.footnote, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
            .background(isSelected ? Color.primary : Theme.fill, in: .capsule)
            .modifier(PressFeedback(isPressed: configuration.isPressed))
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == ChipButtonStyle {
    static var chip: ChipButtonStyle { ChipButtonStyle() }
    static func chip(selected: Bool) -> ChipButtonStyle { ChipButtonStyle(isSelected: selected) }
}

extension Animation {
    /// The house spring: critically damped, settles in about a third of a second.
    static let house = Animation.spring(duration: 0.35, bounce: 0)
}
