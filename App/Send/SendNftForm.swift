import BigInt
import EthnymKit
import SwiftUI

/// Sends an ERC-721 token with `safeTransferFrom`.
struct SendNftForm: View {
    @Environment(AppModel.self) private var app
    @State private var contract = ""
    @State private var tokenId = ""
    @State private var recipient = ""
    @State private var password = ""
    @State private var contractResolution = ENSResolution()
    @State private var resolution = ENSResolution()
    @State private var details = NftDetails()
    @State private var gas = GasPriceModel()
    @State private var flow = SendFlow()
    @State private var isPicking = false
    @State private var tokenIdTouched = false

    var body: some View {
        Form {
            Section {
                SectionIntro("NFT contract", info: "The ERC-721 collection the NFT belongs to. Pick an NFT you own, which fills in its token ID too, or a listed collection, or enter the contract address or ENS name.")

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        isPicking = true
                    } label: {
                        HStack {
                            Text(pickerTitle)
                                .font(.mono(.callout, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    AddressField(
                        placeholder: "NFT contract (0x...) or ENS (.eth)",
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
                }
            }

            Section {
                SectionIntro("Token ID", info: "The NFT's number within the collection. Below it you'll see who owns that token; only its owner can send it.")

                VStack(alignment: .leading, spacing: 10) {
                    TextField("0", text: $tokenId)
                        .font(.mono(size: 32, weight: .semibold))
                        .keyboardType(.numberPad)
                        .onChange(of: tokenId) { tokenIdTouched = true }
                    HStack {
                        ownership
                        Spacer()
                        Button("Refresh owner", systemImage: "arrow.clockwise") {
                            Task { await loadDetails() }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .symbolEffect(.rotate, isActive: details.state.isLoading)
                    }
                    .font(.mono(.footnote))
                    FieldHint(prompt: "Please enter the NFT token ID", error: tokenIdError, isTouched: tokenIdTouched)
                }
            }

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
        .task(id: "\(resolvedContract ?? "")#\(tokenId)") {
            try? await Task.sleep(for: .milliseconds(300))
            await loadDetails()
        }
        .sheet(isPresented: $isPicking) {
            NftPickerSheet(contract: resolvedContract, tokenId: tokenId) { address, id in
                contract = address
                tokenId = id
                isPicking = false
            }
        }
    }

    @ViewBuilder
    private var ownership: some View {
        if parsedTokenId != nil, let owner = details.owner {
            if let wallet = app.wallets.activeWallet, Address.isSame(owner, wallet.address) {
                Label("Owned by you", systemImage: "checkmark")
            } else {
                Text("Owned by \(Formatting.truncateAddress(owner))")
                    .foregroundStyle(.red)
            }
        } else if parsedTokenId != nil, details.state == .loaded {
            Text("This token doesn't exist")
                .foregroundStyle(.red)
        } else {
            Text("--")
                .foregroundStyle(.secondary)
                .loadingPulse(details.state.isLoading)
        }
    }

    private var resolvedContract: String? {
        contractResolution.address(for: contract)
    }

    private var pickerTitle: String {
        guard let resolvedContract, let collection = app.assets.collection(at: resolvedContract) else { return "Select NFT" }
        return tokenId.isEmpty ? collection.asset.symbol : "\(collection.asset.symbol) #\(tokenId)"
    }

    private var parsedTokenId: BigUInt? {
        let trimmed = tokenId.trimmed
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return nil }
        return BigUInt(trimmed)
    }

    private var tokenIdError: FieldError? {
        if tokenId.trimmed.isEmpty { return FieldError("Please enter a token ID", isPrompt: true) }
        return parsedTokenId == nil ? FieldError("Please enter a valid token ID") : nil
    }

    private func loadDetails() async {
        await details.load(
            contract: resolvedContract,
            tokenId: parsedTokenId,
            known: resolvedContract.flatMap { app.assets.collection(at: $0)?.asset },
            service: app.service
        )
    }

    private var request: TransactionRequest? {
        guard app.service != nil,
              let wallet = app.wallets.activeWallet,
              let nft = resolvedContract,
              let id = parsedTokenId,
              RecipientValidation.validate(recipient) == nil,
              let to = resolution.address(for: recipient),
              let data = try? Contracts.erc721SafeTransfer(contract: nft, from: wallet.address, to: to, tokenId: id)
        else { return nil }
        return TransactionRequest(chainId: app.chain.id, to: nft, value: 0, data: data, maxFeePerGas: gas.selectedPrice)
    }

    private func send() {
        guard let wallet = app.wallets.activeWallet, let request, let to = resolution.address(for: recipient) else { return }
        let pending = PendingActivity(
            from: wallet.address,
            to: to,
            chainId: request.chainId,
            type: .erc721,
            nftId: tokenId.trimmed,
            tokenAddress: request.to,
            tokenSymbol: details.metadata?.symbol,
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
            tokenId = ""
            recipient = ""
            password = ""
            tokenIdTouched = false
            contractResolution.reset()
            resolution.reset()
            details.clear()
            flow.reset()
        }
    }
}

/// Owned NFTs fill in the contract and token ID; other collections fill in just the contract.
struct NftPickerSheet: View {
    let contract: String?
    let tokenId: String
    let onSelect: (String, String) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                if !owned.isEmpty {
                    Section {
                        ForEach(owned) { nft in
                            row(collection: nft.collection, tokenId: nft.tokenId)
                        }
                    } header: {
                        SectionHeader("Owned")
                    }
                }
                if !others.isEmpty {
                    Section {
                        ForEach(others, id: \.asset.address) { collection in
                            row(collection: collection, tokenId: nil)
                        }
                    } header: {
                        SectionHeader("Collections")
                    } footer: {
                        Text("Picks the contract; enter the token ID yourself.")
                            .font(.mono(.caption))
                    }
                }
            }
            .overlay {
                if owned.isEmpty && others.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, symbol or token ID")
            .navigationTitle("Select NFT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func matches(_ collection: NftCollection) -> Bool {
        let query = search.trimmed.lowercased()
        return query.isEmpty || collection.name.lowercased().contains(query) || collection.symbol.lowercased().contains(query)
    }

    private var owned: [OwnedNft] {
        app.balances.ownedNfts.filter { matches($0.collection.asset) || $0.tokenId.contains(search.trimmed) }
    }

    private var others: [Listed<NftCollection>] {
        let ownedAddresses = Set(app.balances.ownedNfts.map { $0.collection.asset.address.lowercased() })
        return app.assets.collections.filter { !ownedAddresses.contains($0.asset.address.lowercased()) && matches($0.asset) }
    }

    private func row(collection: Listed<NftCollection>, tokenId id: String?) -> some View {
        let isSelected = contract.map { Address.isSame($0, collection.asset.address) } == true && (id == nil || id == tokenId)
        return Button {
            onSelect(collection.asset.address, id ?? "")
        } label: {
            HStack(spacing: 8) {
                Text(collection.asset.symbol)
                    .font(.mono(.callout, weight: .semibold))
                if collection.isVerified {
                    Image(systemName: "checkmark.seal")
                        .font(.mono(.caption))
                }
                Text(collection.asset.name)
                    .font(.mono(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let id {
                    Text("#\(id)")
                        .font(.mono(.footnote, weight: .medium))
                }
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
