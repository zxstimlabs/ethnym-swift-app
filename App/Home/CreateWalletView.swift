import EthnymKit
import SwiftUI

/// Generates a 12-word secret phrase and stores it encrypted with the password.
struct CreateWalletView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var touched: Set<Field> = []
    @State private var isWorking = false
    @State private var error: String?
    @State private var created = false

    enum Field {
        case name
        case password
        case confirmation
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Wallet name", text: $name)
                            .textContentType(.username)
                            .textInputAutocapitalization(.words)
                            .onChange(of: name) { touched.insert(.name) }
                        FieldHint(prompt: "Please enter a name", error: nameError, isTouched: touched.contains(.name))
                    }
                } header: {
                    SectionHeader("Name")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        PasswordField(title: "Strong password", text: $password, isNewPassword: true)
                            .onChange(of: password) { touched.insert(.password) }
                        FieldHint(prompt: "Please enter a password", error: passwordError, isTouched: touched.contains(.password))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        PasswordField(title: "Confirm password", text: $confirmation, isNewPassword: true)
                            .onChange(of: confirmation) { touched.insert(.confirmation) }
                        FieldHint(prompt: "Type the password again", error: confirmationError, isTouched: touched.contains(.confirmation))
                    }
                } header: {
                    SectionHeader("Password")
                } footer: {
                    Text("The password encrypts your secret phrase on this device. It can't be recovered, so keep it somewhere safe.")
                        .font(.mono(.caption))
                }

                Section {
                    Button(action: create) {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Create Wallet")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canSubmit)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if let error {
                        FieldHint(error, kind: .error)
                    } else {
                        Text("After creating it, reveal and write down the secret phrase from Manage › Export.")
                            .font(.mono(.caption))
                    }
                }
            }
            .navigationTitle("Create Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .interactiveDismissDisabled(isWorking)
            .sensoryFeedback(.success, trigger: created) { _, new in new }
            .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        }
    }

    private var nameError: FieldError? {
        ContactValidation.validateName(name).map { FieldError($0, isPrompt: true) }
    }

    private var passwordError: FieldError? {
        password.isEmpty ? FieldError("Please enter a password", isPrompt: true) : nil
    }

    private var confirmationError: FieldError? {
        if confirmation.isEmpty { return FieldError("Type the password again", isPrompt: true) }
        return confirmation == password ? nil : FieldError("Passwords don't match")
    }

    private var canSubmit: Bool {
        !isWorking && nameError == nil && passwordError == nil && confirmationError == nil
    }

    private func create() {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                let wallet = try await WalletCrypto.createWallet(name: name, password: password)
                app.wallets.add(wallet)
                if app.wallets.activeWallet == nil { app.wallets.select(wallet.id) }
                created = true
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
