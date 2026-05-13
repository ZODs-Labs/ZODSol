import Foundation

public struct NFTSummary: Hashable, Sendable, Codable {
    public let count: Int
    public let collectionPreviews: [Preview]
    public var isEmpty: Bool {
        self.count.signum() != 1
    }

    public init(count: Int, collectionPreviews: [Preview]) {
        self.count = count
        self.collectionPreviews = collectionPreviews
    }

    /// Thumbnail entry for the wallet's NFT row. Mirrors the fallback chain
    /// `AssetSummary` carries for fungible tokens so the loader can swap
    /// origin gateways when the primary URL fails.
    public struct Preview: Hashable, Sendable, Codable {
        public let imageURL: URL
        public let alternates: [URL]

        public init(imageURL: URL, alternates: [URL] = []) {
            self.imageURL = imageURL
            self.alternates = alternates
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.imageURL = try c.decode(URL.self, forKey: .imageURL)
            self.alternates = try c.decodeIfPresent([URL].self, forKey: .alternates) ?? []
        }
    }
}
