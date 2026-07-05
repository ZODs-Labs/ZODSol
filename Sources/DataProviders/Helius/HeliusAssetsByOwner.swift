import Foundation

struct HeliusAssetsByOwnerParams: Encodable {
    let ownerAddress: String
    let page: Int
    let limit: Int
    let displayOptions: DisplayOptions

    struct DisplayOptions: Encodable {
        let showFungible: Bool
        let showNativeBalance: Bool
        let showZeroBalance: Bool
    }
}

struct HeliusAssetsByOwnerResult: Decodable {
    let last_indexed_slot: UInt64?
    let total: Int?
    let limit: Int
    let page: Int
    let nativeBalance: HeliusNativeBalance?
    let items: [HeliusAsset]

    struct HeliusNativeBalance: Decodable {
        let lamports: UInt64
        let price_per_sol: Decimal?
        let total_price: Decimal?
    }

    struct HeliusAsset: Decodable {
        let id: String
        let interface: String
        let content: HeliusContent?
        let ownership: HeliusOwnership?
        let compression: HeliusCompression?
        let grouping: [HeliusGrouping]?
        let token_info: HeliusTokenInfo?
        let burnt: Bool?
    }

    struct HeliusContent: Decodable {
        let json_uri: String?
        let files: [HeliusFile]?
        let links: HeliusLinks?
        let metadata: HeliusMetadata?
    }

    struct HeliusFile: Decodable {
        let uri: String?
        let cdn_uri: String?
        let mime: String?
    }

    struct HeliusLinks: Decodable {
        let image: String?
        let external_url: String?
    }

    struct HeliusMetadata: Decodable {
        let name: String?
        let symbol: String?
        let description: String?
    }

    struct HeliusOwnership: Decodable {
        let owner: String
        let frozen: Bool?
    }

    struct HeliusCompression: Decodable {
        let compressed: Bool?
    }

    struct HeliusGrouping: Decodable {
        let group_key: String
        let group_value: String
    }

    struct HeliusTokenInfo: Decodable {
        let balance: UInt64?
        let decimals: UInt8?
        let symbol: String?
        let token_program: String?
        let price_info: HeliusPriceInfo?
    }

    struct HeliusPriceInfo: Decodable {
        let price_per_token: Decimal?
        let total_price: Decimal?
        let currency: String?
    }
}
