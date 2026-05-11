import Foundation

public enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value, lastRefreshed: Date)
    case partial(Value, error: WalletOverviewError)
    case failed(WalletOverviewError)
}
