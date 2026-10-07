import BigInt
import EthnymKit
import SwiftUI

/// Token and NFT balances for the active wallet.
struct BalancesSection: View {
    enum Kind: String, CaseIterable, Identifiable {
        case tokens = "Tokens"
        case nfts = "NFTs"

        var id: Self { self }
    }

    @Binding var sheet: HomeView.Sheet?
    @Environment(AppModel.self) private var app
    @State private var kind: Kind = .tokens

    var body: some View {
        Section {
            SectionIntro("Balances", info: "Ether, then the tokens and NFTs this wallet holds. Add any that aren't listed by their contract address.") {
                if app.balances.tokensState.isLoading || app.balances.nftsState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                }
            }
            .animation(.house, value: app.balances.tokensState)

            Picker("Balances", selection: $kind.animation(.house)) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden, edges: .bottom)
            .sensoryFeedback(.selection, trigger: kind)

            if app.wallets.activeWallet == nil {
                Text(app.wallets.wallets.isEmpty ? "Create or import a wallet to see its balances." : "Select a wallet to see its balances.")
                    .font(.mono(.footnote))
                    .foregroundStyle(.secondary)
            } else {
                if app.settings.offlineMode {
                    Label("Offline mode is on. Balances aren't fetched.", systemImage: "wifi.slash")
                        .font(.mono(.footnote))
                        .foregroundStyle(.secondary)
                }
                switch kind {
                case .tokens: TokenRows(sheet: $sheet)
                case .nfts: NftRows(sheet: $sheet)
                }
            }
        }
    }
}

private struct TokenRows: View {
    @Binding var sheet: HomeView.Sheet?
    @Environment(AppModel.self) private var app

    var body: some View {
        let balances = app.balances
        let rows = visibleTokens
        NativeBalanceRow()
        ForEach(rows) { token in
            TokenBalanceRow(
                token: token,
                balance: balances.balance(of: token.asset.address),
                isLoading: balances.tokensState.isLoading,
                isCustom: app.assets.isCustom(token: token.asset.address)
            )
        }
        if rows.isEmpty && !app.settings.offlineMode {
            Text(balances.tokensState == .loaded ? "No token balances." : "Loading token balances…")
                .font(.mono(.footnote))
                .foregroundStyle(.secondary)
        }
        if let error = balances.tokensState.errorMessage {
            FieldHint(error, kind: .error)
        }
        Button {
            sheet = .addToken
        } label: {
            Label("Add custom token", systemImage: "plus")
                .font(.mono(.footnote))
        }
        .foregroundStyle(.secondary)
    }

    /// List tokens appear once they hold a balance; custom tokens always appear.
    private var visibleTokens: [Listed<Token>] {
        let balances = app.balances
        let visible = app.assets.tokens.filter { token in
            if app.assets.isCustom(token: token.asset.address) { return true }
            guard !app.settings.offlineMode else { return false }
            return (balances.balance(of: token.asset.address) ?? 0) > 0
        }
        return balances.sorted(visible)
    }
}

/// Ether, always first in the Tokens list, as on the web wallet.
private struct NativeBalanceRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let balances = app.balances
        let currency = app.chain.nativeCurrency
        BalanceRow(
            symbol: currency.symbol,
            name: currency.name,
            isVerified: true,
            balance: balances.native,
            decimals: currency.decimals,
            isLoading: balances.nativeState.isLoading
        )
        .contextMenu {
            if let native = balances.native {
                CopyMenuButton(title: "Copy Balance", text: Units.format(native, decimals: currency.decimals))
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
        }
        if let error = balances.nativeState.errorMessage {
            FieldHint(error, kind: .error)
        }
    }

    private func refresh() {
        guard let address = app.wallets.activeWallet?.address, let service = app.service else { return }
        Task { await app.balances.refreshNative(address: address, service: service) }
    }
}

private struct TokenBalanceRow: View {
    let token: Listed<Token>
    let balance: BigUInt?
    let isLoading: Bool
    let isCustom: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        BalanceRow(
            symbol: token.asset.symbol,
            name: token.asset.name,
            isVerified: token.isVerified,
            balance: balance,
            decimals: token.asset.decimals,
            isLoading: isLoading
        )
        .contextMenu {
            CopyMenuButton(title: "Copy Contract Address", text: token.asset.address)
            if let balance {
                CopyMenuButton(title: "Copy Balance", text: Units.format(balance, decimals: token.asset.decimals))
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
            if isCustom {
                Button("Remove", systemImage: "trash", role: .destructive) { remove() }
            }
        }
        .swipeActions {
            if isCustom {
                Button("Remove", systemImage: "trash", role: .destructive) { remove() }
            }
        }
    }

