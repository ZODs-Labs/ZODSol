import Foundation

public struct AssetQueryOptions: Hashable, Sendable {
    public var page: Int
    public var limit: Int
    public var showFungible: Bool
    public var showNativeBalance: Bool
    public var showZeroBalance: Bool

    public init(
        page: Int = 1,
        limit: Int = 1000,
        showFungible: Bool = true,
        showNativeBalance: Bool = true,
        showZeroBalance: Bool = false
    ) {
        self.page = page
        self.limit = limit
        self.showFungible = showFungible
        self.showNativeBalance = showNativeBalance
        self.showZeroBalance = showZeroBalance
    }

    public static let `default` = AssetQueryOptions()
}
