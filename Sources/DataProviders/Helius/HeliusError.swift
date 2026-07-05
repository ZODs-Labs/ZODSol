import Foundation

public enum HeliusError: Error, Sendable, Equatable {
    case missingAPIKey
    case quotaExceeded
}
