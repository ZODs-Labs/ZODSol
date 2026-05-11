public struct BiometricGate: Sendable {
    public var requiresUserPresence: Bool
    public var localizedPrompt: String

    public static let none = BiometricGate(requiresUserPresence: false, localizedPrompt: "")

    public static func userPresence(prompt: String) -> Self {
        .init(requiresUserPresence: true, localizedPrompt: prompt)
    }

    public init(requiresUserPresence: Bool, localizedPrompt: String) {
        self.requiresUserPresence = requiresUserPresence
        self.localizedPrompt = localizedPrompt
    }
}
