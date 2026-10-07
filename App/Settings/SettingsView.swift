import EthnymKit
import SwiftUI

/// The active wallet and Log Out, RPC endpoints, offline mode, the VPN relay placeholder and
/// appearance. Opens from the header.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var theme: AppTheme = .system
    @State private var newName = ""
    @State private var newURL = ""
    @State private var addError: String?

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                Section {
                    if let wallet = app.wallets.activeWallet {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wallet.name)
                                .font(.mono(.callout, weight: .semibold))
                            AddressText(address: wallet.address, style: .caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No wallet selected")
                            .foregroundStyle(.secondary)
                    }
                    // Deselects the wallet, as the web wallet's Log Out does.
                    Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right") {
                        app.wallets.select(nil)
                        dismiss()
                    }
                    .disabled(app.wallets.activeWallet == nil)
                } header: {
                    SectionHeader("Wallet")
                } footer: {
                    Text("Logging out deselects the wallet. Its keystore stays on this device.")
                        .font(.mono(.caption))
                }

                Section {
                    LabeledContent {
                        Tag(text: settings.settings.activeRpc.map { $0.name ?? "custom" } ?? "default")
                    } label: {
                        Text("Active")
                    }
                    Text(settings.rpcURL.absoluteString)
                        .font(.mono(.caption))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if settings.isUsingCustomRpc {
                        Button("Reset to Default") {
                            withAnimation(.house) { settings.resetRpcToDefault() }
                        }
                    }
                } header: {
                    SectionHeader("RPC endpoint")
                }

                Section {
                    if settings.settings.rpcList.isEmpty {
                        Text("No custom RPCs saved yet.")
                            .font(.mono(.footnote))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(settings.settings.rpcList) { entry in
                        let isActive = settings.settings.activeRpc?.id == entry.id
                        Button {
                            withAnimation(.house) { settings.selectRpc(entry) }
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let name = entry.name {
                                        Text(name)
                                            .font(.mono(.callout, weight: .medium))
                                    }
                                    Text(entry.url)
                                        .font(.mono(.caption))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                if isActive {
                                    Image(systemName: "checkmark")
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isActive ? .isSelected : [])
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation(.house) { settings.deleteRpc(entry) }
                            }
                        }
                    }
                } header: {
                    SectionHeader("Saved RPCs")
                } footer: {
                    if !settings.settings.rpcList.isEmpty {
                        Text("Tap to make active. Swipe to delete.")
                            .font(.mono(.caption))
                    }
                }
                .sensoryFeedback(.selection, trigger: settings.settings.activeRpc)

                Section {
                    TextField("Name (optional, e.g. Alchemy)", text: $newName)
                    TextField("https://...", text: $newURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: newURL) { addError = nil }
                    Button("Save", systemImage: "square.and.arrow.down") {
                        if let error = settings.addRpc(name: newName, url: newURL) {
                            addError = error
                        } else {
                            newName = ""
                            newURL = ""
                        }
                    }
                    .disabled(newURL.trimmed.isEmpty)
                } header: {
                    SectionHeader("Add RPC")
                } footer: {
                    if let addError { FieldHint(addError, kind: .error) }
                }

                Section {
                    Toggle(isOn: $settings.offlineMode.animation(.house)) {
                        Label(settings.offlineMode ? "Offline: fetching disabled" : "Online", systemImage: settings.offlineMode ? "wifi.slash" : "wifi")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .tint(Theme.toggleTint)
                    if settings.offlineMode {
                        Label("All balance and network queries are paused. You can still sign transaction JSON; turn offline mode off before broadcasting.", systemImage: "info.circle")
                            .font(.mono(.caption))
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } header: {
                    SectionHeader("Offline mode")
                } footer: {
                    Text("Disables all network fetching: balances, gas prices, ENS lookups.")
                        .font(.mono(.caption))
                }
                .sensoryFeedback(.selection, trigger: settings.offlineMode)

                Section {
                    LabeledContent {
                        Tag(text: "coming soon")
                    } label: {
                        Label("VPN Relay", systemImage: "checkmark.shield")
                    }
                } header: {
                    SectionHeader("Privacy")
                } footer: {
                    Text("Route RPC traffic through a built-in VPN relay to improve privacy and prevent IP-based tracking by node providers.")
                        .font(.mono(.caption))
                }

                Section {
                    Picker("Theme", selection: $theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    SectionHeader("Appearance")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    LabeledContent("Network", value: app.chain.name)
                } header: {
                    SectionHeader("About")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension Bundle {
    var versionString: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(version) (\(build))"
    }
}
