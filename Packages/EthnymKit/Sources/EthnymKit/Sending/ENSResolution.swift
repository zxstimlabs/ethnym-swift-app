import Foundation
import Observation

/// Resolves what a user typed into an address field: a 0x address passes through, an ENS name is
/// looked up. Each new input cancels the previous lookup.
@MainActor
@Observable
public final class ENSResolution {
    public enum State: Hashable, Sendable {
        case idle
        case resolving(name: String)
        case resolved(name: String, address: String)
        case notFound(name: String)
        case failed(name: String, message: String)
        /// The network is off, so names can't be looked up.
        case offline(name: String)
    }

    public private(set) var state: State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    /// Looks up `input` if it's an ENS name. `delay` debounces typing.
    public func resolve(_ input: String, service: EthereumService?, delay: Duration = .zero) {
        task?.cancel()
        let name = input.trimmed.lowercased()
        guard input.isENSName else {
            state = .idle
            return
        }
        if case let .resolved(resolvedName, _) = state, resolvedName == name { return }
        guard let service else {
            state = .offline(name: name)
            return
        }
        state = .resolving(name: name)
        task = Task {
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
                let address = try await service.resolveENS(name)
                guard !Task.isCancelled else { return }
                state = address.map { .resolved(name: name, address: $0) } ?? .notFound(name: name)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(name: name, message: "Failed to resolve ENS")
            }
        }
    }

    public func reset() {
        task?.cancel()
        state = .idle
    }

    /// The address to send to for `input`: itself if it's a valid address, or its resolved ENS address.
    public func address(for input: String) -> String? {
        let trimmed = input.trimmed
        if Address.isValid(trimmed) { return trimmed }
        if case let .resolved(name, address) = state, name == trimmed.lowercased() { return address }
        return nil
    }

    public var isResolving: Bool {
        if case .resolving = state { true } else { false }
    }
}
