import Foundation
import XCTest
@testable import WalletOverviewUI

final class IPFSGatewayFallbackTests: XCTestCase {
    func test_parse_pathFormCID() throws {
        let url = try XCTUnwrap(URL(string: "https://ipfs.io/ipfs/QmAbc123/asset.png"))
        let parsed = try XCTUnwrap(IPFSGatewayFallback.parse(url))
        XCTAssertEqual(parsed.cid, "QmAbc123")
        XCTAssertEqual(parsed.rest, "asset.png")
    }

    func test_parse_pathFormCIDWithoutRest() throws {
        let url = try XCTUnwrap(URL(string: "https://ipfs.io/ipfs/QmAbc123"))
        let parsed = try XCTUnwrap(IPFSGatewayFallback.parse(url))
        XCTAssertEqual(parsed.cid, "QmAbc123")
        XCTAssertEqual(parsed.rest, "")
    }

    func test_parse_pathFormStripsQueryAndFragment() throws {
        let url = try XCTUnwrap(URL(string: "https://ipfs.io/ipfs/QmAbc123/x.png?w=64#frag"))
        let parsed = try XCTUnwrap(IPFSGatewayFallback.parse(url))
        XCTAssertEqual(parsed.cid, "QmAbc123")
        XCTAssertEqual(parsed.rest, "x.png")
    }

    func test_parse_subdomainForm() throws {
        let url = try XCTUnwrap(URL(string: "https://bafkrei.ipfs.dweb.link/x.png"))
        let parsed = try XCTUnwrap(IPFSGatewayFallback.parse(url))
        XCTAssertEqual(parsed.cid, "bafkrei")
        XCTAssertEqual(parsed.rest, "x.png")
    }

    func test_parse_returnsNilForNonIPFSURL() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/foo.png"))
        XCTAssertNil(IPFSGatewayFallback.parse(url))
    }

    func test_alternates_returnsAllGateways() throws {
        let url = try XCTUnwrap(URL(string: "https://ipfs.io/ipfs/QmAbc/file.png"))
        let alternates = IPFSGatewayFallback.alternates(for: url).map(\.absoluteString)
        XCTAssertEqual(alternates, [
            "https://dweb.link/ipfs/QmAbc/file.png",
            "https://nftstorage.link/ipfs/QmAbc/file.png",
            "https://w3s.link/ipfs/QmAbc/file.png",
        ])
    }

    func test_alternates_handlesCDNWrappedURL() throws {
        let raw = "https://cdn.helius-rpc.com/cdn-cgi/image//https://cf-ipfs.com/ipfs/QmXyz"
        let url = try XCTUnwrap(URL(string: raw))
        let alternates = IPFSGatewayFallback.alternates(for: url).map(\.absoluteString)
        XCTAssertEqual(alternates, [
            "https://dweb.link/ipfs/QmXyz",
            "https://nftstorage.link/ipfs/QmXyz",
            "https://w3s.link/ipfs/QmXyz",
        ])
    }

    func test_alternates_emptyWhenNoIPFS() throws {
        let url = try XCTUnwrap(URL(string: "https://raw.githubusercontent.com/x/y/z.png"))
        XCTAssertTrue(IPFSGatewayFallback.alternates(for: url).isEmpty)
    }
}
