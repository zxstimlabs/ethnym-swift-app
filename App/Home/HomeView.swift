import EthnymKit
import SwiftUI

/// Wallets and balances: the web wallet's Home tab.
struct HomeView: View {
    enum Sheet: String, Identifiable {
        case create
        case importWallet
        case export
        case delete
        case send
        case receive
        case addToken
        case addCollection

        var id: Self { self }
    }

    @Environment(AppModel.self) private var app
    @State private var sheet: Sheet?
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            List {
                if app.wallets.wallets.isEmpty {
                    WelcomeSection(sheet: $sheet)
                } else {
                    WalletSection(sheet: $sheet, zoom: zoom)
                    if !app.wallets.walletsNeedingMigration.isEmpty {
                        MigrationSection()
                    }
                    BalancesSection(sheet: $sheet)
                }
            }
            .animation(.house, value: app.wallets.activeWalletID)
            .animation(.house, value: app.wallets.wallets.count)
            .navigationTitle("Wallets")
            .toolbar { toolbar }
            .refreshable { await app.refreshBalances() }
            .sheet(item: $sheet) { sheet in
                content(for: sheet)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if app.settings.offlineMode {
            ToolbarItem(placement: .topBarLeading) {
                Label("Offline", systemImage: "wifi.slash")
                    .labelStyle(.titleAndIcon)
                    .font(.mono(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Manage", systemImage: "ellipsis.circle") {
                Section {
                    Button("Create Wallet", systemImage: "plus") { sheet = .create }
                    Button("Import Wallet", systemImage: "square.and.arrow.down") { sheet = .importWallet }
                }
                if !app.wallets.wallets.isEmpty {
                    Section {
                        Button("Export", systemImage: "square.and.arrow.up") { sheet = .export }
                        Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right") {
                            app.wallets.select(nil)
                        }
                        .disabled(app.wallets.activeWallet == nil)
                    }
                    Section {
                        Button("Delete Wallet", systemImage: "trash", role: .destructive) { sheet = .delete }
                            .disabled(app.wallets.activeWallet == nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func content(for sheet: Sheet) -> some View {
        switch sheet {
        case .create: CreateWalletView()
        case .importWallet: ImportWalletView()
        case .export: ExportWalletView()
        case .delete: DeleteWalletView()
        case .send: SendView().navigationTransition(.zoom(sourceID: Sheet.send, in: zoom))
        case .receive: ReceiveView().navigationTransition(.zoom(sourceID: Sheet.receive, in: zoom))
        case .addToken: AddCustomTokenView()
        case .addCollection: AddCustomNftView()
        }
    }
}

/// Shown until the first wallet exists.
private struct WelcomeSection: View {
    @Binding var sheet: HomeView.Sheet?

    var body: some View {
        Section {
            EmptyState("No wallets yet", systemImage: "wallet.bifold", message: "Create a new wallet or import an existing one to get started. Keys are encrypted with your password and never leave this device.") {
                VStack(spacing: 10) {
                    Button("Create Wallet") { sheet = .create }
                        .buttonStyle(.primary)
                    Button("Import Wallet") { sheet = .importWallet }
                        .buttonStyle(.secondary)
                }
                .frame(maxWidth: 280)
            }
        }
        .listRowBackground(Color.clear)
    }
}

/// The wallet picker, the active address, its ether balance, and Receive / Send.
private struct WalletSection: View {
    @Binding var sheet: HomeView.Sheet?
    let zoom: Namespace.ID
    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            WalletPicker()

            if let wallet = app.wallets.activeWallet {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        AddressText(address: wallet.address, style: .footnote)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CopyButton(text: wallet.address)
                            .buttonStyle(.borderless)
                    }
                    EtherBalance()
                    HStack(spacing: 10) {
                        Button {
                            sheet = .receive
                        } label: {
                            Label("Receive", systemImage: "qrcode")
                        }
                        .buttonStyle(.secondary)
                        .matchedTransitionSource(id: HomeView.Sheet.receive, in: zoom)

                        Button {
                            sheet = .send
                        } label: {
                            Label("Send", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.primary)
                        .matchedTransitionSource(id: HomeView.Sheet.send, in: zoom)
                    }
                }
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            SectionHeader("Wallet")
        }
    }
}

private struct WalletPicker: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            Picker("Wallet", selection: Binding(get: { app.wallets.activeWalletID }, set: { app.wallets.select($0) })) {
                ForEach(app.wallets.wallets) { wallet in
                    Text(wallet.name)
                        .badge(Formatting.truncateAddress(wallet.address))
                        .tag(Optional(wallet.id))
                }
                Text("No wallet selected")
                    .tag(String?.none)
            }
        } label: {
            HStack(spacing: 8) {
                Text(app.wallets.activeWallet?.name ?? "Select a wallet")
                    .font(.mono(.title3, weight: .bold))
                    .foregroundStyle(app.wallets.activeWallet == nil ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.mono(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Wallet: \(app.wallets.activeWallet?.name ?? "none selected")")
        .sensoryFeedback(.selection, trigger: app.wallets.activeWalletID)
    }
}

/// The big ether number. Digits roll when it changes.
private struct EtherBalance: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let balances = app.balances
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if let native = balances.native {
                    Text(Units.format(native, decimals: 18, maxFractionDigits: 6))
                        .contentTransition(.numericText())
                } else {
                    Text(app.settings.offlineMode ? "—" : "0.0000")
                        .foregroundStyle(.secondary)
                        .loadingPulse(balances.nativeState.isLoading)
                }
            }
            .font(.mono(size: 34, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            Text(app.chain.nativeCurrency.symbol)
                .font(.mono(.title3, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .animation(.house, value: balances.native)
        .accessibilityElement(children: .combine)
        if let error = balances.nativeState.errorMessage {
            FieldHint(error, kind: .error)
        }
    }
}

/// Wallets saved by an older web wallet version, which only need their metadata updated.
private struct MigrationSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let count = app.wallets.walletsNeedingMigration.count
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("\(count) wallet\(count == 1 ? " is" : "s are") on an older storage format", systemImage: "exclamationmark.triangle")
                    .font(.mono(.footnote, weight: .semibold))
                Text("Migrating updates metadata to version \(WalletKeystore.currentUmVersion). Keys are not changed.")
                    .font(.mono(.caption))
                    .foregroundStyle(.secondary)
                Button("Migrate \(count) wallet\(count == 1 ? "" : "s")") {
                    withAnimation(.house) { app.wallets.migrateAll() }
                }
                .buttonStyle(.chip(selected: true))
            }
            .padding(.vertical, 4)
        }
    }
}
