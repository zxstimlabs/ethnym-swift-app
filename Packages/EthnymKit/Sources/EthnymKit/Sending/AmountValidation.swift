import BigInt
import Foundation

/// Amount field rules shared by the send forms. Messages match the web wallet.
public enum AmountValidation {
    public static let emptyMessage = "Please enter an amount to send"

    /// The amount in base units, or the message to show.
    /// - Parameters:
    ///   - balance: When known, amounts above it are rejected.
    ///   - allowZero: Ether sends allow zero; token sends don't.
    public static func validate(_ text: String, decimals: Int, balance: BigUInt?, allowZero: Bool) -> Result<BigUInt, FieldError> {
        let trimmed = text.trimmed
        if trimmed.isEmpty { return .failure(FieldError(emptyMessage, isPrompt: true)) }
        guard let number = Double(trimmed) else { return .failure(FieldError("Please enter a valid number")) }
        if number < 0 {
            return .failure(FieldError(allowZero ? "Amount must be greater than or equal to 0" : "Amount must be greater than 0"))
        }
        let amount: BigUInt
        do {
            amount = try Units.parse(trimmed, decimals: decimals)
        } catch {
            return .failure(FieldError("Invalid amount format"))
        }
        if !allowZero && amount == 0 { return .failure(FieldError("Amount must be greater than 0")) }
        if let balance, amount > balance { return .failure(FieldError("Insufficient balance")) }
        return .success(amount)
    }

    /// `numerator / 4` of the balance, formatted for the amount field: 25%, 50%, 75% and Max.
    public static func fraction(_ quarters: Int, of balance: BigUInt, decimals: Int) -> String {
        Units.format(balance * BigUInt(quarters) / 4, decimals: decimals)
    }
}

/// A field's validation message. Prompts ("Please enter…") read as guidance, not as errors.
public struct FieldError: Error, Hashable, Sendable {
    public let message: String
    public let isPrompt: Bool

    public init(_ message: String, isPrompt: Bool = false) {
        self.message = message
        self.isPrompt = isPrompt
    }
}

/// Recipient field rules.
public enum RecipientValidation {
    public static let emptyMessage = "Please enter an address or ENS"

    public static func validate(_ text: String) -> FieldError? {
        let trimmed = text.trimmed
        if trimmed.isEmpty { return FieldError(emptyMessage, isPrompt: true) }
        if trimmed.isENSName || Address.isValid(trimmed) { return nil }
        if trimmed.hasPrefix("0x") { return FieldError("Invalid address") }
        return FieldError("Enter a 0x address or an ENS name ending in .eth")
    }
}
