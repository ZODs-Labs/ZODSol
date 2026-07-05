import Foundation

/// Read-only credential lookup backed by a process environment variable.
///
/// Treats `unset`, empty (`""`) and whitespace-only values as absent so a
/// shell `export ZODSOL_HELIUS_API_KEY=""` behaves the same as not exporting
/// at all. Designed to be composed in front of a Keychain-backed store so
/// developer rebuilds (which invalidate the legacy Keychain ACL on every
/// new cdhash) can bypass the Keychain entirely without changing the
/// production code path.
public struct EnvironmentKeySource: Sendable {
    private let variableName: String
    private let environment: @Sendable () -> [String: String]

    public init(
        variableName: String,
        environment: @Sendable @escaping () -> [String: String] = { ProcessInfo.processInfo.environment })
    {
        self.variableName = variableName
        self.environment = environment
    }

    public var name: String {
        self.variableName
    }

    /// Returns the trimmed value of the environment variable, or `nil` if
    /// the variable is unset, empty, or whitespace-only.
    public func value() -> String? {
        guard let raw = self.environment()[self.variableName] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
