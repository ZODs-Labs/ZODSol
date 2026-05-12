import CryptoKit
import Foundation
import SolanaKit
@testable import WalletOverviewDomain

/// Deterministic test signer. Signs with a fixed Ed25519 seed so tests can
/// reconstruct the signature off-line if needed.
actor MockSendSigner: SendSignerAccess {
    let seed: Data
    private(set) var signCount = 0
    private(set) var signedMessages: [Data] = []
    var fail: Error?

    init(seed: Data = Data(repeating: 0x42, count: 32)) {
        precondition(seed.count == 32)
        self.seed = seed
    }

    func setFailure(_ error: Error?) {
        self.fail = error
    }

    nonisolated func publicKeyAddress() throws -> WalletAddress {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: self.seed)
        return try WalletAddress(base58: Base58.encode(key.publicKey.rawRepresentation))
    }

    func signMessage(walletId: UUID, message: Data, prompt: String) async throws -> Signature {
        self.signCount += 1
        self.signedMessages.append(message)
        if let fail { throw fail }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: self.seed)
        return try Signature(bytes: key.signature(for: message))
    }
}

/// In-memory address mapping for tests.
actor MockWalletLookup: SendWalletLookup {
    let mapping: [UUID: WalletAddress]

    init(_ mapping: [UUID: WalletAddress]) {
        self.mapping = mapping
    }

    func address(for walletId: UUID) async throws -> WalletAddress {
        guard let addr = mapping[walletId] else {
            throw WalletOverviewError.needsSetup
        }
        return addr
    }
}
