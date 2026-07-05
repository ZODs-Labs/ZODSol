import Foundation
import SolanaKit

/// One candidate chain for an EVM address that resolved on several chains,
/// carrying the ready-to-add entry plus the metadata a picker shows.
public struct PasteChainCandidate: Sendable, Equatable, Identifiable {
    public let entry: TickerEntry
    public let chainName: String
    public let liquidityUSD: Decimal

    public init(entry: TickerEntry, chainName: String, liquidityUSD: Decimal) {
        self.entry = entry
        self.chainName = chainName
        self.liquidityUSD = liquidityUSD
    }

    public var id: String {
        self.entry.sourceIdentifier
    }
}

/// The result of resolving a pasted token address. The caller (the settings view
/// model) owns list concerns (dedupe, cap); this only resolves identity.
public enum PasteResolution: Sendable, Equatable {
    /// Ready to add.
    case resolved(TickerEntry)
    /// The EVM address is live on more than one supported chain; the user picks.
    case needsChainChoice([PasteChainCandidate])
    /// A user-facing message. Empty string means "nothing pasted", a no-op.
    case rejected(String)
}

/// The single entry point the paste UI calls. Classifies the input, routes a
/// Solana mint to the Jupiter resolver and an EVM address to the EVM resolver,
/// and turns every outcome into a `PasteResolution`. This is the Facade that
/// keeps the view model trivial and puts all input-handling in one testable place.
public struct TokenPasteResolver: Sendable {
    private let solana: (any TickerTokenResolving)?
    private let evm: (any EVMTokenResolving)?

    public init(solana: (any TickerTokenResolving)? = nil, evm: (any EVMTokenResolving)? = nil) {
        self.solana = solana
        self.evm = evm
    }

    public func resolve(_ raw: String) async -> PasteResolution {
        switch PasteClassifier.classify(raw) {
        case .empty:
            .rejected("")
        case let .evm(address):
            await self.resolveEVM(address)
        case let .solanaMint(mint):
            await self.resolveSolana(mint)
        case .ensName:
            .rejected("ENS names are not supported here. Paste the token's contract address (0x...).")
        case .unrecognized:
            .rejected("That does not look like a token address.")
        }
    }

    private func resolveEVM(_ address: String) async -> PasteResolution {
        guard let evm = self.evm else { return .rejected("EVM tokens are not available.") }
        switch await evm.resolve(address: address) {
        case let .resolved(token):
            return .resolved(TickerCatalog.evmEntry(token))
        case let .multipleChains(tokens):
            return .needsChainChoice(tokens.map {
                PasteChainCandidate(
                    entry: TickerCatalog.evmEntry($0),
                    chainName: $0.chain.displayName,
                    liquidityUSD: $0.liquidityUSD)
            })
        case .notFound:
            return .rejected(
                "No tradable token found at this address. Check you pasted a token contract, not a wallet.")
        case let .unsupportedChain(name):
            return .rejected("This token is on \(name), which is not supported yet.")
        case let .lowLiquidity(usd):
            return .rejected("Not enough liquidity to show a reliable price (\(Self.usd(usd)) in pools).")
        case .serviceUnavailable:
            return .rejected("Could not reach the price service. Check your connection and try again.")
        }
    }

    private func resolveSolana(_ mint: String) async -> PasteResolution {
        guard (try? Mint(base58: mint)) != nil else {
            return .rejected("That is not a valid token address.")
        }
        guard mint != TickerCatalog.wrappedSolMint else {
            return .rejected("SOL is already available in the Tokens list.")
        }
        guard let solana = self.solana else { return .rejected("Solana tokens are not available.") }
        guard let resolved = await solana.resolve(mint: mint) else {
            return .rejected("Could not find that token.")
        }
        return .resolved(TickerCatalog.jupiterEntry(
            mint: resolved.mint,
            symbol: resolved.symbol,
            displayName: resolved.name,
            displayDecimals: resolved.decimals,
            iconURL: resolved.iconURL))
    }

    private static func usd(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

/// How a pasted string is routed. Pure and synchronous so it is trivially tested.
enum ClassifiedPaste: Equatable {
    case empty
    case evm(address: String)
    case solanaMint(mint: String)
    case ensName
    case unrecognized
}

enum PasteClassifier {
    static func classify(_ raw: String) -> ClassifiedPaste {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if let address = EVMAddress.normalized(trimmed) { return .evm(address: address) }
        if let address = EVMAddress.firstAddress(in: trimmed) { return .evm(address: address) }
        if trimmed.lowercased().hasSuffix(".eth") { return .ensName }
        if self.looksLikeBase58Mint(trimmed) { return .solanaMint(mint: trimmed) }
        return .unrecognized
    }

    // A loose shape check; strict validation happens in the Solana resolver via
    // Mint(base58:). Base58 excludes 0, O, I and l to avoid visual ambiguity.
    private static func looksLikeBase58Mint(_ string: String) -> Bool {
        let alphabet = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return (32...44).contains(string.count) && string.allSatisfy { alphabet.contains($0) }
    }
}
