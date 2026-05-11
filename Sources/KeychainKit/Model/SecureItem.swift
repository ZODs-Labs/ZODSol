import Foundation

public struct SecureItem: Hashable, Sendable {
    public let service: String
    public let account: String
    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}
