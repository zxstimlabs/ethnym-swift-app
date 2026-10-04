import Foundation
import Observation

/// One send form's progress: unlock, prepare, sign, broadcast. Confirmation is the monitor's job.
@MainActor
@Observable
public final class SendFlow {
    public enum Phase: Hashable, Sendable {
        case idle
        /// Unlocking the keystore, filling in gas and fees, signing and broadcasting.
        case signing
        case submitted(hash: String)
        /// Signed without the network; the raw transaction is for broadcasting elsewhere.
        case signedOffline(raw: String, hash: String)
    }

    public private(set) var phase: Phase = .idle
    public var errorMessage: String?

    public init() {}

    public var isBusy: Bool { phase == .signing }

    public var hash: String? {
        switch phase {
        case let .submitted(hash), let .signedOffline(_, hash): hash
        case .idle, .signing: nil
        }
    }

    /// Unlocks `wallet` with `password`, signs `request` and broadcasts it.
    public func send(_ request: TransactionRequest, pending: PendingActivity?, wallet: WalletKeystore, password: String, app: AppModel) async {
        guard !isBusy else { return }
        phase = .signing
        errorMessage = nil
        do {
            guard let service = app.service else { throw TransactionSender.Failure.offline }
            let account = try await WalletCrypto.unlock(wallet, password: password)
            let transaction = try await TransactionSender.prepare(request, from: account.address, service: service)
            let signed = try transaction.signed(with: account.privateKey)
            let hash = try await service.sendRawTransaction(signed.raw)
            phase = .submitted(hash: hash)
            app.transactions.track(hash, pending: pending, service: service)
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
        }
    }

    /// Signs `request` without touching the network. Every field must be filled in.
    public func signOffline(_ request: TransactionRequest, wallet: WalletKeystore, password: String) async {
        guard !isBusy else { return }
        phase = .signing
        errorMessage = nil
        do {
            let transaction = try TransactionSender.prepareOffline(request)
            let account = try await WalletCrypto.unlock(wallet, password: password)
            let signed = try transaction.signed(with: account.privateKey)
            phase = .signedOffline(raw: signed.rawHex, hash: signed.hash)
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
        }
    }

    public func reset() {
        phase = .idle
        errorMessage = nil
    }
}
