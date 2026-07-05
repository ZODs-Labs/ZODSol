import Foundation
import XCTest
@testable import DataProviders

final class ImageURLPolicyTests: XCTestCase {
    func test_permitsHeliusCDN() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.helius-rpc.com/cdn-cgi/image/abc/123.png"))
        XCTAssertTrue(ImageURLPolicy.isPermitted(url))
    }

    func test_permitsArweave() throws {
        let arweave = try XCTUnwrap(URL(string: "https://arweave.net/abc123"))
        let arweaveSubdomain = try XCTUnwrap(URL(string: "https://gateway.arweave.net/abc123"))
        XCTAssertTrue(ImageURLPolicy.isPermitted(arweave))
        XCTAssertTrue(ImageURLPolicy.isPermitted(arweaveSubdomain))
    }

    func test_rejectsPublicIPFSGateway() throws {
        let url = try XCTUnwrap(URL(string: "https://ipfs.io/ipfs/QmQYa8Q2TCUHdB5BoTtvKQg2GSmjJjRGVgBvYpXDrFyq3R"))
        XCTAssertFalse(ImageURLPolicy.isPermitted(url))
    }

    func test_rejectsScamCDNWithNumericSubdomain() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn1849274925.com/650.png"))
        XCTAssertFalse(ImageURLPolicy.isPermitted(url))
    }

    func test_rejectsUnknownHost() throws {
        let url = try XCTUnwrap(URL(string: "https://random-host-not-in-allowlist.example/img.png"))
        XCTAssertFalse(ImageURLPolicy.isPermitted(url))
    }

    func test_rejectsPinataGateway() throws {
        let url = try XCTUnwrap(URL(string: "https://gateway.pinata.cloud/ipfs/QmXyz"))
        XCTAssertFalse(ImageURLPolicy.isPermitted(url))
    }

    func test_permitsNFTStorageLink() throws {
        let url = try XCTUnwrap(URL(string: "https://bafy.ipfs.nftstorage.link/img.png"))
        XCTAssertTrue(ImageURLPolicy.isPermitted(url))
    }

    func test_permitsIrysGateway() throws {
        XCTAssertTrue(try ImageURLPolicy.isPermitted(
            XCTUnwrap(URL(string: "https://gateway.irys.xyz/hGDDhM"))))
        XCTAssertTrue(try ImageURLPolicy.isPermitted(
            XCTUnwrap(URL(string: "https://node1.irys.xyz/hGDDhM"))))
    }

    func test_permitsIBBHost() throws {
        XCTAssertTrue(try ImageURLPolicy.isPermitted(
            XCTUnwrap(URL(string: "https://i.ibb.co/dDxDytJ/photo.jpg"))))
    }

    func test_permitsCFIpfsAndDwebLink() throws {
        XCTAssertTrue(try ImageURLPolicy.isPermitted(
            XCTUnwrap(URL(string: "https://cf-ipfs.com/ipfs/QmXyz"))))
        XCTAssertTrue(try ImageURLPolicy.isPermitted(
            XCTUnwrap(URL(string: "https://dweb.link/ipfs/QmXyz"))))
    }

    func test_permitsW3SIpfsSubdomain() throws {
        XCTAssertTrue(try ImageURLPolicy.isPermitted(
            XCTUnwrap(URL(string: "https://bafkrei.ipfs.w3s.link/image.png"))))
    }
}
