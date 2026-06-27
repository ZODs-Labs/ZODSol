import Foundation
import Observation
import SolanaKit
import WalletOverviewDomain

/// Drives the Menu Bar Widget settings screen. Owns the editable
/// `TickerSettings`, persists every change to `TickerSettingsStore` and pushes
/// the new settings to `onChange` so the status item reconfigures live. The
/// status item supplies `onChange` after the ticker stack is built.
@MainActor
@Observable
public final class TickerSettingsViewModel {
    public private(set) var settings: TickerSettings
    public private(set) var isResolving = false
    public private(set) var addError: String?
    public var onChange: ((TickerSettings) -> Void)?

    private let store: TickerSettingsStore
    private let resolver: (any TickerTokenResolving)?

    public init(
        store: TickerSettingsStore,
        resolver: (any TickerTokenResolving)? = nil,
        initial: TickerSettings = .seeded)
    {
        self.store = store
        self.resolver = resolver
        self.settings = initial
    }

    public func load() async {
        self.settings = await self.store.load()
    }

    public var isWidgetEnabled: Bool { self.settings.isWidgetEnabled }
    public var displayMode: TickerDisplayMode { self.settings.displayMode }
    public var availableBlueChips: [TickerCatalog.BlueChip] { TickerCatalog.blueChips }
    public var canAddMore: Bool { self.settings.entries.count < TickerSettingsStore.maxEntries }
    public var canResolveMints: Bool { self.resolver != nil }

    /// Custom (pasted) tokens, in selection order.
    public var customEntries: [TickerEntry] {
        self.settings.entries.filter { $0.source == .jupiter }
    }

    public func isAdded(_ chip: TickerCatalog.BlueChip) -> Bool {
        self.settings.entries.contains { $0.sourceIdentifier == chip.krakenPair }
    }

    public func setWidgetEnabled(_ enabled: Bool) {
        self.settings.isWidgetEnabled = enabled
        self.commit()
    }

    public func setDisplayMode(_ mode: TickerDisplayMode) {
        self.settings.displayMode = mode
        self.commit()
    }

    /// Adds the blue-chip if absent and under the cap, otherwise removes it.
    public func toggle(_ chip: TickerCatalog.BlueChip) {
        if let index = self.settings.entries.firstIndex(where: { $0.sourceIdentifier == chip.krakenPair }) {
            self.settings.entries.remove(at: index)
        } else if self.canAddMore, let entry = TickerCatalog.blueChipEntry(symbol: chip.symbol) {
            self.settings.entries.append(entry)
        }
        self.commit()
    }

    public func removeEntry(id: UUID) {
        self.settings.entries.removeAll { $0.id == id }
        self.commit()
    }

    /// Validates a pasted mint, resolves its metadata via Jupiter and adds it as
    /// a `.jupiter` entry. Surfaces a user-facing message in `addError` on any
    /// failure; never throws.
    public func addPastedMint(_ raw: String) async {
        self.addError = nil
        let mint = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mint.isEmpty else { return }
        guard (try? Mint(base58: mint)) != nil else {
            self.addError = "That is not a valid mint address."
            return
        }
        guard mint != TickerCatalog.wrappedSolMint else {
            self.addError = "SOL is already available in the Tokens list."
            return
        }
        guard !self.settings.entries.contains(where: { $0.sourceIdentifier == mint }) else {
            self.addError = "That token is already in the ticker."
            return
        }
        guard self.canAddMore else {
            self.addError = "The ticker is full. Remove a token first."
            return
        }
        guard let resolver = self.resolver else { return }

        self.isResolving = true
        let resolved = await resolver.resolve(mint: mint)
        self.isResolving = false

        guard let resolved else {
            self.addError = "Could not find that token."
            return
        }
        let entry = TickerCatalog.jupiterEntry(
            mint: resolved.mint,
            symbol: resolved.symbol,
            displayName: resolved.name,
            displayDecimals: resolved.decimals,
            iconURL: resolved.iconURL)
        self.settings.entries.append(entry)
        self.commit()
    }

    public func clearAddError() {
        self.addError = nil
    }

    private func commit() {
        let snapshot = self.settings
        Task { await self.store.save(snapshot) }
        self.onChange?(snapshot)
    }
}
