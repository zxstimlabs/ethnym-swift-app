import BigInt
import EthnymKit
import SwiftUI

/// Send ether, a token or an NFT, or sign transaction JSON.
struct SendView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case eth = "ETH"
        case token = "Token"
        case nft = "NFT"
        case sign = "Sign"

        var id: Self { self }
    }

    @Environment(AppModel.self) private var app
    @State private var kind: Kind = .eth

    var body: some View {
        NavigationStack {
            Group {
                if app.wallets.activeWallet == nil {
                    EmptyState("No wallet selected", systemImage: "wallet.bifold", message: "Select a wallet on Home to send from it.")
                } else {
                    switch kind {
                    case .eth: SendNativeForm()
                    case .token: SendTokenForm()
                    case .nft: SendNftForm()
                    case .sign: SignTransactionForm()
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if let wallet = app.wallets.activeWallet {
                        SectionHeader("Send from \(wallet.name)")
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                    Picker("Send", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .tabTitle("Send")
            .toolbar { AppHeader() }
            .sensoryFeedback(.selection, trigger: kind)
        }
    }
}

// MARK: - Shared form sections

/// The big amount field with 25% / 50% / 75% / Max and the spendable balance.
struct AmountSection: View {
    @Binding var text: String
    let balance: BigUInt?
    let decimals: Int
    let symbol: String
    let error: FieldError?
    let isLoading: Bool
    let refresh: () -> Void

    @State private var isTouched = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                TextField("0", text: $text)
                    .font(.mono(size: 32, weight: .semibold))
                    .keyboardType(.decimalPad)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .onChange(of: text) { isTouched = true }

                HStack(spacing: 8) {
                    ForEach([(1, "25%"), (2, "50%"), (3, "75%"), (4, "Max")], id: \.0) { quarters, label in
                        Button(label) {
                            if let balance {
                                text = AmountValidation.fraction(quarters, of: balance, decimals: decimals)
                            }
                        }
                        .buttonStyle(.chip)
                        .disabled(balance == nil)
                    }
                }

                HStack(spacing: 6) {
                    Text("Balance")
                        .foregroundStyle(.secondary)
                    Group {
                        if let balance {
                            Text(Units.format(balance, decimals: decimals))
                                .contentTransition(.numericText())
                        } else {
                            Text("—").loadingPulse(isLoading)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Text(symbol)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh balance", systemImage: "arrow.clockwise", action: refresh)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .symbolEffect(.rotate, isActive: isLoading)
                }
                .font(.mono(.footnote))
                .animation(.house, value: balance)

                FieldHint(prompt: AmountValidation.emptyMessage, error: error, isTouched: isTouched)
            }
            .padding(.vertical, 4)
        } header: {
            SectionHeader("Sending")
        }
    }
}

/// Slow / Normal / Fast as 90%, 100% and 110% of the network gas price.
struct GasPresetSection: View {
    let model: GasPriceModel
    let refresh: () -> Void

    var body: some View {
        @Bindable var model = model
        Section {
            HStack(spacing: 8) {
                ForEach(GasPriceModel.Preset.allCases) { preset in
                    Button(preset.title) {
                        withAnimation(.house) { model.preset = preset }
                    }
                    .buttonStyle(.chip(selected: model.preset == preset))
                }
            }
            .sensoryFeedback(.selection, trigger: model.preset)

            HStack {
                Group {
                    if let gwei = model.selectedGwei {
                        Text("\(gwei) gwei")
                            .contentTransition(.numericText())
                    } else {
                        Text("— gwei").loadingPulse(model.isLoading)
                    }
                }
                .font(.mono(.callout, weight: .medium))
                .animation(.house, value: model.selectedGwei)
                Spacer()
                Button("Refresh gas price", systemImage: "arrow.clockwise", action: refresh)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .symbolEffect(.rotate, isActive: model.isLoading)
            }
            if let error = model.errorMessage {
                FieldHint(error, kind: .error)
            }
        } header: {
            HStack(spacing: 6) {
                SectionHeader("Gas preset")
                InfoButton(title: "Gas preset", message: "The most you'll pay per unit of gas. Fast includes the transaction sooner; Slow costs less but can wait if the network is busy. You pay only the current base fee plus a small tip, up to this cap.")
            }
        }
    }
}

/// The password, then Send. The button tracks the flow: spinner while signing, check once sent.
struct SubmitSection: View {
    let title: String
    @Binding var password: String
    let flow: SendFlow
    let canSubmit: Bool
    let disabledReason: String?
    let submit: () -> Void
    let reset: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            PasswordField(title: "Wallet password", text: $password)
        } header: {
            SectionHeader("Password")
        } footer: {
            if let disabledReason {
                Text(disabledReason)
                    .font(.mono(.caption))
            }
        }

        Section {
            HStack(spacing: 10) {
                Button("Reset", action: reset)
                    .buttonStyle(.secondary)
                    .frame(maxWidth: 110)
                    .disabled(flow.isBusy)
                Button(action: submit) {
                    Group {
                        switch label {
                        case .busy: ProgressView().tint(Color(.systemBackground))
                        case .done: Label("Sent", systemImage: "checkmark")
                        case .idle: Text(title)
                        }
                    }
                    .contentTransition(.opacity)
                }
                .buttonStyle(.primary)
                .disabled(!canSubmit || flow.isBusy)
                .accessibilityIdentifier("submit")
            }
            .animation(.house, value: label)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private enum ButtonLabel { case idle, busy, done }

    private var label: ButtonLabel {
        if flow.isBusy { return .busy }
        if let hash = flow.hash, case .submitted = flow.phase {
            switch app.transactions.status(of: hash) {
            case .confirming: return .busy
            case .confirmed: return .done
            default: return .idle
            }
        }
        return .idle
    }
}
