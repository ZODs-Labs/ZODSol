import Foundation
import SolanaKit
import XCTest
@testable import Formatters

final class SendAmountCalculatorTests: XCTestCase {
    // MARK: - Helpers

    private func solInput(
        balance: UInt64,
        priceUSD: Decimal? = Decimal(string: "150"),
        feeReserve: UInt64 = 5200,
        rentReserve: UInt64 = 890_880) -> SendAmountInput
    {
        SendAmountInput(
            balanceBaseUnits: balance,
            decimals: 9,
            priceUSD: priceUSD,
            feeReserveLamports: Lamports(rawValue: feeReserve),
            rentReserveLamports: Lamports(rawValue: rentReserve),
            isNativeSOL: true)
    }

    private func splInput(
        balance: UInt64,
        decimals: UInt8 = 6,
        priceUSD: Decimal? = Decimal(string: "1")) -> SendAmountInput
    {
        SendAmountInput(
            balanceBaseUnits: balance,
            decimals: decimals,
            priceUSD: priceUSD,
            feeReserveLamports: Lamports(rawValue: 5200),
            rentReserveLamports: Lamports(rawValue: 0),
            isNativeSOL: false)
    }

    // MARK: - Percentage cases

    func test_percentage_zeroBalance_returnsZeroBaseUnits() {
        let calc = SendAmountCalculator()
        let result = calc.compute(.percentage(0.5), input: self.solInput(balance: 0))
        XCTAssertEqual(result.baseUnits, 0)
        XCTAssertTrue(result.isZero)
    }

    func test_percentage_balanceBelowFeeReserve_clampsMaxSpendableToZero() {
        let calc = SendAmountCalculator()
        let result = calc.compute(.percentage(1.0), input: self.solInput(balance: 100))
        XCTAssertEqual(result.baseUnits, 0)
        XCTAssertTrue(result.isZero)
    }

    func test_percentage_solHappyPath_reservesFloorAndAtaRent() {
        let calc = SendAmountCalculator()
        let balance: UInt64 = 1_000_000_000
        let result = calc.compute(.percentage(1.0), input: self.solInput(balance: balance))
        XCTAssertEqual(result.baseUnits, balance - 5200 - 890_880)
    }

    func test_percentage_half_floorsNeverRoundsUp() {
        let calc = SendAmountCalculator()
        let result = calc.compute(.percentage(0.5), input: self.solInput(balance: 10_000_001 + 896_080))
        XCTAssertEqual(result.baseUnits, 5_000_000)
    }

    func test_percentage_above1Clamps() {
        let calc = SendAmountCalculator()
        let result = calc.compute(.percentage(1.5), input: self.solInput(balance: 1_000_000_000))
        let max = calc.maxSpendable(input: self.solInput(balance: 1_000_000_000))
        XCTAssertEqual(result.baseUnits, max)
    }

    func test_percentage_zero_returnsZero() {
        let calc = SendAmountCalculator()
        let result = calc.compute(.percentage(0.0), input: self.solInput(balance: 1_000_000_000))
        XCTAssertEqual(result.baseUnits, 0)
    }

    // MARK: - Max spendable

    func test_maxSpendable_solSubtractsFeeAndRent() {
        let calc = SendAmountCalculator()
        let max = calc.maxSpendable(input: self.solInput(balance: 1_000_000_000))
        XCTAssertEqual(max, 1_000_000_000 - 5200 - 890_880)
    }

    func test_maxSpendable_splTokenIsFullBalance() {
        let calc = SendAmountCalculator()
        let max = calc.maxSpendable(input: self.splInput(balance: 1_000_000))
        XCTAssertEqual(max, 1_000_000)
    }

    // MARK: - Manual token-mode parsing

    func test_manual_token_exactDecimalsRoundTrip() {
        let calc = SendAmountCalculator()
        let result = calc.compute(
            .manual(text: "1.5", mode: .token),
            input: self.solInput(balance: 10_000_000_000))
        XCTAssertEqual(result.baseUnits, 1_500_000_000)
        XCTAssertFalse(result.decimalsError)
    }

