import AppKit
import CryptoKit
import XCTest
@testable import WalletOverviewUI

final class QRCodeRendererTests: XCTestCase {
    private let foreground: CGColor = NSColor.black.cgColor
    private let background: CGColor = NSColor.white.cgColor

    func testRendersShortPayload() async {
        let address = "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq"
        let image = await QRCodeRenderer.render(
            payload: address,
            foreground: self.foreground,
            background: self.background,
            sizeInPixels: 256)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }

    func testRendersLongSolanaPayURI() async {
        let recipient = "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq"
        let reference = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
        let payload = "solana:\(recipient)?amount=1.234567"
            + "&spl-token=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
            + "&reference=\(reference)"
            + "&label=ZODSol%20Test%20Wallet"
            + "&message=Thanks%20for%20the%20coffee%20and%20the%20snacks"
            + "&memo=order-123456789-abcdef"
        XCTAssertGreaterThan(payload.count, 200)

        let image = await QRCodeRenderer.render(
            payload: payload,
            foreground: self.foreground,
            background: self.background,
            sizeInPixels: 512)
        XCTAssertNotNil(image)
    }

    func testReturnsNilForEmptyPayload() async {
        let image = await QRCodeRenderer.render(
            payload: "",
            foreground: self.foreground,
            background: self.background,
            sizeInPixels: 256)
        XCTAssertNil(image)
    }

    func testReturnsNilForNonPositiveSize() async {
        let image = await QRCodeRenderer.render(
            payload: "hello",
            foreground: self.foreground,
            background: self.background,
            sizeInPixels: 0)
        XCTAssertNil(image)
    }

    func testDeterministicForSameInput() async {
        let payload = "solana:5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq?amount=0.5"
        let first = await QRCodeRenderer.render(
            payload: payload,
            foreground: self.foreground,
            background: self.background,
            sizeInPixels: 256)
        let second = await QRCodeRenderer.render(
            payload: payload,
            foreground: self.foreground,
            background: self.background,
            sizeInPixels: 256)
        guard let firstTIFF = first?.tiffRepresentation,
              let secondTIFF = second?.tiffRepresentation
        else {
            XCTFail("expected both renders to produce TIFF data")
            return
        }
        XCTAssertGreaterThan(firstTIFF.count, 0)
        XCTAssertEqual(firstTIFF.count, secondTIFF.count)

        let firstDigest = SHA256.hash(data: firstTIFF)
        let secondDigest = SHA256.hash(data: secondTIFF)
        XCTAssertEqual(firstDigest, secondDigest)
    }
}
