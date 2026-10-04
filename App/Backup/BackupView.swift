import EthnymKit
import SwiftUI

/// Keystore tools, encrypted device backups and cloud sync.
struct BackupView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        KeystoreToolView()
                    } label: {
                        BackupRow(title: "Keystore", systemImage: "key", detail: "Encrypt any secret phrase to a keystore, or decrypt a keystore back to its phrase.")
                    }
                    NavigationLink {
                        LocalBackupView()
                    } label: {
                        BackupRow(title: "Local device backup", systemImage: "externaldrive", detail: "Export wallets, contacts, settings and activity as one encrypted file.")
                    }
                    NavigationLink {
                        CloudSyncView()
                    } label: {
                        BackupRow(title: "Cloud sync", systemImage: "icloud", detail: "Coming soon.")
                    }
                }
            }
            .navigationTitle("Backup")
        }
    }
}

private struct BackupRow: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.mono(.callout, weight: .semibold))
                Text(detail)
                    .font(.mono(.caption))
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Keystore tool

/// The standalone keystore utility: phrase to keystore, and keystore to phrase.
struct KeystoreToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case encrypt = "Encrypt"
        case decrypt = "Decrypt"

        var id: Self { self }
    }

    @State private var mode: Mode = .encrypt

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode.animation(.house)) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text(mode == .encrypt ? "Convert any secret phrase to a keystore." : "Decrypt any keystore to its secret phrase.")
                    .font(.mono(.caption))
            }

            switch mode {
            case .encrypt: EncryptPhraseSections()
            case .decrypt: DecryptKeystoreSections()
            }
        }
        .navigationTitle("Keystore")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: mode)
    }
}

private struct EncryptPhraseSections: View {
    @State private var name = ""
    @State private var password = ""
    @State private var phrase = ""
    @State private var output: WalletKeystore?
    @State private var isWorking = false
    @State private var error: String?
    @State private var export: PendingExport?

