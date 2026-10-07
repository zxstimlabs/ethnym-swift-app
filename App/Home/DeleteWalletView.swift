import EthnymKit
import SwiftUI

/// Deletes the active wallet once its password proves ownership.
struct DeleteWalletView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.flowExit) private var flowExit
    @State private var password = ""
    @State private var isConfirming = false
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let wallet = app.wallets.activeWallet {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wallet.name)
                                .font(.mono(.callout, weight: .semibold))
                            AddressText(address: wallet.address, style: .caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        SectionHeader("Wallet")
                    }

                    Section {
                        PasswordField(title: "Password", text: $password)
                    } header: {
                        SectionHeader("1  Enter your wallet password")
                    } footer: {
                        if let error { FieldHint(error, kind: .error) }
                    }

                    Section {
                        Button(role: .destructive) {
                            isConfirming = true
                        } label: {
                            HStack {
                                Text("Delete Wallet")
                                Spacer()
                                if isWorking { ProgressView() }
                            }
                        }
                        .disabled(password.isEmpty || isWorking)
                    } header: {
                        SectionHeader("2  Confirm")
                    } footer: {
                        Text("The keystore is removed from this device. Without a keystore backup or the secret phrase, the wallet can't be recovered.")
                            .font(.mono(.caption))
                    }
                    .confirmationDialog("Delete “\(wallet.name)”?", isPresented: $isConfirming, titleVisibility: .visible) {
                        Button("Delete Wallet", role: .destructive) { delete(wallet) }
                    } message: {
                        Text("This can't be undone.")
                    }
                } else {
                    EmptyState("No wallet selected", systemImage: "wallet.bifold", message: "Select a wallet on Home to delete it.")
                }
            }
            .navigationTitle("Delete Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .flowToolbar()
            .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        }
    }

    private func delete(_ wallet: WalletKeystore) {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                _ = try await WalletCrypto.unlock(wallet, password: password)
                withAnimation(.house) { app.wallets.delete(wallet) }
                flowExit.close()
            } catch {
                self.error = "Wrong password. Please try again."
            }
        }
    }
}
