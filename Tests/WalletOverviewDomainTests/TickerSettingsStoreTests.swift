import Foundation
import SolanaKit
import XCTest
@testable import WalletOverviewDomain

private struct DefaultsFixture: @unchecked Sendable {
    let defaults: UserDefaults
    let suiteName: String
    let key: String
}

private func makeFixture() -> DefaultsFixture {
    let suiteName = "TickerSettingsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return DefaultsFixture(defaults: defaults, suiteName: suiteName, key: "test.tickerSettings")
}

private func cleanup(_ fixture: DefaultsFixture) {
    fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
}

private func makeStore(_ fixture: DefaultsFixture) -> TickerSettingsStore {
    TickerSettingsStore(defaults: fixture.defaults, key: fixture.key)
}

private func entry(_ identifier: String, source: TickerPriceSource = .jupiter) -> TickerEntry {
    TickerEntry(
        source: source,
        sourceIdentifier: identifier,
        symbol: identifier.prefix(4).uppercased(),
        displayName: identifier,
        displayDecimals: 4)
}

private func emptySettings() -> TickerSettings {
    TickerSettings(isWidgetEnabled: false, displayMode: .symbolAndPrice, entries: [])
}

final class TickerSettingsStoreTests: XCTestCase {
    func testLoadWhenAbsentReturnsSeededCuratedSetDisabled() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let settings = await makeStore(fixture).load()
        XCTAssertFalse(settings.isWidgetEnabled)
        XCTAssertEqual(settings.entries.map(\.symbol), ["SOL", "BTC", "ETH"])
    }

    func testSaveLoadRoundTrip() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        var settings = emptySettings()
        settings.isWidgetEnabled = true
        settings.displayMode = .symbolPriceAndChange
        settings.entries = [entry("mintA"), entry("mintB")]
        await store.save(settings)

        let loaded = await store.load()
        XCTAssertEqual(loaded, settings)
    }

    func testAddEntryDedupsBySourceIdentifier() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        await store.save(emptySettings())

        let first = await store.addEntry(entry("mintA"))
        let duplicate = await store.addEntry(entry("mintA", source: .kraken))

        XCTAssertTrue(first)
        XCTAssertFalse(duplicate)
        let count = await store.load().entries.count
        XCTAssertEqual(count, 1)
    }

    func testAddEntryRespectsCap() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        await store.save(emptySettings())

        for index in 0..<TickerSettingsStore.maxEntries {
            let added = await store.addEntry(entry("mint\(index)"))
            XCTAssertTrue(added)
        }
        let overCap = await store.addEntry(entry("oneTooMany"))
        XCTAssertFalse(overCap)
        let count = await store.load().entries.count
        XCTAssertEqual(count, TickerSettingsStore.maxEntries)
    }

    func testRemoveEntry() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let target = entry("mintA")
        await store.save(TickerSettings(isWidgetEnabled: false, displayMode: .symbolAndPrice, entries: [target]))

        await store.removeEntry(id: target.id)
        let entries = await store.load().entries
        XCTAssertTrue(entries.isEmpty)
    }

    func testSetEntryEnabledTogglesOneRow() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let target = entry("mintA")
        await store.save(TickerSettings(isWidgetEnabled: true, displayMode: .symbolAndPrice, entries: [target]))

        await store.setEntryEnabled(id: target.id, false)
        let entries = await store.load().entries
        XCTAssertEqual(entries.first?.isEnabled, false)
    }

    func testSetWidgetEnabledPersists() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        await store.save(emptySettings())
        await store.setWidgetEnabled(true)
        let loaded = await store.load()
        XCTAssertTrue(loaded.isWidgetEnabled)
    }

    func testPersistsAcrossInstances() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        await makeStore(fixture).save(
            TickerSettings(isWidgetEnabled: true, displayMode: .priceOnly, entries: [entry("mintA")]))

        let reloaded = await makeStore(fixture).load()
        XCTAssertTrue(reloaded.isWidgetEnabled)
        XCTAssertEqual(reloaded.displayMode, .priceOnly)
        XCTAssertEqual(reloaded.entries.map(\.sourceIdentifier), ["mintA"])
    }
}
