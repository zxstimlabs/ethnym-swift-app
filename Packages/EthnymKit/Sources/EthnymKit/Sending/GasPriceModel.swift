import BigInt
import Foundation
import Observation

/// The network gas price and the Slow / Normal / Fast preset the user picked.
@MainActor
@Observable
public final class GasPriceModel {
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case slow
        case normal
        case fast

        public var id: Self { self }

        public var title: String {
            switch self {
            case .slow: "Slow"
            case .normal: "Normal"
            case .fast: "Fast"
            }
        }

        /// Per mille of the network price: 90%, 100%, 110%, as the web wallet does.
        var perMille: BigUInt {
            switch self {
            case .slow: 900
            case .normal: 1000
            case .fast: 1100
            }
        }
    }

    public private(set) var networkPrice: BigUInt?
    public var preset: Preset = .normal
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    public init() {}

    /// The price to cap fees at, in wei per gas.
    public var selectedPrice: BigUInt? {
        networkPrice.map { $0 * preset.perMille / 1000 }
    }

    /// The selected price in gwei, for display.
    public var selectedGwei: String? {
        selectedPrice.map(Units.formatGwei)
    }

    public func refresh(service: EthereumService?) async {
        guard let service else {
            errorMessage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            networkPrice = try await service.gasPrice()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
