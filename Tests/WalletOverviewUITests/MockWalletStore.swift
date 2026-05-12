import Foundation
import KeychainKit
import SolanaKit
import WalletOverviewDomain

/// Constructs a real `WalletStore` for unit tests.
///
/// `WalletStore` is a concrete actor with no protocol surface, and its keychain-backed
/// `SecureItemStore` is also concrete. So instead of mocking, we instantiate a real
/// `WalletStore` with a `SecureItemStore` scoped to a unique service id and a fresh
/// `UserDefaults` suite — the keychain has no entries under that service, so
/// `wallets()` returns `[]` and `selectedWalletId()` returns `nil`.
enum TestWalletStoreFactory {
    static func makeEmpty() -> WalletStore {
        let suiteName = "zodsol.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let secureStore = SecureItemStore(service: "zodsol.tests.\(UUID().uuidString)")
        return WalletStore(secureStore: secureStore, defaults: defaults)
    }

    static func makeWithWallet() async throws -> (WalletStore, WalletIdentity) {
        let store = self.makeEmpty()
        let identity = try await store.add(
            address: WalletAddress(base58: "11111111111111111111111111111111"),
            label: "Main")
        await store.setSelectedWallet(identity.id)
        return (store, identity)
    }
}
