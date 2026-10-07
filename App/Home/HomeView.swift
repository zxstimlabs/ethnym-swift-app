import EthnymKit
import SwiftUI

/// Wallets and balances: the web wallet's Home tab.
struct HomeView: View {
    enum Sheet: String, Identifiable {
        case manage
        case receive
        case addToken
        case addCollection

        var id: Self { self }
    }

    /// Screens that take input, full screen so they can't be swiped away. Opened from Manage, or from
    /// the Wallets card before the first wallet exists.
    enum Flow: String, Identifiable {
        case create
        case importWallet
        case export
        case delete

        var id: Self { self }

        @ViewBuilder
        var screen: some View {
            switch self {
            case .create: CreateWalletView()
            case .importWallet: ImportWalletView()
            case .export: ExportWalletView()
            case .delete: DeleteWalletView()
            }
        }
    }

    @Environment(AppModel.self) private var app
    @State private var sheet: Sheet?
    @State private var flow: Flow?

    var body: some View {
        NavigationStack {
            List {
                WalletSection(sheet: $sheet, flow: $flow)
                if !app.wallets.walletsNeedingMigration.isEmpty {
                    MigrationSection()
                }
                BalancesSection(sheet: $sheet)
            }
            .animation(.house, value: app.wallets.activeWalletID)
            .animation(.house, value: app.wallets.wallets.count)
            .tabTitle("Wallets")
            .toolbar { AppHeader() }
            .refreshable { await app.refreshBalances() }
            .sheet(item: $sheet) { sheet in
                content(for: sheet)
            }
            .fullScreenCover(item: $flow) { flow in
                flow.screen
                    .environment(\.flowExit, FlowExit { self.flow = nil })
            }
        }
    }

    @ViewBuilder
    private func content(for sheet: Sheet) -> some View {
        switch sheet {
        case .manage: ManagePopUp(sheet: $sheet)
        case .receive: ReceiveView()
        case .addToken: AddCustomTokenView()
        case .addCollection: AddCustomNftView()
        }
    }
}

/// The wallet picker, the active address, and Receive / Manage. Balances are in their own section.
/// Until the first wallet exists, a prompt and Create / Import take the same rows, so adding one
/// barely moves the layout.
private struct WalletSection: View {
    @Binding var sheet: HomeView.Sheet?
    @Binding var flow: HomeView.Flow?
    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            SectionIntro("Wallets", info: "The wallet you're using. Switch wallets here, or create, import and export them under Manage.") {
                if app.settings.offlineMode {
                    Tag(text: "Offline", systemImage: "wifi.slash")
                }
            }

            if app.wallets.wallets.isEmpty {
                Text("Create or import a wallet")
                    .font(.mono(.title3, weight: .bold))
                    .foregroundStyle(.secondary)
            } else {
                WalletPicker()
            }

            VStack(alignment: .leading, spacing: 14) {
                if let wallet = app.wallets.activeWallet {
                    HStack(alignment: .top, spacing: 12) {
                        AddressText(address: wallet.address, style: .caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CopyButton(text: wallet.address)
                            .buttonStyle(.borderless)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                HStack(spacing: 10) {
                    if app.wallets.wallets.isEmpty {
                        Button {
                            flow = .create
                        } label: {
                            Label("Create", systemImage: "plus")
                        }
                        .buttonStyle(.primary)

                        Button {
                            flow = .importWallet
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.secondary)
                    } else {
                        // Manage stays with no wallet selected, to create or import one.
                        Button {
                            sheet = .receive
                        } label: {
                            Label("Receive", systemImage: "qrcode")
                        }
                        .buttonStyle(.primary)
                        .disabled(app.wallets.activeWallet == nil)

                        Button {
                            sheet = .manage
                        } label: {
                            Label("Manage", systemImage: "ellipsis.circle")
                        }
                        .buttonStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

/// Create, import, export and delete, in a pop-up. The web wallet keeps these under Manage in its
/// wallet card. Choosing one opens that screen full screen over this pop-up: Back returns here, and
/// X closes both.
private struct ManagePopUp: View {
    @Binding var sheet: HomeView.Sheet?
    @Environment(AppModel.self) private var app
    @State private var flow: HomeView.Flow?

    var body: some View {
        PopUp("Manage", systemImage: "ellipsis.circle") {
            VStack(spacing: 0) {
                row("Create Wallet", systemImage: "plus", opens: .create)
                Divider()
                row("Import Wallet", systemImage: "square.and.arrow.down", opens: .importWallet)
                Divider()
                row("Export", systemImage: "square.and.arrow.up", opens: .export)
                Divider()
                row("Delete Wallet", systemImage: "trash", opens: .delete, role: .destructive)
                    .disabled(app.wallets.activeWallet == nil)
            }
        }
        .fullScreenCover(item: $flow) { flow in
            // Closing the pop-up closes the screen over it too.
            flow.screen
                .environment(\.flowExit, FlowExit(returnsToPopUp: true) { sheet = nil })
        }
    }

    private func row(_ title: String, systemImage: String, opens destination: HomeView.Flow, role: ButtonRole? = nil) -> some View {
        Button(role: role) {
            flow = destination
        } label: {
            Label(title, systemImage: systemImage)
                .font(.mono(.body))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .contentShape(.rect)
        }
        .buttonStyle(PopUpRowButtonStyle())
    }
}

/// A full-width row: red for destructive actions, dimmed while pressed or disabled.
private struct PopUpRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.role == .destructive ? Color.red : Color.primary)
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.3)
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
