import EthnymKit
import SwiftUI

/// The line under a field. Before the field is touched it prompts; afterwards it shows the error,
/// or "ok" once the value is valid. Prompt-style errors stay neutral rather than turning red.
struct FieldHint: View {
    enum Kind: Equatable {
        case prompt
        case error
        case ok
        case progress
        case info
    }

    let text: String
    let kind: Kind

    init(_ text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    /// The standard prompt / error / ok sequence.
    init(prompt: String, error: FieldError?, isTouched: Bool, okText: String = "ok") {
        if !isTouched {
            self.init(prompt, kind: .prompt)
        } else if let error {
            self.init(error.message, kind: error.isPrompt ? .prompt : .error)
        } else {
            self.init(okText, kind: .ok)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch kind {
            case .ok:
                Image(systemName: "checkmark")
                    .font(.mono(.caption2, weight: .bold))
            case .error:
                Image(systemName: "exclamationmark.circle")
                    .font(.mono(.caption2, weight: .bold))
            case .progress:
                ProgressView()
                    .controlSize(.mini)
            case .prompt, .info:
                EmptyView()
            }
            Text(text)
                .font(kind == .prompt ? .monoItalic(.caption) : .mono(.caption))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .animation(.house, value: kind)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch kind {
        case .prompt, .info, .progress: .secondary
        case .error: .red
        case .ok: .primary
        }
    }
}
