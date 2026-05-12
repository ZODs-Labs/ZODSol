import Foundation

public struct ParsedTokenAccount: Hashable, Sendable, Codable {
    public let mint: Mint
    public let amount: TokenAmount
    public let owner: WalletAddress
    public let tokenAccount: WalletAddress

    public init(
        mint: Mint,
        amount: TokenAmount,
        owner: WalletAddress,
        tokenAccount: WalletAddress)
    {
        self.mint = mint
        self.amount = amount
        self.owner = owner
        self.tokenAccount = tokenAccount
    }
}
