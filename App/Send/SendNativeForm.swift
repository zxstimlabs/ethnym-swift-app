import BigInt
import EthnymKit
import SwiftUI

/// Sends ether.
struct SendNativeForm: View {
    @Environment(AppModel.self) private var app
    @State private var amount = ""
    @State private var recipient = ""
    @State private var password = ""
    @State private var resolution = ENSResolution()
    @State private var gas = GasPriceModel()
    @State private var flow = SendFlow()

    var body: some View {
        Form {
            AmountSection(
                text: $amount,
                balance: app.balances.native,
                decimals: Units.etherDecimals,
                symbol: app.chain.nativeCurrency.symbol,
                error: amountResult.failure,
                isLoading: app.balances.nativeState.isLoading,
                refresh: refreshBalance
            )

            RecipientSection(text: $recipient, resolution: resolution)

            GasPresetSection(model: gas) { Task { await gas.refresh(service: app.service) } }

            SubmitSection(
                title: "Send",
                password: $password,
                flow: flow,
                canSubmit: request != nil && !password.isEmpty,
                disabledReason: app.settings.offlineMode ? SendCopy.offline : nil,
                submit: send,
                reset: reset
            )

            TransactionStatusSection(flow: flow)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await gas.refresh(service: app.service) }
    }

    private var amountResult: Result<BigUInt, FieldError> {
        AmountValidation.validate(amount, decimals: Units.etherDecimals, balance: app.balances.native, allowZero: true)
    }

    private var request: TransactionRequest? {
        guard app.service != nil,
              case let .success(value) = amountResult,
              RecipientValidation.validate(recipient) == nil,
              let to = resolution.address(for: recipient)
        else { return nil }
        return TransactionRequest(chainId: app.chain.id, to: to, value: value, maxFeePerGas: gas.selectedPrice)
    }

    private func send() {
        guard let wallet = app.wallets.activeWallet, let request else { return }
        let pending = PendingActivity(
            from: wallet.address,
            to: request.to,
            chainId: request.chainId,
            type: .native,
            nativeValue: String(request.value),
            gasPrice: gas.selectedPrice.map { String($0) },
            ensName: recipient.isENSName ? recipient.trimmed.lowercased() : nil
        )
        Task {
            await flow.send(request, pending: pending, wallet: wallet, password: password, app: app)
            if flow.errorMessage == nil { password = "" }
        }
    }

    private func refreshBalance() {
        guard let address = app.wallets.activeWallet?.address, let service = app.service else { return }
        Task { await app.balances.refreshNative(address: address, service: service) }
    }

    private func reset() {
        withAnimation(.house) {
            amount = ""
            recipient = ""
            password = ""
            resolution.reset()
            flow.reset()
        }
    }
}

/// The recipient field, shared by the ether, token and NFT forms.
struct RecipientSection: View {
    @Binding var text: String
    let resolution: ENSResolution

    var body: some View {
        Section {
            AddressField(
                placeholder: "Address (0x...) or ENS (.eth)",
                text: $text,
                resolution: resolution,
                error: RecipientValidation.validate(text)
            )
        } header: {
            HStack(spacing: 6) {
                SectionHeader("Recipient")
                InfoButton(title: "Recipient", message: "Enter the recipient's address, or an ENS name such as vitalik.eth. Names resolve to an address automatically; check it before sending. You can also scan a QR code or pick from your address book.")
            }
        }
    }
}

enum SendCopy {
    static let offline = "Offline mode is on, so sending is turned off. Use Sign to sign transaction JSON without broadcasting."
}

extension Result {
    var failure: Failure? {
        if case let .failure(error) = self { error } else { nil }
    }
}
