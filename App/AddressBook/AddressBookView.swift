import EthnymKit
import SwiftUI

/// Saved contacts, searchable by name, address, tag or note.
struct AddressBookView: View {
    @Environment(AppModel.self) private var app
    @State private var search = ""
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            let contacts = ContactValidation.filter(app.contacts.contacts, query: search)
            List {
                ForEach(contacts) { contact in
                    ContactRow(contact: contact)
                }
                .onDelete { offsets in
                    withAnimation(.house) { app.contacts.delete(atOffsets: offsets, in: contacts) }
                }
            }
            .overlay {
                if contacts.isEmpty {
                    if app.contacts.contacts.isEmpty {
                        EmptyState("No contacts yet", systemImage: "person.crop.rectangle.stack", message: "Save addresses you send to often. They show up in every recipient field.") {
                            Button("Add Contact") { isAdding = true }
                                .buttonStyle(.primary)
                                .frame(maxWidth: 220)
                        }
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .animation(.house, value: contacts)
            .searchable(text: $search, prompt: "Name, address, tag or note")
            .navigationTitle("Address Book")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Contact", systemImage: "plus") { isAdding = true }
                }
                if !app.contacts.contacts.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddContactView()
            }
        }
    }
}

private struct ContactRow: View {
    let contact: Contact
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(contact.name)
                    .font(.mono(.callout, weight: .semibold))
                Spacer()
                if let chain = contact.chain {
                    Tag(text: Formatting.chainLabel(chain))
                }
            }
            HStack(alignment: .top, spacing: 8) {
                AddressText(address: contact.address, style: .caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CopyButton(text: contact.address)
                    .buttonStyle(.borderless)
                    .font(.mono(.footnote))
            }
            if !contact.metadata.note.isEmpty {
                Text(contact.metadata.note)
                    .font(.mono(.caption))
                    .foregroundStyle(.secondary)
            }
            if !contact.metadata.tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(contact.metadata.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.mono(.caption2, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.fill, in: .capsule)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            CopyMenuButton(title: "Copy Address", text: contact.address)
            Link(destination: app.chain.addressURL(contact.address)) {
                Label("View on Etherscan", systemImage: "arrow.up.right.square")
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation(.house) { app.contacts.delete(contact) }
            }
        }
    }
}

/// Adds a contact. ENS names are resolved and saved as the address they point to.
struct AddContactView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var chain = ""
    @State private var tags = ""
    @State private var note = ""
    @State private var nameTouched = false
    @State private var chainTouched = false
    @State private var resolution = ENSResolution()
    @State private var added = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .onChange(of: name) { nameTouched = true }
                        FieldHint(prompt: "Please enter a name", error: ContactValidation.validateName(name).map { FieldError($0, isPrompt: true) }, isTouched: nameTouched)
                    }
                    AddressField(
                        placeholder: "Address (0x...) or ENS (.eth)",
                        text: $address,
                        resolution: resolution,
                        error: addressError,
                        showsAddressBook: false
                    )
                } header: {
                    SectionHeader("Contact")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Chain ID (optional, e.g. 1)", text: $chain)
                            .keyboardType(.numberPad)
                            .onChange(of: chain) { chainTouched = true }
                        FieldHint(prompt: "Optional — leave blank for chain-agnostic", error: ContactValidation.validateChain(chain).map { FieldError($0) }, isTouched: chainTouched)
                    }
                    TextField("Tags (comma-separated, e.g. defi, team)", text: $tags)
                        .textInputAutocapitalization(.never)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1 ... 4)
                } header: {
                    SectionHeader("Details")
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(!canAdd)
                }
            }
            .sensoryFeedback(.success, trigger: added) { _, new in new }
        }
    }

    private var addressError: FieldError? {
        ContactValidation.validateAddress(address, existingAddresses: app.contacts.existingAddresses).map {
            FieldError($0, isPrompt: $0 == "Please enter an address")
        }
    }

    /// The address to save: a valid address as typed, or what the ENS name resolved to.
    private var resolvedAddress: String? {
        resolution.address(for: address).flatMap { resolved in
            app.contacts.existingAddresses.contains(resolved.lowercased()) ? nil : resolved
        }
    }

    private var canAdd: Bool {
        ContactValidation.validateName(name) == nil
            && addressError == nil
            && ContactValidation.validateChain(chain) == nil
            && resolvedAddress != nil
    }

    private func add() {
        guard let resolvedAddress else { return }
        app.contacts.add(Contact(
            address: resolvedAddress,
            name: name.trimmed,
            chain: Int(chain.trimmed),
            metadata: .init(tags: ContactValidation.parseTags(tags), version: "0.0.1", note: note.trimmed)
        ))
        added = true
        dismiss()
    }
}
