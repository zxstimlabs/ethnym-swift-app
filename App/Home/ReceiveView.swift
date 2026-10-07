import EthnymKit
import SwiftUI

/// The active address as a QR code, to receive funds, in a pop-up.
struct ReceiveView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        PopUp("Receive", systemImage: "qrcode") {
            if let wallet = app.wallets.activeWallet {
                VStack(spacing: 20) {
                    QRCodeImage(value: wallet.address)
                        .frame(maxWidth: 240)
                    VStack(spacing: 6) {
                        Text(wallet.name)
                            .font(.mono(.headline, weight: .semibold))
                        AddressText(address: wallet.address, style: .footnote)
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
                .frame(maxWidth: .infinity)
            }
        }
    }
}
