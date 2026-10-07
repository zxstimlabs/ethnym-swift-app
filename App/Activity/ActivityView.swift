import EthnymKit
import SwiftUI

/// Transactions sent from the active wallet, recorded on this device as they confirm.
struct ActivityView: View {
    enum Direction: String, CaseIterable, Identifiable {
        case outgoing = "Outgoing"
        case incoming = "Incoming"

        var id: Self { self }
    }

    @Environment(AppModel.self) private var app
    @State private var direction: Direction = .outgoing

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Direction", selection: $direction.animation(.house)) {
                        ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                switch direction {
                case .outgoing: outgoing
                case .incoming:
                    EmptyState("Coming soon", systemImage: "arrow.down.left", message: "Incoming transfers will appear here.")
                        .listRowBackground(Color.clear)
                }
            }
            .tabTitle("Activity")
            .toolbar { AppHeader() }
            .sensoryFeedback(.selection, trigger: direction)
        }
    }

    @ViewBuilder
    private var outgoing: some View {
        if let wallet = app.wallets.activeWallet {
            let records = app.activity.outgoing(from: wallet.address)
            if records.isEmpty {
                EmptyState("No activity yet", systemImage: "arrow.up.right", message: "Transactions you send from \(wallet.name) appear here once confirmed.")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(records) { record in
                        ActivityRow(record: record)
                    }
                } header: {
                    SectionHeader("\(wallet.name)")
                } footer: {
                    Text("Stored on this device only.")
                        .font(.mono(.caption))
                }
            }
        } else {
            EmptyState("No active wallet", systemImage: "wallet.bifold", message: "Select a wallet on Home to see its activity.")
                .listRowBackground(Color.clear)
        }
    }
}

private struct ActivityRow: View {
    let record: ActivityRecord
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Tag(text: Formatting.chainLabel(record.chainId))
                Link(destination: app.chain.transactionURL(record.txHash)) {
                    HStack(spacing: 3) {
                        Text(Formatting.truncateHash(record.txHash))
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.mono(.caption))
                }
                Spacer()
                Text(record.date, format: .dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits).hour().minute().second())
                    .font(.mono(.caption2))
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("To")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        if let ens = record.ensName {
                            Text(ens)
                                .font(.mono(.caption, weight: .medium))
                        }
                        AddressText(address: record.to, style: .caption)
                            .foregroundStyle(record.ensName == nil ? .primary : .secondary)
                    }
                }
                if let value = record.formattedValue {
                    GridRow {
                        Text("Amount")
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.mono(.caption, weight: .medium))
                    }
                }
                GridRow {
                    Text("Type")
                        .foregroundStyle(.secondary)
                    Text(record.type.label)
                }
            }
            .font(.mono(.caption))
        }
        .padding(.vertical, 4)
        .contextMenu {
            CopyMenuButton(title: "Copy Transaction Hash", text: record.txHash)
            CopyMenuButton(title: "Copy Recipient", text: record.to)
        }
    }
}

extension TxType {
    var label: String {
        switch self {
        case .native: "Ether"
        case .erc20: "Token"
        case .erc721: "NFT"
        case .raw: "Signed JSON"
        }
    }
}
