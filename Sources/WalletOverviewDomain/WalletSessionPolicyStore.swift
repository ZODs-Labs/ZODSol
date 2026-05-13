import Foundation

/// UserDefaults-backed persistence for `WalletSession.Policy`. Defaults to
/// `.default` (15-minute idle, lock on system sleep + screen lock) on first
/// launch.
public actor WalletSessionPolicyStore {
    public static let defaultsKey = "dev.zods.zodsol.session.policy"

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = WalletSessionPolicyStore.defaultsKey)
    {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> WalletSession.Policy {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(WalletSession.Policy.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    public func save(_ policy: WalletSession.Policy) {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        self.defaults.set(data, forKey: self.key)
    }
}
