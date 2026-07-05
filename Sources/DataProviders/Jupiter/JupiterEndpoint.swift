import Foundation

public struct JupiterEndpoint: Sendable {
    public static let priceV3 = URL(string: "https://lite-api.jup.ag/price/v3")!
    public static let tokensSearch = URL(string: "https://lite-api.jup.ag/tokens/v2/search")!
}
