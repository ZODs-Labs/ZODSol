import Foundation
import SolanaKit

/// Detects the chain for a pasted EVM address and resolves its token metadata,
/// keyless, via DexScreener cross-chain search. Chain is discovered, never parsed
/// from the address: we ask which chains host a liquid market and resolve
/// ambiguity by summed USD liquidity, failing closed to a choice or a message.
public struct EVMDexResolverClient: EVMTokenResolving {
    private let client: DexScreenerClient
    private let liquidityFloor: Decimal

    public init(session: URLSession, liquidityFloor: Decimal = 1000) {
        self.client = DexScreenerClient(session: session)
        self.liquidityFloor = liquidityFloor
    }

    public func resolve(address: String) async -> EVMResolution {
        guard let normalized = EVMAddress.normalized(address) else { return .notFound }
        switch await self.client.search(address: normalized) {
        case .failed:
            return .serviceUnavailable
        case let .pairs(allPairs):
            return self.classify(DexScreenerPairMath.matching(allPairs, address: normalized), address: normalized)
        }
    }

    private func classify(_ matching: [DexScreenerPair], address: String) -> EVMResolution {
        guard !matching.isEmpty else { return .notFound }

        var supported: [EVMChain: [DexScreenerPair]] = [:]
        var unsupportedChainId: String?
        for pair in matching {
            if let chain = EVMChain.supported(dexScreenerId: pair.chainId) {
                supported[chain, default: []].append(pair)
            } else {
                unsupportedChainId = unsupportedChainId ?? pair.chainId
            }
        }
        guard !supported.isEmpty else {
            return .unsupportedChain(Self.prettify(unsupportedChainId ?? "another chain"))
        }

        var candidates: [EVMResolvedToken] = []
        var deepestBelowFloor: Decimal = 0
        for (chain, pairs) in supported {
            let liquidity = DexScreenerPairMath.totalLiquidity(pairs)
            if liquidity >= self.liquidityFloor {
                candidates.append(Self.makeToken(chain: chain, address: address, pairs: pairs, liquidity: liquidity))
            } else {
                deepestBelowFloor = Swift.max(deepestBelowFloor, liquidity)
            }
        }

        switch candidates.count {
        case 0:
            return .lowLiquidity(deepestBelowFloor)
        case 1:
            return .resolved(candidates[0])
        default:
            return .multipleChains(candidates.sorted { $0.liquidityUSD > $1.liquidityUSD })
        }
    }

    private static func makeToken(
        chain: EVMChain,
        address: String,
        pairs: [DexScreenerPair],
        liquidity: Decimal) -> EVMResolvedToken
    {
        let deepest = DexScreenerPairMath.deepestPool(pairs)
        let fallback = TokenDisplayText.shortAddress(address)
        let symbol = TokenDisplayText.symbol(deepest?.baseToken.symbol ?? "", fallback: fallback)
        let name = TokenDisplayText.name(deepest?.baseToken.name ?? "", fallback: symbol)
        let icon = deepest?.info?.imageUrl
            .flatMap(URL.init(string:))
            .flatMap { ImageURLPolicy.isPermitted($0) ? $0 : nil }
        return EVMResolvedToken(
            chain: chain,
            address: address,
            symbol: symbol,
            name: name,
            iconURL: icon,
            liquidityUSD: liquidity)
    }

    private static func prettify(_ chainId: String) -> String {
        chainId.isEmpty ? "another chain" : chainId.prefix(1).uppercased() + chainId.dropFirst()
    }
}
