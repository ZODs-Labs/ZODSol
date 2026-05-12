import Foundation

public struct NFTSummary: Hashable, Sendable, Codable {
    public let count: Int
    public let collectionPreviews: [URL]
    public var isEmpty: Bool {
        self.count.signum() != 1
    }

    public init(count: Int, collectionPreviews: [URL]) {
        self.count = count
        self.collectionPreviews = collectionPreviews
    }
}
