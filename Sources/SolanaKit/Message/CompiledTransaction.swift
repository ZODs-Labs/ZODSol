import Foundation

/// A signed (or signature-padded) V0 transaction ready to be base64-encoded
/// and submitted via `sendTransaction` / `simulateTransaction`.
public struct CompiledTransaction: Sendable {
    /// Solana enforces a packet size limit of 1232 bytes for the entire
    /// signatures + message blob. The runtime drops anything larger.
    public static let maxPacketSize = 1232

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

    /// The bytes submitted to the RPC: short_u16(sigCount) || sigs || message.
    public var wireBytes: Data {
        var data = Data()
        data.reserveCapacity(3 + 64 * self.signatures.count + self.message.messageBytes.count)
        data.append(WireFormat.encodeShortU16(UInt16(self.signatures.count)))
        for signature in self.signatures {
            data.append(signature.bytes)
        }
        data.append(self.message.messageBytes)
        return data
    }

    /// `true` if `wireBytes.count` would exceed the packet limit.
    public var exceedsPacketLimit: Bool {
        self.wireBytes.count > Self.maxPacketSize
    }
}
