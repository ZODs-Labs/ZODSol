import Foundation
import XCTest
@testable import WalletOverviewUI

final class HeliusCDNRewriterTests: XCTestCase {
    func test_optimized_injectsOptionsIntoEmptySlot() throws {
        let raw = "https://cdn.helius-rpc.com/cdn-cgi/image//https://cf-ipfs.com/ipfs/Qm123"
        let url = try XCTUnwrap(URL(string: raw))
        let rewritten = try XCTUnwrap(HeliusCDNRewriter.optimized(url, pixelWidth: 64))
        let expected = "https://cdn.helius-rpc.com/cdn-cgi/image/"
            + "width=64,quality=85,format=auto,fit=cover/https://cf-ipfs.com/ipfs/Qm123"
        XCTAssertEqual(rewritten.absoluteString, expected)
    }

    func test_optimized_replacesExistingOptions() throws {
        let raw = "https://cdn.helius-rpc.com/cdn-cgi/image/width=1024/https://arweave.net/abc"
        let url = try XCTUnwrap(URL(string: raw))
        let rewritten = try XCTUnwrap(HeliusCDNRewriter.optimized(url, pixelWidth: 80))
        let expected = "https://cdn.helius-rpc.com/cdn-cgi/image/"
            + "width=80,quality=85,format=auto,fit=cover/https://arweave.net/abc"
        XCTAssertEqual(rewritten.absoluteString, expected)
    }

    func test_optimized_returnsNilForNonHeliusURL() throws {
        let url = try XCTUnwrap(URL(string: "https://gateway.irys.xyz/abc"))
        XCTAssertNil(HeliusCDNRewriter.optimized(url, pixelWidth: 64))
    }

    func test_optimized_returnsNilForMalformedCDNURL() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.helius-rpc.com/no-image-marker/foo"))
        XCTAssertNil(HeliusCDNRewriter.optimized(url, pixelWidth: 64))
    }

    func test_origin_extractsUnderlyingURL() throws {
        let raw = "https://cdn.helius-rpc.com/cdn-cgi/image//https://gateway.irys.xyz/hGDDhM"
        let url = try XCTUnwrap(URL(string: raw))
        let origin = try XCTUnwrap(HeliusCDNRewriter.origin(url))
        XCTAssertEqual(origin.absoluteString, "https://gateway.irys.xyz/hGDDhM")
    }

    func test_origin_returnsNilWhenInnerIsNotHTTP() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.helius-rpc.com/cdn-cgi/image//ipfs://Qmabc"))
        XCTAssertNil(HeliusCDNRewriter.origin(url))
    }

    func test_origin_returnsNilForNonHeliusURL() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/foo.png"))
        XCTAssertNil(HeliusCDNRewriter.origin(url))
    }
}
