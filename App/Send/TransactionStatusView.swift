import EthnymKit
import SwiftUI

/// Where a send stands: signature, then confirmation, with any error above.
struct TransactionStatusSection: View {
    let flow: SendFlow
    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            if let error = flow.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.octagon")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Error")
                            .font(.mono(.footnote, weight: .semibold))
                        Text(error)
                            .font(.mono(.caption))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button("Dismiss error", systemImage: "xmark") {
                        withAnimation(.house) { flow.errorMessage = nil }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
                .foregroundStyle(.red)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            signatureRow
            transactionRow

            if case let .signedOffline(raw, _) = flow.phase {
                SignedTransactionOutput(raw: raw)
                    .transition(.blurReplace)
            }
        } header: {
            SectionHeader("Status")
        }
        .animation(.house, value: flow.phase)
        .animation(.house, value: flow.errorMessage)
        .animation(.house, value: monitorStatus)
        .sensoryFeedback(.error, trigger: flow.errorMessage) { _, new in new != nil }
        .sensoryFeedback(trigger: monitorStatus) { _, new in
            switch new {
            case .confirmed: .success
            case .reverted, .failed: .error
            default: nil
            }
        }
    }

    private var monitorStatus: TransactionMonitor.Status? {
        flow.hash.flatMap { app.transactions.status(of: $0) }
    }

    @ViewBuilder
    private var signatureRow: some View {
        switch flow.phase {
        case .idle:
            StatusRow(icon: .pending, text: "Nothing to sign")
        case .signing:
            StatusRow(icon: .progress, text: "Signing")
        case .submitted, .signedOffline:
            StatusRow(icon: .done, text: "Signed")
        }
    }

    @ViewBuilder
    private var transactionRow: some View {
        switch flow.phase {
        case let .submitted(hash):
            switch monitorStatus {
            case .confirmed:
                StatusRow(icon: .done, text: "Confirmed", hash: hash)
            case .reverted:
                StatusRow(icon: .failed, text: "Reverted", hash: hash)
            case let .failed(message):
                StatusRow(icon: .failed, text: "Couldn't confirm: \(message)", hash: hash)
            case .confirming, nil:
                StatusRow(icon: .progress, text: "Confirming", hash: hash)
            }
        case .signedOffline:
            StatusRow(icon: .pending, text: "Not broadcast (offline)")
        case .idle, .signing:
            StatusRow(icon: .pending, text: "No transaction")
        }
    }
}

private struct StatusRow: View {
    enum Icon { case pending, progress, done, failed }

    let icon: Icon
    let text: String
    var hash: String?
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch icon {
                case .pending: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                case .progress: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill")
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .frame(width: 20)
            .transition(.scale.combined(with: .opacity))

            Text(text)
                .font(.mono(.footnote))
                .foregroundStyle(icon == .pending ? .secondary : .primary)
            Spacer(minLength: 4)
            if let hash {
                Link(destination: app.chain.transactionURL(hash)) {
                    HStack(spacing: 3) {
                        Text(Formatting.truncateHash(hash))
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.mono(.caption))
                }
                CopyButton(text: hash)
                    .buttonStyle(.borderless)
                    .font(.mono(.caption))
            }
        }
    }
}

/// A transaction signed offline, to broadcast from another device.
private struct SignedTransactionOutput: View {
    let raw: String
    @State private var showsQR = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signed raw transaction")
                .font(.mono(.footnote, weight: .semibold))
            Text(raw)
                .font(.mono(.caption2))
                .textSelection(.enabled)
                .lineLimit(6)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.fill, in: .rect(cornerRadius: 10))
            HStack(spacing: 16) {
                CopyButton(text: raw, title: "Copy")
                ShareLink(item: raw) { Label("Share", systemImage: "square.and.arrow.up") }
                Button("QR Code", systemImage: "qrcode") { showsQR = true }
            }
            .buttonStyle(.borderless)
            .font(.mono(.footnote))
            Text("Broadcast it with eth_sendRawTransaction from any online node or explorer.")
                .font(.mono(.caption))
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showsQR) {
            QRCodeImage(value: raw)
                .padding()
                .presentationDetents([.medium])
        }
    }
}