    var body: some View {
        Section {
            TextField("Wallet name", text: $name)
                .textInputAutocapitalization(.words)
            PasswordField(title: "Strong password", text: $password, isNewPassword: true)
            TextField("Secret phrase", text: $phrase, axis: .vertical)
                .lineLimit(2 ... 5)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
        } header: {
            SectionHeader("Input")
        } footer: {
            if let error { FieldHint(error, kind: .error) }
        }

        Section {
            HStack(spacing: 10) {
                Button("Reset") {
                    withAnimation(.house) {
                        name = ""
                        password = ""
                        phrase = ""
                        output = nil
                        error = nil
                    }
                }
                .buttonStyle(.secondary)
                .frame(maxWidth: 110)
                Button(action: encrypt) {
                    if isWorking { ProgressView().tint(Color(.systemBackground)) } else { Text("Backup") }
                }
                .buttonStyle(.primary)
                .disabled(name.trimmed.isEmpty || password.isEmpty || phrase.trimmed.isEmpty || isWorking)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            if let output, let json = try? output.exportedJSON() {
                let text = String(decoding: json, as: UTF8.self)
                Text("Copy and save this backup keystore somewhere secure.")
                    .font(.mono(.footnote))
                CodeBlock(text: text)
                HStack(spacing: 16) {
                    CopyButton(text: text, title: "Copy")
                    Button("Save…", systemImage: "square.and.arrow.down") {
                        export = PendingExport(file: JSONFile(data: json), filename: "\(output.name.replacingOccurrences(of: " ", with: "-"))-DO_NOT_DELETE.json")
                    }
                    Spacer()
                    Button("Clear", systemImage: "xmark") {
                        withAnimation(.house) { self.output = nil }
                    }
                }
                .buttonStyle(.borderless)
                .font(.mono(.footnote))
            } else {
                Text("No backup keystore")
                    .font(.mono(.footnote))
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader("Output")
        }
        .fileExporter(
            isPresented: Binding(get: { export != nil }, set: { if !$0 { export = nil } }),
            document: export?.file,
            contentType: .json,
            defaultFilename: export?.filename
        ) { _ in }
    }

    private func encrypt() {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                let keystore = try await WalletCrypto.backupKeystore(name: name, password: password, phrase: phrase)
                withAnimation(.house) {
                    output = keystore
                    phrase = ""
                    password = ""
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct DecryptKeystoreSections: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var keystoreText = ""
    @State private var password = ""
    @State private var phrase: String?
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        Section {
            TextField("Keystore JSON", text: $keystoreText, axis: .vertical)
                .font(.mono(.caption))
                .lineLimit(4 ... 10)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            PasteButton(payloadType: String.self) { strings in
                if let first = strings.first { keystoreText = first }
            }
            .labelStyle(.titleAndIcon)
            PasswordField(title: "Password", text: $password)
        } header: {
            SectionHeader("Input")
        } footer: {
            if let error { FieldHint(error, kind: .error) }
        }

        Section {
            HStack(spacing: 10) {
                Button("Reset") {
                    withAnimation(.house) {
                        keystoreText = ""
                        password = ""
                        phrase = nil
                        error = nil
                    }
                }
                .buttonStyle(.secondary)
                .frame(maxWidth: 110)
                Button(action: decrypt) {
                    if isWorking { ProgressView().tint(Color(.systemBackground)) } else { Text("Decrypt") }
                }
                .buttonStyle(.primary)
                .disabled(keystoreText.trimmed.isEmpty || password.isEmpty || isWorking)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            if let phrase {
                PhraseGrid(phrase: phrase)
                HStack {
                    CopyButton(text: phrase, title: "Copy", isSecret: true)
                    Spacer()
                    Button("Hide", systemImage: "eye.slash") {
                        withAnimation(.house) { self.phrase = nil }
                    }
                }
                .buttonStyle(.borderless)
                .font(.mono(.footnote))
            } else {
                Text("No secret phrase")
                    .font(.mono(.footnote))
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader("Output")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { phrase = nil }
        }
        .onDisappear { phrase = nil }
    }

    private func decrypt() {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                let keystore = try JSONDecoder().decode(KeystoreV3.self, from: Data(keystoreText.utf8))
                let revealed = try await WalletCrypto.revealPhrase(keystore, password: password)
                password = ""
                withAnimation(.house) { phrase = revealed }
            } catch is DecodingError {
                error = KeystoreImportError.invalidFormat.localizedDescription
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Monospaced, selectable, scrollable text such as keystore JSON.
struct CodeBlock: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.mono(.caption2))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 220)
        .background(Theme.fill, in: .rect(cornerRadius: 10))
    }
}

// MARK: - Local device backup

/// Exports everything as one password-encrypted file.
struct LocalBackupView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case export = "Export"
        case importBackup = "Import"

        var id: Self { self }
    }

    @Environment(AppModel.self) private var app
    @State private var mode: Mode = .export
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var export: PendingExport?
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode.animation(.house)) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            switch mode {
            case .export:
                Section {
                    LabeledContent("Wallets", value: "\(app.wallets.wallets.count)")
                    LabeledContent("Contacts", value: "\(app.contacts.contacts.count)")
                    LabeledContent("Activity records", value: "\(app.activity.records.count)")
                } header: {
                    SectionHeader("Contents")
                } footer: {
                    Text("Encrypted with AES-GCM 256-bit and PBKDF2 (600,000 iterations). Keep the password safe: it can't be recovered. The file also opens in the UnitMetal web wallet.")
                        .font(.mono(.caption))
                }

                Section {
                    PasswordField(title: "Backup password", text: $password, isNewPassword: true)
                } header: {
                    SectionHeader("Password")
                } footer: {
                    if let error {
                        FieldHint(error, kind: .error)
                    } else if saved {
                        FieldHint("Backup saved", kind: .ok)
                    }
                }

                Section {
                    Button(action: makeBackup) {
                        if isWorking {
                            ProgressView().tint(Color(.systemBackground))
                        } else {
                            Label("Save Backup", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(password.isEmpty || isWorking)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            case .importBackup:
                EmptyState("Coming soon", systemImage: "square.and.arrow.down", message: "Restoring from a backup file isn't available yet.")
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Local Device Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: Binding(get: { export != nil }, set: { if !$0 { export = nil } }),
            document: export?.file,
            contentType: .json,
            defaultFilename: export?.filename
        ) { result in
            switch result {
            case .success:
                saved = true
                password = ""
            case let .failure(error):
                self.error = error.localizedDescription
            }
        }
        .sensoryFeedback(.success, trigger: saved) { _, new in new }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
    }

    private func makeBackup() {
        isWorking = true
        error = nil
        saved = false
        let payload = WalletBackup.Payload(
            wallets: app.wallets.wallets,
            activeWalletAddress: app.wallets.activeWallet?.address,
            contacts: app.contacts.contacts,
            settings: app.settings.settings,
            activity: app.activity.records
        )
        Task {
            defer { isWorking = false }
            do {
                let backup = try await WalletBackup.make(payload, password: password)
                export = PendingExport(file: JSONFile(data: try backup.exportedJSON()), filename: WalletBackup.suggestedFilename())
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Cloud sync

struct CloudSyncView: View {
    var body: some View {
        EmptyState("Coming soon", systemImage: "icloud", message: "Cloud sync will store your encrypted wallet backup off-device. Data is always encrypted first; nothing unencrypted ever leaves this device.")
        .navigationTitle("Cloud Sync")
        .navigationBarTitleDisplayMode(.inline)
    }
}
