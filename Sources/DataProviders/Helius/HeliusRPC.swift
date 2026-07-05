import Foundation

struct HeliusBalanceResult: Decodable {
    struct Context: Decodable {
        let slot: UInt64
    }

    let context: Context
    let value: UInt64
}

struct HeliusTokenAccountsResult: Decodable {
    struct Context: Decodable {
        let slot: UInt64
        let apiVersion: String?
    }

    let context: Context
    let value: [Holding]

    struct Holding: Decodable {
        let pubkey: String
        let account: Account

        struct Account: Decodable {
            let data: ParsedData
        }

        struct ParsedData: Decodable {
            let parsed: Parsed
        }

        struct Parsed: Decodable {
            let info: Info
        }

        struct Info: Decodable {
            let mint: String
            let owner: String
            let tokenAmount: TokenAmountField

            struct TokenAmountField: Decodable {
                let amount: String
                let decimals: UInt8
                let uiAmount: Double?
                let uiAmountString: String?
            }
        }
    }
}
