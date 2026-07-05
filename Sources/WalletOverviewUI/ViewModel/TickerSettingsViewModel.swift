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
    /// Set when a pasted EVM address is live on several chains; drives the picker.
    public private(set) var chainChoices: [PasteChainCandidate]?
    public var onChange: ((TickerSettings) -> Void)?

    private let store: TickerSettingsStore
    private let pasteResolver: TokenPasteResolver?

    public init(
        store: TickerSettingsStore,
        pasteResolver: TokenPasteResolver? = nil,
        initial: TickerSettings = .seeded)
    {
        self.store = store
        self.pasteResolver = pasteResolver
        self.settings = initial
    }

    public func load() async {
        self.settings = await self.store.load()
    }

    public var isWidgetEnabled: Bool {
        self.settings.isWidgetEnabled
    }

    public var displayMode: TickerDisplayMode {
        self.settings.displayMode
    }

    public var availableBlueChips: [TickerCatalog.BlueChip] {
        TickerCatalog.blueChips
    }

    public var canAddMore: Bool {
        self.settings.entries.count < TickerSettingsStore.maxEntries
    }

    public var canResolve: Bool {
        self.pasteResolver != nil
    }

    /// Custom (pasted) tokens - Solana mints and EVM tokens - in selection order.
    public var customEntries: [TickerEntry] {
        self.settings.entries.filter { $0.source == .jupiter || $0.source == .evmDex }
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

    /// Resolves a pasted token address (Solana mint or EVM contract) through the
    /// facade and adds it, prompts a chain choice when an EVM address is live on
    /// several chains, or surfaces a user-facing message. Never throws.
    public func addPasted(_ raw: String) async {
        self.addError = nil
        self.chainChoices = nil
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard self.canAddMore else {
            self.addError = "The ticker is full. Remove a token first."
            return
        }
        guard let pasteResolver = self.pasteResolver else { return }

        self.isResolving = true
        let resolution = await pasteResolver.resolve(trimmed)
        self.isResolving = false

        switch resolution {
        case let .resolved(entry):
            self.appendIfNew(entry)
        case let .needsChainChoice(candidates):
            self.chainChoices = candidates
        case let .rejected(message):
            if !message.isEmpty { self.addError = message }
        }
    }

    /// Confirms a chain from the disambiguation prompt and adds that entry.
    public func chooseChain(_ candidate: PasteChainCandidate) {
        self.chainChoices = nil
        self.appendIfNew(candidate.entry)
    }

    public func cancelChainChoice() {
        self.chainChoices = nil
    }

    private func appendIfNew(_ entry: TickerEntry) {
        guard !self.settings.entries.contains(where: { $0.sourceIdentifier == entry.sourceIdentifier }) else {
            self.addError = "That token is already in the ticker."
            return
        }
        guard self.canAddMore else {
            self.addError = "The ticker is full. Remove a token first."
            return
        }
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
