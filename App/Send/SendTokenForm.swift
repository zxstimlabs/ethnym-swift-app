import BigInt
import EthnymKit
import SwiftUI

/// Sends an ERC-20 token, picked from the list or entered by contract address or ENS name.
struct SendTokenForm: View {
    @Environment(AppModel.self) private var app
    @State private var contract = ""
    @State private var amount = ""
    @State private var recipient = ""
    @State private var password = ""
    @State private var contractResolution = ENSResolution()
    @State private var resolution = ENSResolution()
    @State private var details = TokenDetails()
    @State private var gas = GasPriceModel()
    @State private var flow = SendFlow()
    @State private var isPicking = false

    var body: some View {
        Form {
            Section {
                SectionIntro("Token", info: "The ERC-20 token to send. Pick one from the list, or enter its contract address or ENS name; its name, symbol and your balance load from the contract.")

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        isPicking = true
                    } label: {
                        HStack {
                            Text(selectedToken?.asset.symbol ?? "Select token")
                                .font(.mono(.callout, weight: .semibold))
                            if selectedToken?.isVerified == true {
                                Image(systemName: "checkmark.seal")
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    AddressField(
                        placeholder: "Token address (0x...) or ENS (.eth)",
                        text: $contract,
                        resolution: contractResolution,
                        error: contract.trimmed.isEmpty ? FieldError("Please enter a token address or ENS", isPrompt: true) : RecipientValidation.validate(contract),
                        prompt: "Please enter a token address or ENS",
                        showsAddressBook: false
                    )

                    HStack(spacing: 6) {
                        Text(details.metadata?.name ?? "-")
                        Text("·").foregroundStyle(.secondary)
                        Text(details.metadata?.symbol ?? "-")
                    }
                    .font(.mono(.footnote))
                    .foregroundStyle(.secondary)
                    .loadingPulse(details.state.isLoading && details.metadata == nil)
                    if let error = details.state.errorMessage {
                        FieldHint(error, kind: .error)
                    }
                }
            }

            AmountSection(
                text: $amount,
                balance: details.balance,
                decimals: details.metadata?.decimals ?? 18,
                symbol: details.metadata?.symbol ?? "-",
                error: amountResult.failure,
                isLoading: details.state.isLoading,
                refresh: { Task { await loadDetails() } }
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
        .task(id: resolvedContract) { await loadDetails() }
        .sheet(isPresented: $isPicking) {
            TokenPickerSheet(selected: resolvedContract) { address in
                contract = address
                isPicking = false
            }
        }
    }

    private var resolvedContract: String? {
        contractResolution.address(for: contract)
    }

    private var selectedToken: Listed<Token>? {
        resolvedContract.flatMap { app.assets.token(at: $0) }
    }

    private func loadDetails() async {
        await details.load(
            contract: resolvedContract,
            owner: app.wallets.activeWallet?.address,
            known: selectedToken?.asset,
            service: app.service
        )
    }

    private var amountResult: Result<BigUInt, FieldError> {
        guard let decimals = details.metadata?.decimals else {
            return amount.trimmed.isEmpty
                ? .failure(FieldError(AmountValidation.emptyMessage, isPrompt: true))
                : .failure(FieldError("Select a token first"))
        }
        return AmountValidation.validate(amount, decimals: decimals, balance: details.balance, allowZero: false)
    }

    private var request: TransactionRequest? {
        guard app.service != nil,
              let token = resolvedContract,
              case let .success(value) = amountResult,
              RecipientValidation.validate(recipient) == nil,
              let to = resolution.address(for: recipient),
              let data = try? Contracts.erc20Transfer(token: token, to: to, amount: value)
        else { return nil }
        return TransactionRequest(chainId: app.chain.id, to: token, value: 0, data: data, maxFeePerGas: gas.selectedPrice)
    }

    private func send() {
        guard let wallet = app.wallets.activeWallet, let request, let metadata = details.metadata,
              case let .success(value) = amountResult, let to = resolution.address(for: recipient)
        else { return }
        let pending = PendingActivity(
            from: wallet.address,
            to: to,
            chainId: request.chainId,
            type: .erc20,
            tokenValue: String(value),
            tokenAddress: request.to,
            tokenSymbol: metadata.symbol,
            tokenDecimals: metadata.decimals,
            gasPrice: gas.selectedPrice.map { String($0) },
            ensName: recipient.isENSName ? recipient.trimmed.lowercased() : nil
        )
        Task {
            await flow.send(request, pending: pending, wallet: wallet, password: password, app: app)
            if flow.errorMessage == nil { password = "" }
        }
    }

    private func reset() {
        withAnimation(.house) {
            contract = ""
            amount = ""
            recipient = ""
            password = ""
            contractResolution.reset()
            resolution.reset()
            details.clear()
            flow.reset()
        }
    }
}

/// Picks a token, holdings first, then the rest of the list.
struct TokenPickerSheet: View {
    let selected: String?
    let onSelect: (String) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(filtered) { token in
                Button {
                    onSelect(token.asset.address)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(token.asset.symbol)
                                    .font(.mono(.callout, weight: .semibold))
                                if token.isVerified {
                                    Image(systemName: "checkmark.seal")
                                        .font(.mono(.caption))
                                }
                            }
                            Text(token.asset.name)
                                .font(.mono(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let balance = app.balances.balance(of: token.asset.address), balance > 0 {
                            Text(Units.format(balance, decimals: token.asset.decimals, maxFractionDigits: 4))
                                .font(.mono(.footnote, weight: .medium))
                        }
                        if selected.map({ Address.isSame($0, token.asset.address) }) == true {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name or symbol")
            .navigationTitle("Select Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private var filtered: [Listed<Token>] {
        let sorted = app.balances.sorted(app.assets.tokens)
        let query = search.trimmed.lowercased()
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.asset.symbol.lowercased().contains(query) || $0.asset.name.lowercased().contains(query) }
    }
}
