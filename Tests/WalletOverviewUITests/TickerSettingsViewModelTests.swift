import Foundation
import SolanaKit
import WalletOverviewDomain
import XCTest
@testable import WalletOverviewUI

/// Synchronous so the non-Sendable UserDefaults never crosses an async boundary.
private func makeStore() -> TickerSettingsStore {
    let suiteName = "TickerSettingsViewModelTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return TickerSettingsStore(defaults: defaults, key: "test.tickerSettings")
}

private func empty() -> TickerSettings {
    TickerSettings(isWidgetEnabled: false, displayMode: .symbolAndPrice, entries: [])
}

private let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

private struct StubResolver: TickerTokenResolving {
    let result: ResolvedTickerToken?
    func resolve(mint: String) async -> ResolvedTickerToken? {
        self.result
    }
}

private func resolvedUSDC() -> ResolvedTickerToken {
    ResolvedTickerToken(mint: usdcMint, symbol: "USDC", name: "USD Coin", decimals: 6, iconURL: nil)
}

@MainActor
final class TickerSettingsViewModelTests: XCTestCase {
    func testSetWidgetEnabledUpdatesAndNotifies() {
        let model = TickerSettingsViewModel(store: makeStore(), initial: empty())
        var notified: TickerSettings?
        model.onChange = { notified = $0 }

        model.setWidgetEnabled(true)

        XCTAssertTrue(model.isWidgetEnabled)
        XCTAssertEqual(notified?.isWidgetEnabled, true)
    }

    func testToggleAddsThenRemovesBlueChip() throws {
        let model = TickerSettingsViewModel(
            store: makeStore(),
            initial: TickerSettings(isWidgetEnabled: true, displayMode: .symbolAndPrice, entries: []))
        let btc = try XCTUnwrap(TickerCatalog.blueChips.first { $0.symbol == "BTC" })

        XCTAssertFalse(model.isAdded(btc))
        model.toggle(btc)
        XCTAssertTrue(model.isAdded(btc))
        XCTAssertEqual(model.settings.entries.first?.sourceIdentifier, "XXBTZUSD")

        model.toggle(btc)
        XCTAssertFalse(model.isAdded(btc))
        XCTAssertTrue(model.settings.entries.isEmpty)
    }

    func testSetDisplayModeNotifies() {
        let model = TickerSettingsViewModel(store: makeStore(), initial: empty())
        var notified: TickerDisplayMode?
        model.onChange = { notified = $0.displayMode }

        model.setDisplayMode(.priceOnly)

        XCTAssertEqual(model.displayMode, .priceOnly)
        XCTAssertEqual(notified, .priceOnly)
    }

    func testLoadReadsPersistedSettings() async {
        let store = makeStore()
        await store.save(TickerSettings(isWidgetEnabled: true, displayMode: .priceOnly, entries: []))

        let model = TickerSettingsViewModel(store: store, initial: empty())
        await model.load()

        XCTAssertTrue(model.isWidgetEnabled)
        XCTAssertEqual(model.displayMode, .priceOnly)
    }

    // MARK: - Pasted mints

    func testAddPastedMintResolvesAndAddsJupiterEntry() async {
        let model = TickerSettingsViewModel(
            store: makeStore(),
            resolver: StubResolver(result: resolvedUSDC()),
            initial: empty())

        await model.addPastedMint("  \(usdcMint)  ")

        XCTAssertNil(model.addError)
        XCTAssertEqual(model.customEntries.count, 1)
        XCTAssertEqual(model.customEntries.first?.symbol, "USDC")
        XCTAssertEqual(model.customEntries.first?.source, .jupiter)
        XCTAssertEqual(model.customEntries.first?.sourceIdentifier, usdcMint)
    }

    func testAddPastedInvalidMintSetsError() async {
        let model = TickerSettingsViewModel(
            store: makeStore(),
            resolver: StubResolver(result: resolvedUSDC()),
            initial: empty())

        await model.addPastedMint("not a valid mint!!!")

        XCTAssertNotNil(model.addError)
        XCTAssertTrue(model.customEntries.isEmpty)
    }

    func testAddPastedWrappedSolIsSteeredAway() async {
        let model = TickerSettingsViewModel(
            store: makeStore(),
            resolver: StubResolver(result: resolvedUSDC()),
            initial: empty())

        await model.addPastedMint(TickerCatalog.wrappedSolMint)

        XCTAssertNotNil(model.addError)
        XCTAssertTrue(model.customEntries.isEmpty)
    }

    func testAddPastedMintRejectsDuplicate() async {
        let model = TickerSettingsViewModel(
            store: makeStore(),
            resolver: StubResolver(result: resolvedUSDC()),
            initial: empty())

        await model.addPastedMint(usdcMint)
        await model.addPastedMint(usdcMint)

        XCTAssertEqual(model.customEntries.count, 1)
        XCTAssertNotNil(model.addError)
    }

    func testAddPastedMintUnresolvedSetsError() async {
        let model = TickerSettingsViewModel(
            store: makeStore(),
            resolver: StubResolver(result: nil),
            initial: empty())

        await model.addPastedMint(usdcMint)

        XCTAssertNil(model.customEntries.first)
        XCTAssertNotNil(model.addError)
    }

    func testRemoveCustomEntry() async {
        let model = TickerSettingsViewModel(
            store: makeStore(),
            resolver: StubResolver(result: resolvedUSDC()),
            initial: empty())
        await model.addPastedMint(usdcMint)
        let id = try? XCTUnwrap(model.customEntries.first?.id)

        if let id { model.removeEntry(id: id) }

        XCTAssertTrue(model.customEntries.isEmpty)
    }
}
