import EthnymKit
import SwiftUI

/// An address input that also takes ENS names, with lookup, QR scanning and the address book.
/// ENS names resolve on their own after a short pause; the search button retries.
struct AddressField: View {
    let placeholder: String
    @Binding var text: String
    let resolution: ENSResolution
    var error: FieldError?
    var prompt: String = RecipientValidation.emptyMessage
    var showsAddressBook = true

    @Environment(AppModel.self) private var app
    @State private var isTouched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.mono(.callout))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)

                Group {
                    Button("Look up ENS", systemImage: "magnifyingglass") {
                        resolution.resolve(text, service: app.service)
                    }
                    .disabled(!text.isENSName)
                    QRScanButton { text = $0 }
                    if showsAddressBook {
                        AddressBookPickerButton { text = $0 }
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
            }
            hint
        }
        .onChange(of: text) { isTouched = true }
        .task(id: text) {
            resolution.resolve(text, service: app.service, delay: .milliseconds(450))
        }
    }

    @ViewBuilder
    private var hint: some View {
        if isTouched, error == nil, text.isENSName {
            switch resolution.state {
            case .resolving, .idle:
                FieldHint("Resolving \(text.trimmed.lowercased())…", kind: .progress)
            case let .resolved(_, address):
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.mono(.caption2, weight: .bold))
                    AddressText(address: address, style: .caption)
                }
            case .notFound:
                FieldHint("Invalid ENS: the name doesn't resolve to an address", kind: .error)
            case .failed:
                FieldHint("Failed to resolve ENS", kind: .error)
            case .offline:
                FieldHint("Offline mode is on, so ENS names can't be resolved", kind: .error)
            }
        } else {
            FieldHint(prompt: prompt, error: error, isTouched: isTouched)
        }
    }
}

/// Picks an address from your own wallets or your contacts.
struct AddressBookPickerButton: View {
    let onSelect: (String) -> Void
    @State private var isPresented = false

    var body: some View {
        Button("Pick from address book", systemImage: "person.crop.rectangle.stack") {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            AddressBookPicker { address in
                onSelect(address)
                isPresented = false
            }
        }
    }
}

private struct AddressBookPicker: View {
    let onSelect: (String) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                let wallets = filteredWallets
                let contacts = ContactValidation.filter(app.contacts.contacts, query: search)
                if !wallets.isEmpty {
                    Section {
                        ForEach(wallets) { wallet in
                            row(name: wallet.name, address: wallet.address, isCurrent: wallet.id == app.wallets.activeWalletID)
                        }
                    } header: {
                        SectionHeader("My addresses")
                    }
                }
                if !contacts.isEmpty {
                    Section {
                        ForEach(contacts) { contact in
                            row(name: contact.name, address: contact.address, isCurrent: false)
                        }
                    } header: {
                        SectionHeader("Contacts")
                    }
                }
                if wallets.isEmpty && contacts.isEmpty {
                    EmptyState(search.isEmpty ? "No addresses saved yet" : "No results", systemImage: "person.crop.rectangle.stack", message: search.isEmpty ? "Add contacts in the Address Book tab." : "Nothing matches “\(search)”.")
                    .listRowBackground(Color.clear)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or address")
            .navigationTitle("Address Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filteredWallets: [WalletKeystore] {
        let query = search.trimmed.lowercased()
        guard !query.isEmpty else { return app.wallets.wallets }
        return app.wallets.wallets.filter { $0.name.lowercased().contains(query) || $0.address.lowercased().contains(query) }
    }

    private func row(name: String, address: String, isCurrent: Bool) -> some View {
        Button {
            onSelect(address)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.mono(.callout, weight: .medium))
                    if isCurrent { Tag(text: "current") }
                }
                AddressText(address: address, style: .caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
