import Foundation
import Observation

/// The address book.
@MainActor
@Observable
public final class ContactStore {
    public private(set) var contacts: [Contact]
    public private(set) var storageError: String?

    @ObservationIgnored private let storage: any DataStorage
    static let key = "address-book"

    public init(storage: any DataStorage) {
        self.storage = storage
        self.contacts = storage.decode([Contact].self, for: Self.key) ?? []
    }

    /// Lowercased, for duplicate checks.
    public var existingAddresses: [String] {
        contacts.map { $0.address.lowercased() }
    }

    public func add(_ contact: Contact) {
        contacts.append(contact)
        persist()
    }

    public func delete(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        persist()
    }

    public func delete(atOffsets offsets: IndexSet, in visible: [Contact]) {
        let ids = Set(offsets.map { visible[$0].id })
        contacts.removeAll { ids.contains($0.id) }
        persist()
    }

    private func persist() {
        do {
            try storage.encode(contacts, for: Self.key)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }
}
