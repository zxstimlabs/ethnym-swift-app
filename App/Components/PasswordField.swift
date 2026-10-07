import SwiftUI

/// A password field with a show/hide toggle. Never autocorrected or capitalized.
///
/// Both states carry the content type, so Password AutoFill offers saved passwords (`.password`)
/// or a strong one (`.newPassword`) whether or not the text is revealed. Pair a new password with
/// a `.username` field holding the wallet name, so a saved password is labelled with its wallet.
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
