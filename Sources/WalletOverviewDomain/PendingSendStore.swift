import Foundation
import SolanaKit

/// One in-flight transaction recorded so the orchestrator can resync on app
/// reopen if the polling task was cancelled mid-confirmation.
public struct PendingSend: Codable, Sendable, Equatable {
    public let walletId: UUID
    public let signatureBase58: String
    public let lastValidBlockHeight: UInt64
    public let network: SolanaNetwork
    public let createdAt: Date

    public init(
        walletId: UUID,
        signatureBase58: String,
        lastValidBlockHeight: UInt64,
        network: SolanaNetwork,
        createdAt: Date)
    {
        self.walletId = walletId
        self.signatureBase58 = signatureBase58
        self.lastValidBlockHeight = lastValidBlockHeight
        self.network = network
        self.createdAt = createdAt
    }
}

/// Persistence for "this transaction was broadcast but we did not see it
/// confirmed before the panel closed" — at most `maxEntries` items, never
/// signed transaction bytes or key material.
public actor PendingSendStore {
    public static let defaultsKey = "dev.zods.zodsol.pendingSends"
    public static let maxEntries = 5

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = PendingSendStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public func add(_ pending: PendingSend) {
        var current = self.readAll()
        // Replace any existing entry with the same signature so add is idempotent.
        current.removeAll { $0.signatureBase58 == pending.signatureBase58 }
        current.append(pending)
        // Evict oldest when over the cap.
        if current.count > Self.maxEntries {
            current.sort { $0.createdAt < $1.createdAt }
            current.removeFirst(current.count - Self.maxEntries)
        }
        self.writeAll(current)
    }

    public func remove(signatureBase58: String) {
        var current = self.readAll()
        current.removeAll { $0.signatureBase58 == signatureBase58 }
        self.writeAll(current)
    }

    public func list(for walletId: UUID) -> [PendingSend] {
        self.readAll().filter { $0.walletId == walletId }
    }

    public func all() -> [PendingSend] {
        self.readAll()
    }

    /// Drop entries whose `createdAt` is older than `maxAge`. Run on every
    /// resync so old signatures don't bloat persistence.
    public func prune(olderThan maxAge: TimeInterval, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-maxAge)
        let current = self.readAll().filter { $0.createdAt >= cutoff }
        self.writeAll(current)
    }

    // MARK: - Storage

    private func readAll() -> [PendingSend] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingSend].self, from: data)) ?? []
    }

    private func writeAll(_ entries: [PendingSend]) {
        if entries.isEmpty {
            self.defaults.removeObject(forKey: self.key)
            return
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        self.defaults.set(data, forKey: self.key)
    }
}
