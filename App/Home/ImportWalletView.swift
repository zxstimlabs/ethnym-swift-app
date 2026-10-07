import EthnymKit
import SwiftUI
import UniformTypeIdentifiers

/// Imports wallets from a secret phrase, a keystore file, or pasted keystore JSON.
struct ImportWalletView: View {
    enum Method: String, CaseIterable, Identifiable {
        case phrase = "Phrase"
        case file = "File"
        case paste = "Paste"

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var method: Method = .phrase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Import with", selection: $method.animation(.house)) {
                        ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                switch method {
                case .phrase: PhraseImport()
                case .file: KeystoreFileImport()
                case .paste: KeystorePasteImport()
                }
            }
            .navigationTitle("Import Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .sensoryFeedback(.selection, trigger: method)
        }
    }
}

// MARK: - Secret phrase

private struct PhraseImport: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var password = ""
    @State private var phrase = ""
    @State private var touched: Set<String> = []
    @State private var isWorking = false
    @State private var error: String?
    @State private var imported = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Wallet name", text: $name)
                    .textContentType(.username)
                    .textInputAutocapitalization(.words)
                    .onChange(of: name) { touched.insert("name") }
                FieldHint(prompt: "Please enter a name", error: ContactValidation.validateName(name).map { FieldError($0, isPrompt: true) }, isTouched: touched.contains("name"))
            }
            VStack(alignment: .leading, spacing: 8) {
                PasswordField(title: "Strong password", text: $password, isNewPassword: true)
                    .onChange(of: password) { touched.insert("password") }
                FieldHint(prompt: "Please enter a password", error: password.isEmpty ? FieldError("Please enter a password", isPrompt: true) : nil, isTouched: touched.contains("password"))
            }
        } header: {
            SectionHeader("Wallet")
        }

        Section {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Enter your secret phrase", text: $phrase, axis: .vertical)
                    .lineLimit(3 ... 6)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .onChange(of: phrase) { touched.insert("phrase") }
                FieldHint(prompt: "Please enter a secret phrase", error: phraseError, isTouched: touched.contains("phrase"))
            }
        } header: {
            SectionHeader("Secret phrase")
        } footer: {
            Text("12 to 24 words, separated by spaces. The first Ethereum account (m/44'/60'/0'/0/0) is imported.")
                .font(.mono(.caption))
        }

        Section {
            Button(action: importPhrase) {
                if isWorking { ProgressView() } else { Text("Import Wallet") }
            }
            .buttonStyle(.primary)
            .disabled(!canSubmit)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            if let error { FieldHint(error, kind: .error) }
        }
        .sensoryFeedback(.success, trigger: imported) { _, new in new }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
    }

    private var phraseError: FieldError? {
        let normalized = HDWallet.normalize(phrase)
        if normalized.isEmpty { return FieldError("Please enter a secret phrase", isPrompt: true) }
        do {
            try HDWallet.validate(normalized)
            return nil
        } catch {
            return FieldError(error.localizedDescription)
        }
    }

    private var canSubmit: Bool {
        !isWorking && ContactValidation.validateName(name) == nil && !password.isEmpty && phraseError == nil
    }

    private func importPhrase() {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                let wallet = try await WalletCrypto.importWallet(name: name, password: password, phrase: phrase)
                if app.wallets.add(wallet) {
                    imported = true
                    dismiss()
                } else {
                    error = "This wallet is already imported."
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Keystore file and pasted JSON

private struct KeystoreFileImport: View {
    @State private var isPicking = false
    @State private var wallets: [WalletKeystore] = []
    @State private var filename: String?
    @State private var error: String?

    var body: some View {
        Section {
            Button {
                isPicking = true
            } label: {
                Label(filename ?? "Choose keystore file…", systemImage: "doc.badge.plus")
            }
        } header: {
            SectionHeader("Keystore file")
        } footer: {
            if let error {
                FieldHint(error, kind: .error)
            } else {
                Text("A .json keystore exported from ETHnym or the UnitMetal web wallet. It holds one wallet or a list of them.")
                    .font(.mono(.caption))
            }
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.json, .plainText]) { result in
            do {
                let url = try result.get()
                filename = url.lastPathComponent
                wallets = try WalletKeystore.parse(url.readSecurityScoped())
                error = nil
            } catch {
                wallets = []
                self.error = error.localizedDescription
            }
        }

        KeystoreImportSummary(wallets: wallets)
    }
}

private struct KeystorePasteImport: View {
    @State private var text = ""

    var body: some View {
        Section {
            TextField("Paste your keystore file content here", text: $text, axis: .vertical)
                .font(.mono(.caption))
                .lineLimit(4 ... 10)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            PasteButton(payloadType: String.self) { strings in
                if let first = strings.first { text = first }
            }
            .labelStyle(.titleAndIcon)
        } header: {
            SectionHeader("Keystore contents")
        } footer: {
            if !text.isEmpty, parsed == nil {
                FieldHint(KeystoreImportError.invalidFormat.localizedDescription, kind: .error)
            }
        }

        KeystoreImportSummary(wallets: parsed ?? [])
    }

    private var parsed: [WalletKeystore]? {
        try? WalletKeystore.parse(Data(text.utf8))
    }
}

/// Lists what a keystore contains and imports it. No password is needed: the keystores stay encrypted.
private struct KeystoreImportSummary: View {
    let wallets: [WalletKeystore]
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        if !wallets.isEmpty {
            Section {
                ForEach(wallets, id: \.id) { wallet in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(wallet.name)
                            .font(.mono(.callout, weight: .medium))
                        AddressText(address: wallet.address, style: .caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                SectionHeader(wallets.count == 1 ? "1 wallet found" : "\(wallets.count) wallets found")
            }
            .transition(.opacity)

            Section {
                Button("Import \(wallets.count == 1 ? "Wallet" : "\(wallets.count) Wallets")") {
                    let result = app.wallets.add(contentsOf: wallets)
                    if result.added > 0 {
                        dismiss()
                    } else {
                        message = "Already imported."
                    }
                }
                .buttonStyle(.primary)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if let message { FieldHint(message, kind: .info) }
            }
        }
    }
}
