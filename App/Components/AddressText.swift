import EthnymKit
import SwiftUI

/// How full addresses are set. A setting will choose; until then they're continuous.
enum AddressFormat {
    /// `0xf39Fd6e51aad88F6…`, unbroken.
    case continuous
    /// `0x f39F d6e5 1aad 88F6 …`, in groups of four with the prefix dimmed.
    case chunked
}

extension EnvironmentValues {
    @Entry var addressFormat: AddressFormat = .continuous
}

/// A full address, never truncated, in the `addressFormat` from the environment. The text is
/// selectable.
struct AddressText: View {
    let address: String
    var style: Font.TextStyle = .footnote
    var weight: Font.Weight = .regular

    @Environment(\.addressFormat) private var format

    var body: some View {
        Text(format == .chunked ? chunked : AttributedString(address))
            .font(.mono(style, weight: weight))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(address)
    }

    private var chunked: AttributedString {
        guard address.isHexAddress || (address.hasPrefix("0x") && address.count > 10) else {
            return AttributedString(address)
        }
        var result = AttributedString()
        for (index, chunk) in Address.chunks(address).enumerated() {
            var part = AttributedString(index == 0 ? chunk : " " + chunk)
            if index == 0 { part.foregroundColor = .secondary }
            result += part
        }
        return result
    }
}

/// Section headers in the mono face, without the system's uppercasing.
struct SectionHeader: View {
    let title: String
    var systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.mono(.footnote, weight: .semibold))
        // Concrete black or white: list headers resolve the hierarchical `.primary` to their gray.
        .foregroundStyle(Color.primary)
        .textCase(nil)
    }
}

/// A small outlined tag: "verified", "current", "coming soon".
struct Tag: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.mono(.caption2, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay(.secondary.opacity(0.5), in: .rect(cornerRadius: 5).stroke(lineWidth: 1))
    }
}

extension View {
    /// A gentle pulse for placeholders while loading. Static when Reduce Motion is on.
    func loadingPulse(_ active: Bool = true) -> some View {
        modifier(LoadingPulse(active: active))
    }
}

private struct LoadingPulse: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.phaseAnimator([1.0, 0.45]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.8)
            }
        } else {
            content.opacity(active ? 0.6 : 1)
        }
    }
}

/// `ContentUnavailableView` in the mono face. The system view otherwise falls back to SF.
struct EmptyState<Actions: View>: View {
    let title: String
    let systemImage: String
    let message: String
    let actions: Actions

    init(_ title: String, systemImage: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
                    .font(.mono(.title3, weight: .semibold))
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            Text(message)
                .font(.mono(.footnote))
        } actions: {
            actions
        }
    }
}
