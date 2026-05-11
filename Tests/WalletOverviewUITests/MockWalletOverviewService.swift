import Foundation
import SolanaKit
import WalletOverviewDomain

actor MockWalletOverviewService: WalletOverviewService {
    var loadResult: LoadState<WalletOverview> = .idle
    var streamStates: [LoadState<WalletOverview>] = []

    private(set) var loadCallCount: Int = 0
    private(set) var lastForceRevalidate: Bool?
    private(set) var lastLoadWalletId: UUID?
    private(set) var invalidateCallCount: Int = 0
    private(set) var invalidateAllCallCount: Int = 0
    private(set) var lastInvalidatedWalletId: UUID?

    init(
        loadResult: LoadState<WalletOverview> = .idle,
        streamStates: [LoadState<WalletOverview>] = []
    ) {
        self.loadResult = loadResult
        self.streamStates = streamStates
    }

    func setLoadResult(_ result: LoadState<WalletOverview>) {
        self.loadResult = result
    }

    func setStreamStates(_ states: [LoadState<WalletOverview>]) {
        self.streamStates = states
    }

    func load(for walletId: UUID, forceRevalidate: Bool) async -> LoadState<WalletOverview> {
        loadCallCount += 1
        lastForceRevalidate = forceRevalidate
        lastLoadWalletId = walletId
        return loadResult
    }

    nonisolated func stream(for walletId: UUID, tick: Duration) -> AsyncStream<LoadState<WalletOverview>> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                let snapshot = await self.streamStates
                for state in snapshot {
                    if Task.isCancelled { break }
                    continuation.yield(state)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func invalidate(walletId: UUID) async {
        invalidateCallCount += 1
        lastInvalidatedWalletId = walletId
    }

    func invalidateAll() async {
        invalidateAllCallCount += 1
    }
}
