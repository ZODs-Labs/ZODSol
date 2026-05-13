import Foundation
import XCTest
@testable import SolanaRPC

final class URLSessionConfigurationTests: XCTestCase {
    func test_makeDefault_timeoutIntervalForRequest_is20() {
        let config = URLSessionConfiguration.makeDefault()
        XCTAssertEqual(config.timeoutIntervalForRequest, 20)
    }

    func test_makeDefault_timeoutIntervalForResource_is60() {
        let config = URLSessionConfiguration.makeDefault()
        XCTAssertEqual(config.timeoutIntervalForResource, 60)
    }

    func test_makeDefault_waitsForConnectivity_isFalse() {
        let config = URLSessionConfiguration.makeDefault()
        XCTAssertFalse(config.waitsForConnectivity)
    }

    func test_makeDefault_acceptHeader_isApplicationJSON() {
        let config = URLSessionConfiguration.makeDefault()
        let headers = config.httpAdditionalHeaders ?? [:]
        XCTAssertEqual(headers["Accept"] as? String, "application/json")
    }

    func test_makeDefault_contentTypeHeader_isApplicationJSON() {
        let config = URLSessionConfiguration.makeDefault()
        let headers = config.httpAdditionalHeaders ?? [:]
        XCTAssertEqual(headers["Content-Type"] as? String, "application/json")
    }

    func test_makeDefault_acceptEncoding_isBrGzipDeflate() {
        let config = URLSessionConfiguration.makeDefault()
        let headers = config.httpAdditionalHeaders ?? [:]
        XCTAssertEqual(headers["Accept-Encoding"] as? String, "br,gzip,deflate")
    }

    func test_makeDefault_solanaClient_isStamped() {
        let config = URLSessionConfiguration.makeDefault(clientVersion: "9.9.9")
        let headers = config.httpAdditionalHeaders ?? [:]
        XCTAssertEqual(headers["Solana-Client"] as? String, "zodsol/9.9.9")
    }

    func test_makeDefault_requestCachePolicy_ignoresLocalCache() {
        let config = URLSessionConfiguration.makeDefault()
        XCTAssertEqual(config.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func test_makeDefault_urlCache_isNil() {
        let config = URLSessionConfiguration.makeDefault()
        XCTAssertNil(config.urlCache)
    }
}
