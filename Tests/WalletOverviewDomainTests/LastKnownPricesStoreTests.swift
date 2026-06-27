import Foundation
import SolanaKit
import XCTest
@testable import WalletOverviewDomain

private struct PricesFixture: @unchecked Sendable {
    let defaults: UserDefaults
    let suiteName: String
    let key: String
}

private func makeFixture() -> PricesFixture {
    let suiteName = "LastKnownPricesStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return PricesFixture(defaults: defaults, suiteName: suiteName, key: "test.lastKnownPrices")
}

private func cleanup(_ fixture: PricesFixture) {
    fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
}

private func makeStore(_ fixture: PricesFixture) -> LastKnownPricesStore {
    LastKnownPricesStore(defaults: fixture.defaults, key: fixture.key)
}

private func price(_ usd: String, at capturedAt: Date) -> LastKnownPrice {
    LastKnownPrice(
        quote: PriceQuote(usdPrice: Decimal(string: usd), change24h: 1.5),
        capturedAt: capturedAt)
}

final class LastKnownPricesStoreTests: XCTestCase {
    func testRoundTrip() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let now = Date()
        let prices = ["XXBTZUSD": price("64000", at: now), "SOLUSD": price("150", at: now)]
        await store.save(prices)

        let loaded = await store.load(now: now)
        XCTAssertEqual(loaded["XXBTZUSD"]?.quote.usdPrice, Decimal(string: "64000"))
        XCTAssertEqual(loaded["SOLUSD"]?.quote.usdPrice, Decimal(string: "150"))
    }

    func testLoadPrunesEntriesOlderThanMaxAge() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let now = Date()
        let stale = now.addingTimeInterval(-(LastKnownPricesStore.maxAge + 60))
        await store.save(["fresh": price("1", at: now), "stale": price("2", at: stale)])

        let loaded = await store.load(now: now)
        XCTAssertNotNil(loaded["fresh"])
        XCTAssertNil(loaded["stale"])
    }

    func testSaveKeepsNewestWhenOverCap() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let now = Date()
        var prices: [String: LastKnownPrice] = [:]
        for index in 0..<(LastKnownPricesStore.maxEntries + 10) {
            prices["mint\(index)"] = price("\(index)", at: now.addingTimeInterval(Double(index)))
        }
        await store.save(prices)

        let loaded = await store.load(now: now.addingTimeInterval(100))
        XCTAssertEqual(loaded.count, LastKnownPricesStore.maxEntries)
        // The newest (highest index) must survive; the oldest (index 0) must not.
        XCTAssertNotNil(loaded["mint\(LastKnownPricesStore.maxEntries + 9)"])
        XCTAssertNil(loaded["mint0"])
    }

    func testEmptySaveClearsStorage() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        await store.save(["a": price("1", at: Date())])
        await store.save([:])
        let loaded = await store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testPersistsAcrossInstances() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let now = Date()
        await makeStore(fixture).save(["SOLUSD": price("150", at: now)])
        let loaded = await makeStore(fixture).load(now: now)
        XCTAssertEqual(loaded["SOLUSD"]?.quote.usdPrice, Decimal(string: "150"))
    }
}
