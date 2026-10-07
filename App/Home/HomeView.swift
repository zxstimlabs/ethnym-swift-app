import EthnymKit
import SwiftUI

/// Wallets and balances: the web wallet's Home tab.
struct HomeView: View {
    enum Sheet: String, Identifiable {
        case create
        case importWallet
        case export
        case delete
        case manage
        case receive
        case addToken
        case addCollection

        var id: Self { self }
    }

    @Environment(AppModel.self) private var app
    @State private var sheet: Sheet?

    var body: some View {
        NavigationStack {
            List {
                if app.wallets.wallets.isEmpty {
                    WelcomeSection(sheet: $sheet)
                } else {
                    WalletSection(sheet: $sheet)
                    if !app.wallets.walletsNeedingMigration.isEmpty {
                        MigrationSection()
                    }
                    BalancesSection(sheet: $sheet)
                }
            }
            .animation(.house, value: app.wallets.activeWalletID)
            .animation(.house, value: app.wallets.wallets.count)
            .tabTitle("Wallets")
            .toolbar { AppHeader() }
            .refreshable { await app.refreshBalances() }
            .sheet(item: $sheet) { sheet in
                content(for: sheet)
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
        case .manage: ManagePopUp(sheet: $sheet)
        case .receive: ReceiveView()
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

/// The wallet picker, the active address, and Receive / Manage. Balances are in their own section.
private struct WalletSection: View {
    @Binding var sheet: HomeView.Sheet?
    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            SectionIntro("Wallets", info: "The wallet you're using. Switch wallets here, or create, import and export them under Manage.") {
                if app.settings.offlineMode {
                    Tag(text: "Offline", systemImage: "wifi.slash")
                }
            }

            WalletPicker()

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
                // Manage stays with no wallet selected, to create or import one.
                HStack(spacing: 10) {
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
            .padding(.vertical, 6)
        }
    }
}

/// Create, import, export and delete, in a pop-up. The web wallet keeps these under Manage in its
/// wallet card. Choosing one swaps this pop-up for that screen.
private struct ManagePopUp: View {
    @Binding var sheet: HomeView.Sheet?
    @Environment(AppModel.self) private var app

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
    }

    private func row(_ title: String, systemImage: String, opens destination: HomeView.Sheet, role: ButtonRole? = nil) -> some View {
        Button(role: role) {
            sheet = destination
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
