import XCTest
@testable import SolanaKit

final class AggregateValuesTests: XCTestCase {
    private let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    private let wrappedSol = "So11111111111111111111111111111111111111112"
    private let ownerAddr = "11111111111111111111111111111111"
    private let tokenAcct = "So11111111111111111111111111111111111111112"

    // MARK: - AssetSummary

    func testAssetSummaryCodableRoundTrip() throws {
        let summary = try makeSummary(mintBase58: usdcMint, kind: .fungible)
        let data = try jsonEncoder().encode(summary)
        let decoded = try jsonDecoder().decode(AssetSummary.self, from: data)
        XCTAssertEqual(summary, decoded)
        XCTAssertEqual(summary.id, decoded.id)
    }

    func testAssetSummaryIdentifiableUsesMint() throws {
        let mint = try Mint(base58: usdcMint)
        let summary = AssetSummary(
            id: mint,
            kind: .fungible,
            symbol: "USDC",
            name: "USD Coin",
            imageURL: URL(string: "https://example.com/usdc.png"),
            amount: TokenAmount(amount: 1_000_000, decimals: 6),
            usdValue: Decimal(string: "1.00"),
            pricePerToken: Decimal(string: "1.00"),
            priceChange24h: 0.0,
            tokenProgram: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        XCTAssertEqual(summary.id, mint)
    }

    // MARK: - WalletOverview

    func testWalletOverviewCodableRoundTrip() throws {
        let overview = try makeOverview()
        let data = try jsonEncoder().encode(overview)
        let decoded = try jsonDecoder().decode(WalletOverview.self, from: data)
        XCTAssertEqual(overview, decoded)
    }

    func testWalletOverviewPreservesIsPartialFlag() throws {
        let overview = try makeOverview(isPartial: true)
        let data = try jsonEncoder().encode(overview)
        let decoded = try jsonDecoder().decode(WalletOverview.self, from: data)
        XCTAssertTrue(decoded.isPartial)
    }

    // MARK: - NFTSummary

    func testNFTSummaryCodableRoundTrip() throws {
        let summary = try NFTSummary(
            count: 7,
            collectionPreviews: [
                XCTUnwrap(URL(string: "https://example.com/a.png")),
                XCTUnwrap(URL(string: "https://example.com/b.png")),
            ])
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(NFTSummary.self, from: data)
        XCTAssertEqual(summary, decoded)
    }

    func testNFTSummaryEmpty() throws {
        let summary = NFTSummary(count: 0, collectionPreviews: [])
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(NFTSummary.self, from: data)
        XCTAssertEqual(summary, decoded)
        XCTAssertEqual(decoded.count, 0)
        XCTAssertTrue(decoded.collectionPreviews.isEmpty)
    }

    // MARK: - ParsedTokenAccount

    func testParsedTokenAccountCodableRoundTrip() throws {
        let account = try ParsedTokenAccount(
            mint: Mint(base58: usdcMint),
            amount: TokenAmount(amount: 5_000_000, decimals: 6),
            owner: WalletAddress(base58: ownerAddr),
            tokenAccount: WalletAddress(base58: tokenAcct))
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(ParsedTokenAccount.self, from: data)
        XCTAssertEqual(account, decoded)
    }

    // MARK: - NativeBalance

    func testNativeBalanceCodableRoundTrip() throws {
        let balance = NativeBalance(
            lamports: 12_345_000_000,
            pricePerSol: Decimal(string: "180.25"),
            totalUSD: Decimal(string: "2224.18"))
        let data = try jsonEncoder().encode(balance)
        let decoded = try jsonDecoder().decode(NativeBalance.self, from: data)
        XCTAssertEqual(balance, decoded)
    }

    func testNativeBalanceWithNilPrices() throws {
        let balance = NativeBalance(lamports: 0, pricePerSol: nil, totalUSD: nil)
        let data = try jsonEncoder().encode(balance)
        let decoded = try jsonDecoder().decode(NativeBalance.self, from: data)
        XCTAssertEqual(balance, decoded)
        XCTAssertNil(decoded.pricePerSol)
        XCTAssertNil(decoded.totalUSD)
    }

    // MARK: - AssetPage

    func testAssetPageCodableRoundTrip() throws {
        let summary = try makeSummary(mintBase58: usdcMint, kind: .fungible)
        let page = AssetPage(
            items: [summary],
            nativeSol: NativeBalance(
                lamports: 2_000_000_000,
                pricePerSol: Decimal(string: "180"),
                totalUSD: Decimal(string: "360")),
            page: 1,
            limit: 1000,
            totalEstimated: 1,
            hasMore: false)
        let data = try jsonEncoder().encode(page)
        let decoded = try jsonDecoder().decode(AssetPage.self, from: data)
        XCTAssertEqual(page, decoded)
    }

    func testAssetPageWithoutNativeBalance() throws {
        let page = AssetPage(
            items: [],
            nativeSol: nil,
            page: 2,
            limit: 500,
            totalEstimated: nil,
            hasMore: true)
        let data = try jsonEncoder().encode(page)
        let decoded = try jsonDecoder().decode(AssetPage.self, from: data)
        XCTAssertEqual(page, decoded)
        XCTAssertNil(decoded.nativeSol)
        XCTAssertNil(decoded.totalEstimated)
        XCTAssertTrue(decoded.hasMore)
    }

    // MARK: - AssetQueryOptions

    func testAssetQueryOptionsDefaults() {
        let options = AssetQueryOptions.default
        XCTAssertEqual(options.page, 1)
        XCTAssertEqual(options.limit, 1000)
        XCTAssertTrue(options.showFungible)
        XCTAssertTrue(options.showNativeBalance)
        XCTAssertFalse(options.showZeroBalance)
    }

    func testAssetQueryOptionsCustomInit() {
        let options = AssetQueryOptions(
            page: 3,
            limit: 250,
            showFungible: false,
            showNativeBalance: false,
            showZeroBalance: true)
        XCTAssertEqual(options.page, 3)
        XCTAssertEqual(options.limit, 250)
        XCTAssertFalse(options.showFungible)
        XCTAssertFalse(options.showNativeBalance)
        XCTAssertTrue(options.showZeroBalance)
    }

    // MARK: - Sendable conformance compilation check

    func testEveryPublicTypeIsUsableInSendableContext() async throws {
        // If any of these types loses Sendable conformance the test target
        // simply will not compile.
        let summary = try makeSummary(mintBase58: usdcMint, kind: .fungible)
        let overview = try makeOverview()
        let nft = NFTSummary(count: 1, collectionPreviews: [])
        let tokenAccount = try ParsedTokenAccount(
            mint: Mint(base58: usdcMint),
            amount: TokenAmount(amount: 1, decimals: 6),
            owner: WalletAddress(base58: ownerAddr),
            tokenAccount: WalletAddress(base58: tokenAcct))
        let native = NativeBalance(lamports: 1, pricePerSol: nil, totalUSD: nil)
        let page = AssetPage(
            items: [summary],
            nativeSol: native,
            page: 1,
            limit: 10,
            totalEstimated: 1,
            hasMore: false)
        let options = AssetQueryOptions.default
        let network = SolanaNetwork.mainnet
        let kind = AssetKind.fungible
        let address = try WalletAddress(base58: usdcMint)
        let mint = try Mint(base58: usdcMint)
        let lamports: Lamports = 1_000_000_000
        let amount = TokenAmount(amount: 1, decimals: 6)
        let error: SolanaProviderError = .canceled

        try await Self.consume(
            SendableBundle(
                summary: summary,
                overview: overview,
                nft: nft,
                tokenAccount: tokenAccount,
                native: native,
                page: page,
                options: options,
                network: network,
                kind: kind,
                address: address,
                mint: mint,
                lamports: lamports,
                amount: amount,
                error: error))
    }

    /// A @Sendable function whose signature forces every parameter to be
    /// Sendable at compile time.
    @Sendable
    private static func consume(_ bundle: SendableBundle) async throws {
        XCTAssertEqual(bundle.summary.kind, .fungible)
        XCTAssertEqual(bundle.overview.address, bundle.address)
        XCTAssertEqual(bundle.nft.count, 1)
        XCTAssertEqual(bundle.tokenAccount.mint, bundle.mint)
        XCTAssertNil(bundle.native.pricePerSol)
        XCTAssertFalse(bundle.page.hasMore)
        XCTAssertEqual(bundle.options.page, 1)
        XCTAssertEqual(bundle.network, .mainnet)
        XCTAssertEqual(bundle.kind, .fungible)
        XCTAssertEqual(bundle.lamports.rawValue, 1_000_000_000)
        XCTAssertEqual(bundle.amount.amount, 1)
        XCTAssertEqual(bundle.error, .canceled)
    }

    private struct SendableBundle {
        let summary: AssetSummary
        let overview: WalletOverview
        let nft: NFTSummary
        let tokenAccount: ParsedTokenAccount
        let native: NativeBalance
        let page: AssetPage
        let options: AssetQueryOptions
        let network: SolanaNetwork
        let kind: AssetKind
        let address: WalletAddress
        let mint: Mint
        let lamports: Lamports
        let amount: TokenAmount
        let error: SolanaProviderError
    }

    // MARK: - Builders

    private func makeSummary(mintBase58: String, kind: AssetKind) throws -> AssetSummary {
        try AssetSummary(
            id: Mint(base58: mintBase58),
            kind: kind,
            symbol: "USDC",
            name: "USD Coin",
            imageURL: URL(string: "https://example.com/usdc.png"),
            amount: TokenAmount(amount: 1_500_000, decimals: 6),
            usdValue: Decimal(string: "1.50"),
            pricePerToken: Decimal(string: "1.00"),
            priceChange24h: 0.12,
            tokenProgram: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
    }

    private func makeOverview(isPartial: Bool = false) throws -> WalletOverview {
        try WalletOverview(
            walletId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            address: WalletAddress(base58: self.usdcMint),
            solBalance: 12_345_000_000,
            solPriceUSD: Decimal(string: "180.25"),
            solChange24h: -0.0345,
            tokens: [self.makeSummary(mintBase58: self.usdcMint, kind: .fungible)],
            nfts: NFTSummary(count: 0, collectionPreviews: []),
            totalUSD: Decimal(string: "2224.18"),
            totalChange24h: 0.012,
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            isPartial: isPartial)
    }

    private func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
