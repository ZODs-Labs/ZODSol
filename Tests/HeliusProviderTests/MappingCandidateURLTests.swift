import Foundation
import XCTest
@testable import HeliusProvider

final class MappingCandidateURLTests: XCTestCase {
    func test_returnsEmptyWhenNoContent() {
        XCTAssertTrue(HeliusSolanaProvider.candidateLogoURLs(content: nil).isEmpty)
    }

    func test_returnsAllPermittedCandidatesPreferredFirst() {
        let content = HeliusAssetsByOwnerResult.HeliusContent(
            json_uri: nil,
            files: [
                HeliusAssetsByOwnerResult.HeliusFile(
                    uri: "https://gateway.irys.xyz/payload",
                    cdn_uri: "https://cdn.helius-rpc.com/cdn-cgi/image//https://gateway.irys.xyz/payload",
                    mime: "image/png"),
            ],
            links: HeliusAssetsByOwnerResult.HeliusLinks(
                image: "https://i.ibb.co/abc/photo.jpg",
                external_url: nil),
            metadata: nil)
        let candidates = HeliusSolanaProvider.candidateLogoURLs(content: content)
        XCTAssertEqual(candidates.map(\.absoluteString), [
            "https://cdn.helius-rpc.com/cdn-cgi/image//https://gateway.irys.xyz/payload",
            "https://gateway.irys.xyz/payload",
            "https://i.ibb.co/abc/photo.jpg",
        ])
    }

    func test_dewrapsCDNAsLastResort() {
        let content = HeliusAssetsByOwnerResult.HeliusContent(
            json_uri: nil,
            files: [
                HeliusAssetsByOwnerResult.HeliusFile(
                    uri: nil,
                    cdn_uri: "https://cdn.helius-rpc.com/cdn-cgi/image//https://cf-ipfs.com/ipfs/Qm123",
                    mime: nil),
            ],
            links: nil,
            metadata: nil)
        let candidates = HeliusSolanaProvider.candidateLogoURLs(content: content)
        XCTAssertEqual(candidates.map(\.absoluteString), [
            "https://cdn.helius-rpc.com/cdn-cgi/image//https://cf-ipfs.com/ipfs/Qm123",
            "https://cf-ipfs.com/ipfs/Qm123",
        ])
    }

    func test_dropsBlockedHostsButKeepsPermitted() {
        let content = HeliusAssetsByOwnerResult.HeliusContent(
            json_uri: nil,
            files: [
                HeliusAssetsByOwnerResult.HeliusFile(
                    uri: "https://ipfs.io/ipfs/Qmblocked",
                    cdn_uri: nil,
                    mime: nil),
            ],
            links: HeliusAssetsByOwnerResult.HeliusLinks(
                image: "https://arweave.net/permitted",
                external_url: nil),
            metadata: nil)
        let candidates = HeliusSolanaProvider.candidateLogoURLs(content: content)
        XCTAssertEqual(candidates.map(\.absoluteString), [
            "https://arweave.net/permitted",
        ])
    }

    func test_dedupesIdenticalURLs() {
        let content = HeliusAssetsByOwnerResult.HeliusContent(
            json_uri: nil,
            files: [
                HeliusAssetsByOwnerResult.HeliusFile(
                    uri: "https://arweave.net/abc",
                    cdn_uri: nil,
                    mime: nil),
            ],
            links: HeliusAssetsByOwnerResult.HeliusLinks(
                image: "https://arweave.net/abc",
                external_url: nil),
            metadata: nil)
        let candidates = HeliusSolanaProvider.candidateLogoURLs(content: content)
        XCTAssertEqual(candidates.count, 1)
    }
}
