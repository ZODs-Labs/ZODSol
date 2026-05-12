import Foundation
import XCTest
import SolanaKit
import WalletOverviewDomain
@testable import WalletOverviewUI

final class PendingSendBannerTests: XCTestCase {

    func testViewModelConfirmedShowsConfirmedTitle() throws {
        let signature = try Self.makeSignature()
        let info = PendingSendDisplayInfo(
            signature: signature,
            outcome: .confirmed(signature, slot: 100)
        )

        let model = PendingSendBannerViewModel(info: info)

        XCTAssertEqual(model.title, "Send confirmed")
        XCTAssertEqual(model.iconName, "checkmark.circle.fill")
    }

    func testViewModelFailedShowsFailedTitle() throws {
        let signature = try Self.makeSignature()
        let info = PendingSendDisplayInfo(
            signature: signature,
            outcome: .failed(signature, error: "runtime")
        )

        let model = PendingSendBannerViewModel(info: info)

        XCTAssertEqual(model.title, "Send failed")
        XCTAssertEqual(model.iconName, "xmark.circle.fill")
    }

    func testViewModelExpiredShowsExpiredTitle() throws {
        let signature = try Self.makeSignature()
        let info = PendingSendDisplayInfo(
            signature: signature,
            outcome: .expired(signature)
        )

        let model = PendingSendBannerViewModel(info: info)

        XCTAssertEqual(model.title, "Send expired")
        XCTAssertEqual(model.iconName, "clock.badge.exclamationmark.fill")
    }

    func testViewModelPendingPreviewShowsConfirmingTitle() throws {
        let signature = try Self.makeSignature()

        let model = PendingSendBannerViewModel.pendingPreview(signature: signature)

        XCTAssertEqual(model.title, "Confirming send...")
        XCTAssertEqual(model.iconName, "clock.badge")
    }

    func testViewModelSubtitleContainsShortenedSignature() throws {
        let signature = try Self.makeSignature()
        let info = PendingSendDisplayInfo(
            signature: signature,
            outcome: .confirmed(signature, slot: 100)
        )

        let model = PendingSendBannerViewModel(info: info)
        let base58 = signature.base58
        let expectedPrefix = String(base58.prefix(4))
        let expectedSuffix = String(base58.suffix(4))

        XCTAssertTrue(model.subtitle.hasPrefix(expectedPrefix))
        XCTAssertTrue(model.subtitle.hasSuffix(expectedSuffix))
        XCTAssertTrue(model.subtitle.contains("..."))
        XCTAssertLessThan(model.subtitle.count, base58.count)
    }

    // MARK: - Helpers

    private static func makeSignature() throws -> Signature {
        try Signature(bytes: Data(repeating: 0xAB, count: 64))
    }
}
