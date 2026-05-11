import Foundation

struct HeliusBalanceResult: Decodable, Sendable {
    struct Context: Decodable, Sendable {
        let slot: UInt64
    }
    let context: Context
    let value: UInt64
}

struct HeliusTokenAccountsResult: Decodable, Sendable {
    struct Context: Decodable, Sendable {
        let slot: UInt64
        let apiVersion: String?
    }
    let context: Context
    let value: [Holding]

    struct Holding: Decodable, Sendable {
        let pubkey: String
        let account: Account

        struct Account: Decodable, Sendable {
            let data: ParsedData
        }

        struct ParsedData: Decodable, Sendable {
            let parsed: Parsed
        }

        struct Parsed: Decodable, Sendable {
            let info: Info
        }

        struct Info: Decodable, Sendable {
            let mint: String
            let owner: String
            let tokenAmount: TokenAmountField

            struct TokenAmountField: Decodable, Sendable {
                let amount: String
                let decimals: UInt8
                let uiAmount: Double?
                let uiAmountString: String?
            }
        }
    }
}
