import WalletOverviewUI

actor MockAPIKeyStore: APIKeyStore {
    private var storedKey: String?

    init(key: String? = nil) {
        self.storedKey = key
    }

    func currentKey() async throws -> String? {
        self.storedKey
    }

    func save(_ key: String) async throws {
        self.storedKey = key
    }

    func clear() async throws {
        self.storedKey = nil
    }
}
