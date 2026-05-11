import XCTest
@testable import KeychainKit

final class SecureItemTests: XCTestCase {
    func testInitCopiesValues() {
        let item = SecureItem(service: "svc", account: "acct")
        XCTAssertEqual(item.service, "svc")
        XCTAssertEqual(item.account, "acct")
    }

    func testHashableEquality() {
        let a = SecureItem(service: "s", account: "a")
        let b = SecureItem(service: "s", account: "a")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testHashableInequality() {
        let a = SecureItem(service: "s", account: "a")
        let b = SecureItem(service: "s", account: "b")
        XCTAssertNotEqual(a, b)
    }

    func testSendableConformance() {
        let item = SecureItem(service: "s", account: "a")
        let _: any Sendable = item
    }

    func testUsableInSet() {
        var set = Set<SecureItem>()
        let item = SecureItem(service: "s", account: "a")
        set.insert(item)
        set.insert(item)
        XCTAssertEqual(set.count, 1)
    }
}