    private func refresh() {
        guard let address = app.wallets.activeWallet?.address, let service = app.service else { return }
        Task { await app.balances.refreshToken(token.asset.address, address: address, service: service) }
    }

    private func remove() {
        withAnimation(.house) { app.assets.removeToken(token.asset.address) }
    }
}

/// Symbol, name and amount: one line of the Tokens list.
private struct BalanceRow: View {
    let symbol: String
    let name: String
    let isVerified: Bool
    let balance: BigUInt?
    let decimals: Int
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(symbol)
                        .font(.mono(.callout, weight: .semibold))
                    if isVerified {
                        Image(systemName: "checkmark.seal")
                            .font(.mono(.caption))
                            .accessibilityLabel("Verified")
                    }
                }
                Text(name)
                    .font(.mono(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Group {
                if let balance {
                    Text(Units.format(balance, decimals: decimals, maxFractionDigits: 6))
                        .contentTransition(.numericText())
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                        .loadingPulse(isLoading)
                }
            }
            .font(.mono(.callout, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .animation(.house, value: balance)
    }
}

private struct NftRows: View {
    @Binding var sheet: HomeView.Sheet?
    @Environment(AppModel.self) private var app

    var body: some View {
        let balances = app.balances
        let owned = balances.ownedNfts
        ForEach(owned) { nft in
            NftRow(collection: nft.collection, tokenId: nft.tokenId)
        }
        ForEach(unownedCustomCollections, id: \.address) { collection in
            NftRow(collection: Listed(collection, isVerified: false), tokenId: nil)
        }
        if owned.isEmpty && unownedCustomCollections.isEmpty && !app.settings.offlineMode {
            Text(balances.nftsState.isLoading ? "Loading NFTs…" : "No NFTs found.")
                .font(.mono(.footnote))
                .foregroundStyle(.secondary)
                .loadingPulse(balances.nftsState.isLoading)
        }
        if let error = balances.nftsState.errorMessage {
            FieldHint(error, kind: .error)
        }
        Button {
            sheet = .addCollection
        } label: {
            Label("Add custom NFT collection", systemImage: "plus")
                .font(.mono(.footnote))
        }
        .foregroundStyle(.secondary)
    }

    /// Custom collections are listed even when the wallet owns none of their tokens.
    private var unownedCustomCollections: [NftCollection] {
        app.assets.customCollections.filter { collection in
            !app.balances.ownedNfts.contains { Address.isSame($0.collection.asset.address, collection.address) }
        }
    }
}

private struct NftRow: View {
    let collection: Listed<NftCollection>
    let tokenId: String?
    @Environment(AppModel.self) private var app

    var body: some View {
        let isCustom = app.assets.isCustom(collection: collection.asset.address)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(collection.asset.symbol)
                        .font(.mono(.callout, weight: .semibold))
                    if collection.isVerified {
                        Image(systemName: "checkmark.seal")
                            .font(.mono(.caption))
                            .accessibilityLabel("Verified")
                    }
                }
                Text(collection.asset.name)
                    .font(.mono(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(tokenId.map { "#\($0)" } ?? "—")
                .font(.mono(.callout, weight: .medium))
                .foregroundStyle(tokenId == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contextMenu {
            CopyMenuButton(title: "Copy Contract Address", text: collection.asset.address)
            if let tokenId {
                CopyMenuButton(title: "Copy Token ID", text: tokenId)
            }
            if isCustom {
                Button("Remove Collection", systemImage: "trash", role: .destructive) { remove() }
            }
        }
        .swipeActions {
            if isCustom {
                Button("Remove", systemImage: "trash", role: .destructive) { remove() }
            }
        }
    }

    private func remove() {
        withAnimation(.house) { app.assets.removeCollection(collection.asset.address) }
    }
}

/// A context-menu item that copies.
struct CopyMenuButton: View {
    let title: String
    let text: String

    var body: some View {
        Button(title, systemImage: "doc.on.doc") {
            Pasteboard.copy(text, isSecret: false)
        }
    }
}
