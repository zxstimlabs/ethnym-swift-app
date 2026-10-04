import Foundation
import Observation

/// Outgoing transaction history, kept on this device only.
@MainActor
@Observable
public final class ActivityStore {
    public private(set) var records: [ActivityRecord]
    public private(set) var storageError: String?

    @ObservationIgnored private let storage: any DataStorage
    @ObservationIgnored private let now: @Sendable () -> Date
    static let key = "activity"

    public init(storage: any DataStorage, now: @escaping @Sendable () -> Date = { .now }) {
        self.storage = storage
        self.now = now
        self.records = storage.decode([ActivityRecord].self, for: Self.key) ?? []
    }

    /// Stamps the record with the current time and an auto-incremented id.
    @discardableResult
    public func record(_ pending: PendingActivity, txHash: String) -> ActivityRecord {
        var record = pending.record(txHash: txHash, timestamp: Int64((now().timeIntervalSince1970 * 1000).rounded()))
        record.id = (records.compactMap(\.id).max() ?? 0) + 1
        records.append(record)
        persist()
        return record
    }

    /// Transactions sent from `address`, newest first.
    public func outgoing(from address: String) -> [ActivityRecord] {
        records
            .filter { Address.isSame($0.from, address) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func persist() {
        do {
            try storage.encode(records, for: Self.key)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }
}
