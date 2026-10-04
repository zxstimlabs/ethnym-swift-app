import EthnymKit
import SwiftUI

/// Adds an ERC-20 by contract address, after reading its name, symbol and decimals on-chain.
struct AddCustomTokenView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        AddAssetForm(
            title: "Add Token",
            placeholder: "Token address (0x...)",
            failure: "Could not fetch token metadata. Check the address and try again."
        ) { address, service in
            let metadata = try await service.tokenMetadata(address)
            return AssetPreview(
                name: metadata.name,
                symbol: metadata.symbol,
                detail: "\(metadata.decimals) decimals",
                add: { app.assets.addToken(Token(chainId: app.chain.id, address: address, name: metadata.name, symbol: metadata.symbol, decimals: metadata.decimals)) }
            )
        }
    }
}

/// Adds an ERC-721 collection by contract address.
struct AddCustomNftView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        AddAssetForm(
            title: "Add NFT Collection",
            placeholder: "Collection address (0x...)",
            failure: "Could not fetch collection metadata. Check the address and try again."
        ) { address, service in
            let metadata = try await service.collectionMetadata(address)
            return AssetPreview(
                name: metadata.name,
                symbol: metadata.symbol,
                detail: "ERC-721",
                add: { app.assets.addCollection(NftCollection(chainId: app.chain.id, address: address, name: metadata.name, symbol: metadata.symbol)) }
            )
        }
    }
}

struct AssetPreview {
    let name: String
    let symbol: String
    let detail: String
    let add: () -> Void
}

private struct AddAssetForm: View {
    let title: String
    let placeholder: String
    let failure: String
    let lookUp: (String, EthereumService) async throws -> AssetPreview

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var preview: AssetPreview?
    @State private var error: String?
    @State private var isLoading = false
    @State private var added = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField(placeholder, text: $address)
                            .font(.mono(.callout))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(lookUpAddress)
                        QRScanButton { address = $0 }
                    }
                    Button(action: lookUpAddress) {
                        HStack {
                            Text("Look up")
                            Spacer()
                            if isLoading { ProgressView() }
                        }
                    }
                    .disabled(isLoading || address.trimmed.isEmpty)
                } footer: {
                    if let error {
                        FieldHint(error, kind: .error)
                    }
                }

                if let preview {
                    Section {
                        LabeledContent("Name", value: preview.name)
                        LabeledContent("Symbol", value: preview.symbol)
                        LabeledContent("Type", value: preview.detail)
                    } header: {
                        SectionHeader("Found")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .font(.mono(.callout))
            .animation(.house, value: preview?.symbol)
            .animation(.house, value: error)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        preview?.add()
                        added = true
                        dismiss()
                    }
                    .disabled(preview == nil)
                }
            }
            .onChange(of: address) {
                preview = nil
                error = nil
            }
            .sensoryFeedback(.success, trigger: added) { _, new in new }
            .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        }
        .presentationDetents([.medium, .large])
    }

    private func lookUpAddress() {
        let trimmed = address.trimmed
        guard trimmed.isHexAddress else {
            error = "Must be a valid 0x address (42 chars)"
            return
        }
        guard let service = app.service else {
            error = "Offline mode is on. Turn it off in Settings to look up contracts."
            return
        }
        isLoading = true
        error = nil
        Task {
            defer { isLoading = false }
            do {
                preview = try await lookUp(Address.checksummed(trimmed), service)
            } catch {
                self.error = failure
            }
        }
    }
}
