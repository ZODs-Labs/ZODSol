import Foundation
import XCTest
@testable import HeliusProvider

final class ImageURLPolicyTests: XCTestCase {
    func test_permitsHeliusCDN() {
        let url = URL(string: "https://cdn.helius-rpc.com/cdn-cgi/image/abc/123.png")!
        XCTAssertTrue(ImageURLPolicy.isPermitted(url))
    }

    func test_permitsArweave() {
        let arweave = URL(string: "https://arweave.net/abc123")!
        let arweaveSubdomain = URL(string: "https://gateway.arweave.net/abc123")!
        XCTAssertTrue(ImageURLPolicy.isPermitted(arweave))
        XCTAssertTrue(ImageURLPolicy.isPermitted(arweaveSubdomain))
    }

    func test_rejectsPublicIPFSGateway() {
        let url = URL(string: "https://ipfs.io/ipfs/QmQYa8Q2TCUHdB5BoTtvKQg2GSmjJjRGVgBvYpXDrFyq3R")!
        XCTAssertFalse(ImageURLPolicy.isPermitted(url))
    }

    func test_rejectsScamCDNWithNumericSubdomain() {
        let url = URL(string: "https://cdn1849274925.com/650.png")!
        XCTAssertFalse(ImageURLPolicy.isPermitted(url))
    }

    func test_rejectsUnknownHost() {
        let url = URL(string: "https://random-host-not-in-allowlist.example/img.png")!
        XCTAssertFalse(ImageURLPolicy.isPermitted(url))
    }

    func test_rejectsPinataGateway() {
        let url = URL(string: "https://gateway.pinata.cloud/ipfs/QmXyz")!
        XCTAssertFalse(ImageURLPolicy.isPermitted(url))
    }

    func test_permitsNFTStorageLink() {
        let url = URL(string: "https://bafy.ipfs.nftstorage.link/img.png")!
        XCTAssertTrue(ImageURLPolicy.isPermitted(url))
    }
}
