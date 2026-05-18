import Foundation
import Kit

/// A signed (or signature-padded) V0 transaction ready to be base64-encoded
/// and submitted via `sendTransaction` / `simulateTransaction`.
public struct CompiledTransaction: Sendable {
    /// Solana enforces a packet size limit of 1232 bytes for the entire
    /// signatures + message blob. The runtime drops anything larger.
    public static let maxPacketSize = Kit.legacyTransactionSizeLimit

    /// Signatures in the order returned by `CompiledMessage.signerAddresses`.
    public let signatures: [Signature]
    public let message: CompiledMessage

    public init(message: CompiledMessage, signatures: [Signature]) throws {
        guard signatures.count == message.signerAddresses.count else {
            throw MessageCompiler.CompileError.signatureCountMismatch(
                expected: message.signerAddresses.count,
                got: signatures.count)
        }
        self.message = message
        self.signatures = signatures
    }

    public var wireBytes: Data {
        do {
            return try Kit.getTransactionEncoder().encode(self.kitTransaction())
        } catch {
            preconditionFailure("Invalid compiled transaction")
        }
    }

    public var base64EncodedWireTransaction: String {
        do {
            return try Kit.getBase64EncodedWireTransaction(self.kitTransaction())
        } catch {
            preconditionFailure("Invalid compiled transaction")
        }
    }

    /// `true` if `wireBytes.count` would exceed the packet limit.
    public var exceedsPacketLimit: Bool {
        do {
            return try !Kit.isTransactionWithinSizeLimit(self.kitTransaction())
        } catch {
            return true
        }
    }

    public func kitTransaction() throws -> Kit.Transaction {
        let signatures = try zip(self.message.signerAddresses, self.signatures).map { address, signature in
            try Kit.TransactionSignature(
                address: address.address,
                signature: Kit.signatureBytes(signature.bytes))
        }
        return Kit.Transaction(
            messageBytes: self.message.messageBytes,
            signatures: Kit.SignaturesMap(entries: signatures),
            lifetimeConstraint: self.message.lifetimeConstraint)
    }
}
