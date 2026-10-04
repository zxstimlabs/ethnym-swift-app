import SwiftUI

/// A password field with a show/hide toggle. Never autocorrected or capitalized.
struct PasswordField: View {
    let title: String
    @Binding var text: String
    var isNewPassword = false

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .focused($isFocused)
            .textContentType(isNewPassword ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.mono(.body))

            Button(isRevealed ? "Hide password" : "Show password", systemImage: isRevealed ? "eye.slash" : "eye") {
                let wasFocused = isFocused
                isRevealed.toggle()
                isFocused = wasFocused
            }
            .labelStyle(.iconOnly)
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
        }
    }
}
