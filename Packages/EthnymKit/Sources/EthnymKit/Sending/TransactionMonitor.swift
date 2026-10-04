import Foundation
import Observation

/// Watches broadcast transactions until they're mined and records successful ones in activity.
/// Lives with the app, not a screen, so closing the send sheet doesn't lose the receipt.
@MainActor
@Observable
public final class TransactionMonitor {
    public enum Status: Hashable, Sendable {
        case confirming
        case confirmed
        case reverted
        case failed(String)
    }

    public private(set) var statuses: [String: Status] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let activity: ActivityStore

    public init(activity: ActivityStore) {
        self.activity = activity
    }

    public func status(of hash: String) -> Status? {
        statuses[hash.lowercased()]
    }

    /// Starts polling for the receipt. `pending` becomes an activity record once confirmed.
    public func track(_ hash: String, pending: PendingActivity?, service: EthereumService) {
        let key = hash.lowercased()
        guard tasks[key] == nil else { return }
        statuses[key] = .confirming
        tasks[key] = Task { [activity] in
            defer { tasks[key] = nil }
            do {
                switch try await service.waitForReceipt(hash) {
                case .success:
                    statuses[key] = .confirmed
                    if let pending { activity.record(pending, txHash: hash) }
                case .reverted:
                    statuses[key] = .reverted
                }
            } catch is CancellationError {
                return
            } catch {
                statuses[key] = .failed(error.localizedDescription)
            }
        }
    }
}
