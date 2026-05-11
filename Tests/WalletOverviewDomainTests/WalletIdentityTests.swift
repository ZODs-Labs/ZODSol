import XCTest
import SolanaKit
@testable import WalletOverviewDomain

final class WalletIdentityTests: XCTestCase {

    private func makeAddress() throws -> WalletAddress {
        let material = makeTestPrivateKey()
        return try WalletAddress(base58: material.base58Address)
    }

    func testCodableRoundTrip() throws {
        let address = try makeAddress()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let identity = WalletIdentity(id: UUID(), address: address, label: "Main", createdAt: createdAt)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(identity)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WalletIdentity.self, from: data)

        XCTAssertEqual(decoded, identity)
        XCTAssertEqual(decoded.label, "Main")
        XCTAssertEqual(decoded.address, address)
    }

    func testHashableByID() throws {
        let address = try makeAddress()
        let id = UUID()
        let now = Date()
        let a = WalletIdentity(id: id, address: address, label: "A", createdAt: now)
        let b = WalletIdentity(id: id, address: address, label: "A", createdAt: now)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)

        var set: Set<WalletIdentity> = [a]
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    func testDifferentIDsAreNotEqual() throws {
        let address = try makeAddress()
        let now = Date()
        let a = WalletIdentity(id: UUID(), address: address, label: "A", createdAt: now)
        let b = WalletIdentity(id: UUID(), address: address, label: "A", createdAt: now)
        XCTAssertNotEqual(a, b)
    }

    func testLabelIsMutable() throws {
        let address = try makeAddress()
        var identity = WalletIdentity(id: UUID(), address: address, label: "Old", createdAt: Date())
        identity.label = "New"
        XCTAssertEqual(identity.label, "New")
    }
}
