public enum AssetKind: String, Hashable, Sendable, Codable {
    case nativeSol
    case fungible
    case nft
    case compressedNft
    case other
}
