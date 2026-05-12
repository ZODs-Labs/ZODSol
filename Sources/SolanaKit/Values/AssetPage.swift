import Foundation

public struct AssetPage: Hashable, Sendable, Codable {
    public let items: [AssetSummary]
    public let nativeSol: NativeBalance?
    public let page: Int
    public let limit: Int
    public let totalEstimated: Int?
    public let hasMore: Bool

    public init(
        items: [AssetSummary],
        nativeSol: NativeBalance?,
        page: Int,
        limit: Int,
        totalEstimated: Int?,
        hasMore: Bool)
    {
        self.items = items
        self.nativeSol = nativeSol
        self.page = page
        self.limit = limit
        self.totalEstimated = totalEstimated
        self.hasMore = hasMore
    }
}
