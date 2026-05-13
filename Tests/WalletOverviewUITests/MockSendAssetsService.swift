import Foundation
import SolanaKit
import WalletOverviewDomain

/// Test stub for the send service. Defaults to throwing `.canceled` on every
/// call - view-model tests that don't exercise the send flow want a service
/// that never produces side effects.
actor MockSendAssetsService: SendAssetsService {
    private(set) var lastQuoteTier: PriorityTier?
    private var resyncResults: [PendingSendResolution] = []

    func quote(_ request: SendRequest, tier: PriorityTier) async throws -> SendQuote {
        self.lastQuoteTier = tier
        throw SendError.canceled
    }

    func send(quote: SendQuote) async throws -> SendOutcome {
        throw SendError.canceled
    }

    func resync(walletId: UUID) async -> [PendingSendResolution] {
        self.resyncResults
    }

    func setResyncResults(_ results: [PendingSendResolution]) {
        self.resyncResults = results
    }
}
