import Foundation
import SolanaKit
import SolanaRPC

extension HeliusSolanaProvider {

    static func mapRPCError(_ e: RPCError) -> SolanaProviderError {
        switch e {
        case .http(let status, _) where status == 401 || status == 403:
            return .unauthorized
        case .http(429, let retryAfter):
            return .rateLimited(retryAfter: retryAfter)
        case .http(let status, _) where (500 ..< 600).contains(status):
            return .providerUnavailable(message: "Helius \(status)")
        case .transport(let code) where code == .notConnectedToInternet:
            return .networkUnavailable
        case .transport(let code):
            return .providerUnavailable(message: code.rawValue.description)
        case .canceled:
            return .canceled
        case .decoding(let s):
            return .malformedResponse(s)
        case .rpc(let je):
            if je.code == -32005 {
                return .rateLimited(retryAfter: nil)
            } else if je.code == -32602 {
                return .invalidInput(je.message)
            } else {
                return .providerUnavailable(message: "JSON-RPC error \(je.code): \(je.message)")
            }
        case .http(let status, _):
            return .providerUnavailable(message: "HTTP \(status)")
        }
    }

    static func buildPage(
        _ result: HeliusAssetsByOwnerResult,
        options: AssetQueryOptions
    ) throws -> AssetPage {
        var items: [AssetSummary] = []
        for asset in result.items {
            guard asset.burnt != true else { continue }
            let summary = try mapAsset(asset)
            items.append(summary)
        }

        var nativeSol: NativeBalance? = nil
        if let nb = result.nativeBalance, options.showNativeBalance {
            nativeSol = NativeBalance(
                lamports: Lamports(rawValue: nb.lamports),
                pricePerSol: nb.price_per_sol,
                totalUSD: nb.total_price
            )
        }

        return AssetPage(
            items: items,
            nativeSol: nativeSol,
            page: result.page,
            limit: result.limit,
            totalEstimated: result.total,
            hasMore: result.items.count == options.limit
        )
    }

    private static func mapAsset(_ asset: HeliusAssetsByOwnerResult.HeliusAsset) throws -> AssetSummary {
        let kind = classifyAsset(asset)
        let mint = try Mint(base58: asset.id)
        let tokenInfo = asset.token_info
        let content = asset.content

        let amount: TokenAmount
        let symbol: String?
        let name: String?
        let pricePerToken: Decimal?
        let usdValue: Decimal?

        switch kind {
        case .fungible:
            amount = TokenAmount(
                amount: tokenInfo?.balance ?? 0,
                decimals: tokenInfo?.decimals ?? 0
            )
            symbol = tokenInfo?.symbol
            name = content?.metadata?.name
            pricePerToken = tokenInfo?.price_info?.price_per_token
            if let ppt = pricePerToken {
                usdValue = ppt * amount.uiAmount
            } else {
                usdValue = nil
            }
        case .nft, .compressedNft:
            amount = TokenAmount(amount: 1, decimals: 0)
            symbol = tokenInfo?.symbol ?? content?.metadata?.symbol
            name = content?.metadata?.name
            pricePerToken = nil
            usdValue = nil
        default:
            amount = TokenAmount(amount: 1, decimals: 0)
            symbol = content?.metadata?.symbol
            name = content?.metadata?.name
            pricePerToken = nil
            usdValue = nil
        }

        let imageURLString = content?.files?.first?.cdn_uri ?? content?.links?.image
        let imageURL: URL? = imageURLString.flatMap { URL(string: $0) }

        return AssetSummary(
            id: mint,
            kind: kind,
            symbol: symbol,
            name: name,
            imageURL: imageURL,
            amount: amount,
            usdValue: usdValue,
            pricePerToken: pricePerToken,
            priceChange24h: nil,
            tokenProgram: tokenInfo?.token_program
        )
    }

    private static func classifyAsset(_ asset: HeliusAssetsByOwnerResult.HeliusAsset) -> AssetKind {
        if asset.compression?.compressed == true {
            return .compressedNft
        }
        switch asset.interface {
        case "FungibleToken", "FungibleAsset":
            return .fungible
        case "V1_NFT", "ProgrammableNFT", "MplCoreAsset":
            return .nft
        default:
            return .other
        }
    }

    static func mapHolding(
        _ h: HeliusTokenAccountsResult.Holding,
        owner: WalletAddress
    ) throws -> ParsedTokenAccount {
        let info = h.account.data.parsed.info
        let mint = try Mint(base58: info.mint)
        guard let rawAmount = UInt64(info.tokenAmount.amount) else {
            throw SolanaProviderError.malformedResponse(
                "cannot parse token amount '\(info.tokenAmount.amount)' as UInt64"
            )
        }
        let tokenAccount = try WalletAddress(base58: h.pubkey)
        return ParsedTokenAccount(
            mint: mint,
            amount: TokenAmount(amount: rawAmount, decimals: info.tokenAmount.decimals),
            owner: owner,
            tokenAccount: tokenAccount
        )
    }
}
