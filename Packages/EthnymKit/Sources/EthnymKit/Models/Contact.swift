import Foundation

public struct Contact: Codable, Hashable, Sendable, Identifiable {
    public struct Metadata: Codable, Hashable, Sendable {
        public var tags: [String]
        public var version: String
        public var note: String

        public init(tags: [String] = [], version: String = "0.0.1", note: String = "") {
            self.tags = tags
            self.version = version
            self.note = note
        }
    }

    public var id: String
    public var address: String
    public var name: String
    /// EVM chain ID, or nil for a chain-agnostic contact.
    public var chain: Int?
    public var metadata: Metadata

    public init(id: String = UUID().uuidString.lowercased(), address: String, name: String, chain: Int?, metadata: Metadata) {
        self.id = id
        self.address = address
        self.name = name
        self.chain = chain
        self.metadata = metadata
    }

    // `chain` is written as `null` rather than omitted, matching the web wallet.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(address, forKey: .address)
        try container.encode(name, forKey: .name)
        try container.encode(chain, forKey: .chain)
        try container.encode(metadata, forKey: .metadata)
    }
}

// MARK: - Validation and search

public enum ContactValidation {
    public static func validateName(_ value: String) -> String? {
        value.trimmed.isEmpty ? "Please enter a name" : nil
    }

    public static func validateAddress(_ value: String, existingAddresses: [String]) -> String? {
        let trimmed = value.trimmed
        if trimmed.isEmpty { return "Please enter an address" }
        if existingAddresses.contains(trimmed.lowercased()) { return "Address already in address book" }
        if !trimmed.isENSName && !Address.isValid(trimmed) { return "Enter a 0x address or an ENS name" }
        return nil
    }

    public static func validateChain(_ value: String) -> String? {
        let trimmed = value.trimmed
        if !trimmed.isEmpty && Int(trimmed) == nil { return "Chain must be a numeric chain ID" }
        return nil
    }

    public static func parseTags(_ raw: String) -> [String] {
        raw.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    public static func filter(_ contacts: [Contact], query: String) -> [Contact] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return contacts }
        return contacts.filter { contact in
            contact.name.lowercased().contains(q)
                || contact.address.lowercased().contains(q)
                || contact.metadata.tags.contains { $0.lowercased().contains(q) }
                || contact.metadata.note.lowercased().contains(q)
        }
    }
}
