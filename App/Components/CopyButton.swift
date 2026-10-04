import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Copies text and confirms with a checkmark and a light haptic. Secrets are copied local-only
/// (no Universal Clipboard) and expire from the pasteboard after a minute.
struct CopyButton: View {
    let text: String
    var title: String?
    var isSecret = false

    @State private var copied = false

    var body: some View {
        Button {
            Pasteboard.copy(text, isSecret: isSecret)
            copied = true
        } label: {
            Label(copied ? "Copied" : (title ?? "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .labelStyle(.adaptive(iconOnly: title == nil))
        .disabled(text.isEmpty)
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .accessibilityLabel(copied ? "Copied" : (title ?? "Copy"))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

enum Pasteboard {
    static func copy(_ text: String, isSecret: Bool) {
        let item = [UTType.plainText.identifier: text]
        let options: [UIPasteboard.OptionsKey: Any] = isSecret
            ? [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(60)]
            : [:]
        UIPasteboard.general.setItems([item], options: options)
    }
}

/// Icon-only or title-and-icon, chosen at the call site.
struct AdaptiveLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
        }
    }
}

extension LabelStyle where Self == AdaptiveLabelStyle {
    static func adaptive(iconOnly: Bool) -> AdaptiveLabelStyle { AdaptiveLabelStyle(iconOnly: iconOnly) }
}
