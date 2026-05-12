import Foundation
import SolanaKit
import XCTest
@testable import WalletOverviewUI

@MainActor
final class ReceiveViewModelTests: XCTestCase {
    private let recipientBase58 = "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq"
    private let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

    private func makeIntent() throws -> ReceiveIntent {
        let address = try WalletAddress(base58: self.recipientBase58)
        return ReceiveIntent(walletId: UUID(), address: address, network: .mainnet)
    }

    private func makeViewModel(toastDuration: TimeInterval = 0.1) throws -> ReceiveViewModel {
        try ReceiveViewModel(
            intent: self.makeIntent(),
            cluster: .mainnet,
            toastDuration: toastDuration)
    }

    private func makeSolRow() -> PortfolioRow {
        PortfolioRow.sol(balance: Lamports(rawValue: 1_000_000_000), price: nil, change: nil)
    }

    private func makeUsdcRow() -> PortfolioRow {
        PortfolioRow(
            id: self.usdcMint,
            symbol: "USDC",
            name: "USD Coin",
            imageURL: nil,
            amount: TokenAmount(amount: 100, decimals: 6),
            pricePerToken: nil,
            usdValue: nil,
            priceChange24h: nil,
            isNative: false,
            tokenProgram: nil)
    }

    func test_onAppear_setsQrPayloadToBareAddress() throws {
        let viewModel = try self.makeViewModel()
        viewModel.onAppear()
        XCTAssertEqual(viewModel.qrPayload, self.recipientBase58)
    }

    func test_setAmountRequest_switchesPayloadToSolanaPayURI() throws {
        let viewModel = try self.makeViewModel()
        viewModel.onAppear()
        viewModel.setAmountRequest(asset: self.makeUsdcRow())

        XCTAssertTrue(viewModel.qrPayload.hasPrefix("solana:"), "got: \(viewModel.qrPayload)")
        XCTAssertTrue(viewModel.qrPayload.contains("spl-token="), "got: \(viewModel.qrPayload)")
        XCTAssertTrue(viewModel.qrPayload.contains(self.usdcMint))
    }

    func test_updateAmountText_debouncesAndProducesURIWithAmount() async throws {
        let viewModel = try self.makeViewModel()
        viewModel.onAppear()
        viewModel.setAmountRequest(asset: self.makeSolRow())
        viewModel.updateAmountText("25")

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(viewModel.qrPayload.hasPrefix("solana:"), "got: \(viewModel.qrPayload)")
        XCTAssertTrue(viewModel.qrPayload.contains("amount=25"), "got: \(viewModel.qrPayload)")
    }

    func test_clearAmountRequest_returnsPayloadToBareBase58() async throws {
        let viewModel = try self.makeViewModel()
        viewModel.onAppear()
        viewModel.setAmountRequest(asset: self.makeUsdcRow())
        XCTAssertTrue(viewModel.qrPayload.hasPrefix("solana:"))

        viewModel.clearAmountRequest()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.qrPayload, self.recipientBase58)
        XCTAssertEqual(viewModel.amountRequest, .none)
    }

    func test_copyAddress_setsToastVisibleAndResets() async throws {
        let viewModel = try self.makeViewModel(toastDuration: 0.1)
        viewModel.onAppear()
        viewModel.copyAddress()
        XCTAssertTrue(viewModel.copyToastVisible)

        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(viewModel.copyToastVisible)
    }

    func test_unparseableAmountText_keepsURIWithoutAmount() async throws {
        let viewModel = try self.makeViewModel()
        viewModel.onAppear()
        viewModel.setAmountRequest(asset: self.makeSolRow())
        viewModel.updateAmountText("not-a-number")
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(viewModel.qrPayload.hasPrefix("solana:"))
        XCTAssertFalse(
            viewModel.qrPayload.contains("amount="),
            "unparseable amount should not produce amount= query item: \(viewModel.qrPayload)")
    }
}
