import BigInt
import Foundation
import web3

/// Call data for the transfers the wallet sends, ABI-encoded by web3.swift.
public enum Contracts {
    public enum Failure: LocalizedError {
        case encoding

        public var errorDescription: String? { "The contract call couldn't be encoded." }
    }

    /// `transfer(address,uint256)`.
    public static func erc20Transfer(token: String, to recipient: String, amount: BigUInt) throws -> Data {
        try callData(ERC20Functions.transfer(contract: EthereumAddress(token), to: EthereumAddress(recipient), value: amount))
    }

    /// `safeTransferFrom(address,address,uint256)`.
    public static func erc721SafeTransfer(contract: String, from sender: String, to recipient: String, tokenId: BigUInt) throws -> Data {
        try callData(ERC721Functions.safeTransferFrom(
            contract: EthereumAddress(contract),
            sender: EthereumAddress(sender),
            to: EthereumAddress(recipient),
            tokenId: tokenId
        ))
    }

    private static func callData(_ function: some ABIFunction) throws -> Data {
        guard let data = try function.transaction().data else { throw Failure.encoding }
        return data
    }
}
