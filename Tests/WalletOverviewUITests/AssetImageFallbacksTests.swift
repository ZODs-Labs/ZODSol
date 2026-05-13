import Foundation
import XCTest
@testable import WalletOverviewUI

final class AssetImageFallbacksTests: XCTestCase {
    func test_chain_putsIPFSAlternatesBeforeOriginExtraction() throws {
        let cdnRaw = "https://cdn.helius-rpc.com/cdn-cgi/image//https://ipfs.io/ipfs/QmCircular"
        let url = try XCTUnwrap(URL(string: cdnRaw))
        let primary = try XCTUnwrap(HeliusCDNRewriter.optimized(url, pixelWidth: 64))
        let chain = AssetImageFallbacks.chain(
            url: url,
            primary: primary,
            initial: []).map(\.absoluteString)
        XCTAssertEqual(chain, [
            "https://dweb.link/ipfs/QmCircular",
            "https://nftstorage.link/ipfs/QmCircular",
            "https://w3s.link/ipfs/QmCircular",
            "https://ipfs.io/ipfs/QmCircular",
        ])
    }

    func test_chain_dedupesAcrossSources() throws {
        let url = try XCTUnwrap(URL(string: "https://ipfs.io/ipfs/QmDup/x.png"))
        let primary = url
        let alt = try XCTUnwrap(URL(string: "https://dweb.link/ipfs/QmDup/x.png"))
        let chain = AssetImageFallbacks.chain(
            url: url,
            primary: primary,
            initial: [alt]).map(\.absoluteString)
        XCTAssertEqual(chain, [
            "https://dweb.link/ipfs/QmDup/x.png",
            "https://nftstorage.link/ipfs/QmDup/x.png",
            "https://w3s.link/ipfs/QmDup/x.png",
        ])
    }

    func test_chain_nonIPFSURLOnlyAddsInitialAndOrigin() throws {
        let raw = "https://cdn.helius-rpc.com/cdn-cgi/image//https://edge.uxento.io/image/Qmid"
        let url = try XCTUnwrap(URL(string: raw))
        let chain = AssetImageFallbacks.chain(
            url: url,
            primary: url,
            initial: []).map(\.absoluteString)
        XCTAssertEqual(chain, [
            "https://edge.uxento.io/image/Qmid",
        ])
    }

    func test_chain_initialURLsPreservedInOrder() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a.png"))
        let alt1 = try XCTUnwrap(URL(string: "https://example.com/b.png"))
        let alt2 = try XCTUnwrap(URL(string: "https://example.com/c.png"))
        let chain = AssetImageFallbacks.chain(
            url: url,
            primary: url,
            initial: [alt1, alt2]).map(\.absoluteString)
        XCTAssertEqual(chain, [
            "https://example.com/b.png",
            "https://example.com/c.png",
        ])
    }
}
