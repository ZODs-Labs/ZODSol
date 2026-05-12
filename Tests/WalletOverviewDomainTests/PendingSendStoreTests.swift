import Foundation
import SolanaKit
import XCTest
@testable import WalletOverviewDomain

/// `UserDefaults` is documented as thread-safe but the Swift compiler does
/// not infer `Sendable` for it under strict concurrency. We wrap each test
/// in a local fixture so the reference never escapes a task boundary the
/// compiler can't reason about.
private struct DefaultsFixture: @unchecked Sendable {
    let defaults: UserDefaults
    let suiteName: String
    let key: String
}

private func makeFixture() -> DefaultsFixture {
    let suiteName = "PendingSendStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return DefaultsFixture(defaults: defaults, suiteName: suiteName, key: "test.pendingSends")
}

private func cleanup(_ fixture: DefaultsFixture) {
    fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
}

private func makeStore(_ fixture: DefaultsFixture) -> PendingSendStore {
    PendingSendStore(defaults: fixture.defaults, key: fixture.key)
}

private func makePending(
    signature: String = "sig-\(UUID().uuidString)",
    wallet: UUID = UUID(),
    lastValidBlockHeight: UInt64 = 1000,
    network: SolanaNetwork = .mainnet,
    createdAt: Date = Date()) -> PendingSend
{
    PendingSend(
        walletId: wallet,
        signatureBase58: signature,
        lastValidBlockHeight: lastValidBlockHeight,
        network: network,
        createdAt: createdAt)
}

final class PendingSendStoreTests: XCTestCase {
    func testAddAndList() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let walletA = UUID()
        let walletB = UUID()
        let a = makePending(signature: "a", wallet: walletA)
        let b = makePending(signature: "b", wallet: walletB)
        await store.add(a)
        await store.add(b)
        let listA = await store.list(for: walletA)
        let listB = await store.list(for: walletB)
        XCTAssertEqual(listA, [a])
        XCTAssertEqual(listB, [b])
    }

    func testAddIsIdempotentBySignature() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let p1 = makePending(signature: "dup", wallet: UUID())
        let p2 = PendingSend(
            walletId: p1.walletId, signatureBase58: "dup",
            lastValidBlockHeight: p1.lastValidBlockHeight + 1,
            network: p1.network, createdAt: p1.createdAt.addingTimeInterval(1))
        await store.add(p1)
        await store.add(p2)
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.lastValidBlockHeight, p2.lastValidBlockHeight)
    }

    func testRemove() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let a = makePending(signature: "a")
        let b = makePending(signature: "b")
        await store.add(a)
        await store.add(b)
        await store.remove(signatureBase58: "a")
        let all = await store.all()
        XCTAssertEqual(all.map(\.signatureBase58), ["b"])
    }

    func testCapEvictsOldestEntries() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<(PendingSendStore.maxEntries + 3) {
            await store.add(makePending(
                signature: "s\(index)",
                createdAt: base.addingTimeInterval(Double(index))))
        }
        let all = await store.all()
        XCTAssertEqual(all.count, PendingSendStore.maxEntries)
        let signatures = Set(all.map(\.signatureBase58))
        XCTAssertFalse(signatures.contains("s0"))
        XCTAssertFalse(signatures.contains("s1"))
        XCTAssertFalse(signatures.contains("s2"))
        XCTAssertTrue(signatures.contains("s\(PendingSendStore.maxEntries + 2)"))
    }

    func testPruneRemovesOldEntriesOnly() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let now = Date()
        let old = makePending(signature: "old", createdAt: now.addingTimeInterval(-3600))
        let recent = makePending(signature: "recent", createdAt: now.addingTimeInterval(-30))
        await store.add(old)
        await store.add(recent)
        await store.prune(olderThan: 60, now: now)
        let all = await store.all()
        XCTAssertEqual(all.map(\.signatureBase58), ["recent"])
    }

    func testEntriesPersistAcrossInstancesViaUserDefaults() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let storeA = makeStore(fixture)
        let p = makePending(signature: "persist", network: .devnet)
        await storeA.add(p)
        let storeB = makeStore(fixture)
        let listed = await storeB.all()
        XCTAssertEqual(listed.map(\.signatureBase58), ["persist"])
        XCTAssertEqual(listed.first?.network, .devnet)
    }
}
