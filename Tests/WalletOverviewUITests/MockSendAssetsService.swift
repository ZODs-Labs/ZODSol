import Foundation
import SolanaKit
import WalletOverviewDomain

/// Test stub for the send service. Defaults to throwing `.canceled` on every
/// call - view-model tests that don't exercise the send flow want a service
/// that never produces side effects.
actor MockSendAssetsService: SendAssetsService {
    private(set) var lastQuoteTier: PriorityTier?
    private var resyncResults: [Signature: SendOutcome] = [:]

    func quote(_ request: SendRequest, tier: PriorityTier) async throws -> SendQuote {
        lastQuoteTier = tier
        throw SendError.canceled
    }

    func send(quote: SendQuote) async throws -> SendOutcome {
        throw SendError.canceled
    }

    func resync(walletId: UUID) async -> [Signature: SendOutcome] {
        resyncResults
    }

    func setResyncResults(_ results: [Signature: SendOutcome]) {
        self.resyncResults = results
    }
}
