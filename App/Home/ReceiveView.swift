import EthnymKit
import SwiftUI

/// The active address as a QR code, to receive funds.
struct ReceiveView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let wallet = app.wallets.activeWallet {
                    VStack(spacing: 24) {
                        QRCodeImage(value: wallet.address)
                            .frame(maxWidth: 300)
                        VStack(spacing: 6) {
                            Text(wallet.name)
                                .font(.mono(.headline, weight: .semibold))
                            AddressText(address: wallet.address, style: .callout)
                                .multilineTextAlignment(.center)
                        }
                        Text("Send only Ethereum mainnet assets to this address.")
                            .font(.mono(.caption))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            CopyButton(text: wallet.address, title: "Copy")
                                .buttonStyle(.secondary)
                            ShareLink(item: wallet.address) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.primary)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
