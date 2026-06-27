import Foundation

/// UserDefaults-backed persistence for the menu-bar ticker configuration.
/// Capped at `maxEntries` selected tokens so the menu bar never overflows and
/// the blob stays small. Stores only the user's token selection and display
/// preferences, never wallet data or key material.
public actor TickerSettingsStore {
    public static let defaultsKey = "dev.zods.zodsol.tickerSettings"
    public static let maxEntries = 6

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = TickerSettingsStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Returns the persisted settings, or the seeded curated set (widget
    /// disabled, SOL/BTC/ETH pre-loaded) when nothing has been saved yet.
    public func load() -> TickerSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(TickerSettings.self, from: data)
        else {
            return .seeded
        }
        return decoded
    }

    public func save(_ settings: TickerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        self.defaults.set(data, forKey: self.key)
    }

    /// Appends an entry. Refuses a duplicate `sourceIdentifier` and refuses once
    /// the cap is reached. Returns whether the entry was added.
    @discardableResult
    public func addEntry(_ entry: TickerEntry) -> Bool {
        var settings = self.load()
        guard settings.entries.count < Self.maxEntries else { return false }
        guard !settings.entries.contains(where: { $0.sourceIdentifier == entry.sourceIdentifier }) else {
            return false
        }
        settings.entries.append(entry)
        self.save(settings)
        return true
    }

    public func removeEntry(id: UUID) {
        var settings = self.load()
        settings.entries.removeAll { $0.id == id }
        self.save(settings)
    }

    public func setEntryEnabled(id: UUID, _ isEnabled: Bool) {
        var settings = self.load()
        guard let index = settings.entries.firstIndex(where: { $0.id == id }) else { return }
        settings.entries[index].isEnabled = isEnabled
        self.save(settings)
    }

    public func setWidgetEnabled(_ isEnabled: Bool) {
        var settings = self.load()
        settings.isWidgetEnabled = isEnabled
        self.save(settings)
    }

    public func setDisplayMode(_ mode: TickerDisplayMode) {
        var settings = self.load()
        settings.displayMode = mode
        self.save(settings)
    }
}
