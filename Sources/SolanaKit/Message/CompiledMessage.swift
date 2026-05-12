import Foundation

/// Result of compiling a `TransactionMessage` to V0 wire bytes.
///
/// `messageBytes` is the canonical byte sequence the fee payer (and any
/// additional signers) sign over. `signerAddresses` lists those signers in
/// the order their signatures must appear in the final wire transaction.
public struct CompiledMessage: Sendable, Equatable {
    public let messageBytes: Data
    public let signerAddresses: [WalletAddress]
    public let accountKeys: [WalletAddress]

    public init(messageBytes: Data, signerAddresses: [WalletAddress], accountKeys: [WalletAddress]) {
        self.messageBytes = messageBytes
        self.signerAddresses = signerAddresses
        self.accountKeys = accountKeys
    }
}
