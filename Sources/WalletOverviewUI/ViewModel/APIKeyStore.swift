public protocol APIKeyStore: Sendable {
    func currentKey() async throws -> String?
    func save(_ key: String) async throws
    func clear() async throws
}
