import Foundation
import SolanaKit

/// One recipient the user has previously sent to from a given wallet. The
/// store keeps `lastSentAt` so the UI can sort the recents list newest-first.
public struct RecentRecipient: Codable, Sendable, Equatable, Identifiable {
    public let walletId: UUID
    public let address: WalletAddress
    public var lastSentAt: Date

    public var id: String {
        "\(self.walletId.uuidString)/\(self.address.base58)"
    }

    public init(walletId: UUID, address: WalletAddress, lastSentAt: Date) {
        self.walletId = walletId
        self.address = address
        self.lastSentAt = lastSentAt
    }
}

/// Persistence for "addresses this wallet has previously sent to" - capped
/// at `maxEntriesPerWallet` per wallet and `maxEntriesTotal` globally so the
/// UserDefaults blob never grows unbounded. Never stores any key material.
public actor RecentRecipientsStore {
    public static let defaultsKey = "dev.zods.zodsol.recentRecipients"
    public static let maxEntriesPerWallet = 10
    public static let maxEntriesTotal = 50

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = RecentRecipientsStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public func record(_ recipient: WalletAddress, walletId: UUID, at time: Date = Date()) async {
        var current = self.readAll()
        current.removeAll { $0.walletId == walletId && $0.address.base58 == recipient.base58 }
        let entry = RecentRecipient(walletId: walletId, address: recipient, lastSentAt: time)
        current.insert(entry, at: 0)
        current = self.trimPerWallet(current)
        current = self.trimGlobal(current)
        self.writeAll(current)
    }

    public func list(walletId: UUID) async -> [RecentRecipient] {
        self.readAll()
            .filter { $0.walletId == walletId }
            .sorted { $0.lastSentAt > $1.lastSentAt }
    }

    public func clear(walletId: UUID) async {
        let remaining = self.readAll().filter { $0.walletId != walletId }
        self.writeAll(remaining)
    }

    public func clearAll() async {
        self.defaults.removeObject(forKey: self.key)
    }

    // MARK: - Trimming

    private func trimPerWallet(_ entries: [RecentRecipient]) -> [RecentRecipient] {
        let grouped = Dictionary(grouping: entries, by: \.walletId)
        var keep: [RecentRecipient] = []
        for (_, bucket) in grouped {
            let newestFirst = bucket.sorted { $0.lastSentAt > $1.lastSentAt }
            keep.append(contentsOf: newestFirst.prefix(Self.maxEntriesPerWallet))
        }
        return keep
    }

    private func trimGlobal(_ entries: [RecentRecipient]) -> [RecentRecipient] {
        guard entries.count > Self.maxEntriesTotal else { return entries }
        let newestFirst = entries.sorted { $0.lastSentAt > $1.lastSentAt }
        return Array(newestFirst.prefix(Self.maxEntriesTotal))
    }

    // MARK: - Storage

    private func readAll() -> [RecentRecipient] {
        guard let data = self.defaults.data(forKey: self.key) else { return [] }
        return (try? JSONDecoder().decode([RecentRecipient].self, from: data)) ?? []
    }

    private func writeAll(_ entries: [RecentRecipient]) {
        if entries.isEmpty {
            self.defaults.removeObject(forKey: self.key)
            return
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        self.defaults.set(data, forKey: self.key)
    }
}
