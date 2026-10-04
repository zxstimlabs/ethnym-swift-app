import BigInt
import EthnymKit
import SwiftUI

/// Signs a transaction from pasted JSON. Online it fills in what's missing and broadcasts;
/// in offline mode it signs only, for broadcasting from another device.
struct SignTransactionForm: View {
    @Environment(AppModel.self) private var app
    @State private var json = ""
    @State private var password = ""
    @State private var flow = SendFlow()
    @State private var isTouched = false

    private static let placeholder = #"{"to": "0x...", "chainId": 1, "type": "eip1559", "gas": "0x...", "maxFeePerGas": "0x...", "maxPriorityFeePerGas": "0x..."}"#

    var body: some View {
        Form {
            Section {
                TextField(Self.placeholder, text: $json, axis: .vertical)
                    .font(.mono(.caption))
                    .lineLimit(5 ... 14)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .onChange(of: json) { isTouched = true }
                PasteButton(payloadType: String.self) { strings in
                    if let first = strings.first { json = first }
                }
                .labelStyle(.titleAndIcon)
                FieldHint(prompt: PreparedTransaction.ValidationError.empty.localizedDescription, error: validationError, isTouched: isTouched)
            } header: {
                SectionHeader("Transaction JSON")
            } footer: {
                Text(app.settings.offlineMode
                     ? "Offline: every field (nonce, gas, maxFeePerGas, maxPriorityFeePerGas) must be set. The signed transaction is shown for broadcasting elsewhere."
                     : "Missing nonce, gas and fees are filled in from the network. Sent as an EIP-1559 transaction.")
                    .font(.mono(.caption))
            }

            if case let .success(transaction) = parsed {
                TransactionDetailsSection(transaction: transaction)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            SubmitSection(
                title: app.settings.offlineMode ? "Sign" : "Send",
                password: $password,
                flow: flow,
                canSubmit: (try? parsed.get()) != nil && !password.isEmpty,
                disabledReason: nil,
                submit: submit,
                reset: reset
            )

            TransactionStatusSection(flow: flow)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.house, value: (try? parsed.get()) != nil)
    }

    private var parsed: Result<PreparedTransaction, PreparedTransaction.ValidationError> {
        PreparedTransaction.validate(json)
    }

    private var validationError: FieldError? {
        switch parsed {
        case .success: nil
        case .failure(.empty): FieldError(PreparedTransaction.ValidationError.empty.localizedDescription, isPrompt: true)
        case let .failure(error): FieldError(error.localizedDescription)
        }
    }

    private func submit() {
        guard let wallet = app.wallets.activeWallet, case let .success(transaction) = parsed else { return }
        let request = TransactionRequest(transaction)
        Task {
            if app.settings.offlineMode {
                await flow.signOffline(request, wallet: wallet, password: password)
            } else {
                let pending = PendingActivity(
                    from: wallet.address,
                    to: transaction.to,
                    chainId: transaction.chainId,
                    type: .raw,
                    nativeValue: transaction.valueAmount.map { String($0) }
                )
                await flow.send(request, pending: pending, wallet: wallet, password: password, app: app)
            }
            if flow.errorMessage == nil { password = "" }
        }
    }

    private func reset() {
        withAnimation(.house) {
            json = ""
            password = ""
            isTouched = false
            flow.reset()
        }
    }
}

private struct TransactionDetailsSection: View {
    let transaction: PreparedTransaction

    var body: some View {
        Section {
            LabeledContent("Chain", value: Formatting.chainLabel(transaction.chainId))
            LabeledContent("To") {
                AddressText(address: transaction.to, style: .caption)
            }
            if let from = transaction.from ?? transaction.account {
                LabeledContent("From") {
                    AddressText(address: from, style: .caption)
                }
            }
            if let value = transaction.valueAmount, value > 0 {
                LabeledContent("Value", value: "\(Units.formatEther(value)) ETH")
            }
            if let type = transaction.type {
                LabeledContent("Type", value: type)
            }
            if let gas = transaction.gasAmount {
                LabeledContent("Gas", value: String(gas))
            }
            if let nonce = transaction.nonce {
                LabeledContent("Nonce", value: String(nonce))
            }
            if let fee = transaction.maxFeeAmount {
                LabeledContent("Max fee per gas", value: "\(Units.formatGwei(fee)) gwei")
            }
            if let tip = transaction.maxPriorityFeeAmount {
                LabeledContent("Max priority fee", value: "\(Units.formatGwei(tip)) gwei")
            }
            if let data = transaction.data, data.count > 2 {
                LabeledContent("Data", value: "\((data.count - 2) / 2) bytes")
            }
        } header: {
            SectionHeader("Transaction details")
        }
        .font(.mono(.footnote))
    }
}
