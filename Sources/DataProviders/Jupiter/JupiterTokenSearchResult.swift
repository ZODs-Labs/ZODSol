import Foundation

/// One entry from Jupiter `tokens/v2/search`. Only the fields the ticker needs
/// for display are decoded; the search payload carries many more.
struct JupiterTokenSearchResult: Decodable {
    let id: String
    let symbol: String?
    let name: String?
    let icon: String?
    let decimals: Int?
}
