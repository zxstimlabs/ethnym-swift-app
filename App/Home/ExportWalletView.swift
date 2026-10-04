import EthnymKit
import SwiftUI

/// Saves keystore files and reveals the active wallet's secret phrase.
struct ExportWalletView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var export: PendingExport?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Save Current Wallet Keystore…", systemImage: "square.and.arrow.down") {
                        guard let wallet = app.wallets.activeWallet else { return }
                        prepareExport(filename: "\(wallet.name.replacingOccurrences(of: " ", with: "-"))-DO_NOT_DELETE.json") {
                            try wallet.exportedJSON()
                        }
                    }
                    .disabled(app.wallets.activeWallet == nil)

                    Button("Save All Keystores…", systemImage: "square.and.arrow.down.on.square") {
                        prepareExport(filename: "ethnym-wallets-DO_NOT_DELETE.json") {
                            try JSONEncoder.prettyPrinted.encode(app.wallets.wallets)
                        }
                    }
                } header: {
                    SectionHeader("Keystore files")
                } footer: {
                    if let exportError {
                        FieldHint(exportError, kind: .error)
                    } else {
                        Text("Keystores stay encrypted with their passwords. Keep a copy somewhere safe; they restore your wallets in ETHnym or the web wallet.")
                            .font(.mono(.caption))
                    }
                }

                if let wallet = app.wallets.activeWallet {
                    RevealPhraseSection(wallet: wallet)
                } else {
                    Section {
                        Text("Select a wallet to reveal its secret phrase.")
                            .font(.mono(.footnote))
                            .foregroundStyle(.secondary)
                    } header: {
                        SectionHeader("Secret phrase")
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: Binding(get: { export != nil }, set: { if !$0 { export = nil } }),
                document: export?.file,
                contentType: .json,
                defaultFilename: export?.filename
            ) { result in
                if case let .failure(error) = result { exportError = error.localizedDescription }
            }
        }
    }

    private func prepareExport(filename: String, data: () throws -> Data) {
        do {
            export = PendingExport(file: JSONFile(data: try data()), filename: filename)
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// Decrypts and shows the phrase. It's cleared when the app leaves the foreground or the screen closes.
private struct RevealPhraseSection: View {
    let wallet: WalletKeystore
    @Environment(\.scenePhase) private var scenePhase
    @State private var password = ""
    @State private var phrase: String?
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        Section {
            if let phrase {
                PhraseGrid(phrase: phrase)
                    .transition(.blurReplace)
                HStack {
                    CopyButton(text: phrase, title: "Copy", isSecret: true)
                    Spacer()
                    Button("Hide", systemImage: "eye.slash") {
                        withAnimation(.house) { self.phrase = nil }
                    }
                }
                .buttonStyle(.borderless)
            } else {
                PasswordField(title: "Wallet password", text: $password)
                Button(action: reveal) {
                    HStack {
                        Text("Reveal Secret Phrase")
                        Spacer()
                        if isWorking { ProgressView() }
                    }
                }
                .disabled(password.isEmpty || isWorking)
            }
        } header: {
            SectionHeader("Secret phrase")
        } footer: {
            if let error {
                FieldHint(error, kind: .error)
            } else {
                Text("Anyone with these words controls the wallet. Never share them or type them into a website. Copies expire from the clipboard after a minute.")
                    .font(.mono(.caption))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { phrase = nil }
        }
        .onDisappear { phrase = nil }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
    }

    private func reveal() {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                let revealed = try await WalletCrypto.revealPhrase(wallet.keystore, password: password)
                password = ""
                withAnimation(.house) { phrase = revealed }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Numbered words in three columns, the way they'd be written down.
struct PhraseGrid: View {
    let phrase: String

    var body: some View {
        let words = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 3), alignment: .leading, spacing: 10) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.mono(.caption2))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 16, alignment: .trailing)
                    Text(word)
                        .font(.mono(.callout, weight: .medium))
                }
            }
        }
        .padding(.vertical, 6)
        .privacySensitive()
        .textSelection(.enabled)
    }
}

extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
