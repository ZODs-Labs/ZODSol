import WalletOverviewUI

actor MockAPIKeyStore: APIKeyStore {
    private var storedKey: String?

    init(key: String? = nil) { self.storedKey = key }

    func currentKey() async throws -> String? { storedKey }
    func save(_ key: String) async throws { storedKey = key }
    func clear() async throws { storedKey = nil }
}