    func test_manual_token_tooManyDecimalsSetsDecimalsError() {
        let calc = SendAmountCalculator()
        let result = calc.compute(
            .manual(text: "0.0000000001", mode: .token),
            input: self.solInput(balance: 10_000_000_000))
        XCTAssertTrue(result.decimalsError)
        XCTAssertEqual(result.baseUnits, 0)
    }

    func test_manual_token_leadingZeroAccepted() {
        let calc = SendAmountCalculator()
        let result = calc.compute(
            .manual(text: "0.5", mode: .token),
            input: self.solInput(balance: 10_000_000_000))
        XCTAssertEqual(result.baseUnits, 500_000_000)
    }

    func test_manual_token_bareDotRejected_parseReturnsNil() {
        let calc = SendAmountCalculator()
        XCTAssertNil(calc.parse(text: ".5", decimals: 9))
    }

    func test_manual_token_nonNumericReturnsNilFromParse() {
        let calc = SendAmountCalculator()
        XCTAssertNil(calc.parse(text: "abc", decimals: 9))
    }

    func test_manual_token_emptyTextProducesIsZero() {
        let calc = SendAmountCalculator()
        let result = calc.compute(
            .manual(text: "", mode: .token),
            input: self.solInput(balance: 10_000_000_000))
        XCTAssertTrue(result.isZero)
    }

    // MARK: - Manual fiat-mode parsing

    func test_manual_fiat_floorsConversion() {
        let calc = SendAmountCalculator()
        let result = calc.compute(
            .manual(text: "1.00", mode: .fiat),
            input: self.solInput(balance: 1_000_000_000, priceUSD: Decimal(string: "3")))
        XCTAssertEqual(result.baseUnits, 333_333_333)
    }

    func test_manual_fiat_priceUSDNilDisablesFiat_fallsBackToTokenParse() {
        let calc = SendAmountCalculator()
        let result = calc.compute(
            .manual(text: "1", mode: .fiat),
            input: self.solInput(balance: 10_000_000_000, priceUSD: nil))
        XCTAssertEqual(result.baseUnits, 1_000_000_000)
    }

    func test_manual_fiat_roundsToZero_setsRoundedToZeroFlag() {
        let calc = SendAmountCalculator()
        let input = SendAmountInput(
            balanceBaseUnits: 1_000_000,
            decimals: 2,
            priceUSD: Decimal(string: "1"),
            feeReserveLamports: Lamports(rawValue: 0),
            rentReserveLamports: Lamports(rawValue: 0),
            isNativeSOL: false)
        let result = calc.compute(.manual(text: "0.0001", mode: .fiat), input: input)
        XCTAssertEqual(result.baseUnits, 0)
        XCTAssertTrue(result.roundedToZero)
    }

    // MARK: - exceedsBalance

    func test_manual_token_overBalanceFlagsExceedsBalance() {
        let calc = SendAmountCalculator()
        let result = calc.compute(
            .manual(text: "1000", mode: .token),
            input: self.solInput(balance: 1_000_000_000))
        XCTAssertTrue(result.exceedsBalance)
    }

    // MARK: - displayFiat

    func test_manual_token_priceUSDNil_returnsNilDisplayFiat() {
        let calc = SendAmountCalculator()
        let result = calc.compute(
            .manual(text: "1", mode: .token),
            input: self.solInput(balance: 10_000_000_000, priceUSD: nil))
        XCTAssertNil(result.displayFiat)
    }

    func test_manual_token_priceUSDPresent_returnsFormattedFiat() {
        let calc = SendAmountCalculator()
        let result = calc.compute(
            .manual(text: "1", mode: .token),
            input: self.solInput(balance: 10_000_000_000, priceUSD: Decimal(string: "150")))
        XCTAssertNotNil(result.displayFiat)
    }
}
