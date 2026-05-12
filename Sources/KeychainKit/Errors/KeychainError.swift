import Foundation
import Security

public enum KeychainError: Error, Sendable, Equatable {
    case unhandledStatus(OSStatus)
    case itemNotFound
    case duplicateItem
    case interactionRequired
    case biometricFailed
    case userCanceled
    case biometryNotAvailable
    case biometryLockout
    case biometryNotEnrolled
    case dataDecodingFailed
    /// The binary asked Keychain for an entitlement-gated operation that its
    /// current signature does not grant. Most common when local/Homebrew builds
    /// opt into sandbox or Data Protection Keychain behavior.
    case missingEntitlement(OSStatus)
}

extension KeychainError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unhandledStatus(status):
            "Keychain failed (\(Self.statusName(status))). \(Self.statusMessage(status))"
        case .itemNotFound:
            "Item not found in Keychain."
        case .duplicateItem:
            "An item with this account already exists in Keychain."
        case .interactionRequired:
            "Keychain needs user interaction but it is not allowed in this context."
        case .biometricFailed:
            "Authentication did not succeed. Try again."
        case .userCanceled:
            "You cancelled the authentication prompt."
        case .biometryNotAvailable:
            "Local authentication is not available on this Mac."
        case .biometryLockout:
            "Authentication is temporarily locked. Use your Mac password, then try again."
        case .biometryNotEnrolled:
            "No Touch ID fingerprints are enrolled in System Settings."
        case .dataDecodingFailed:
            "Stored Keychain value could not be decoded."
        case let .missingEntitlement(status):
            """
            This build asked Keychain for an entitlement-gated operation (\(Self.statusName(status))). \
            Rebuild with the standard macOS Keychain path for Homebrew, or provide matching signing entitlements.
            """
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .biometryLockout:
            "Use your Mac password in the system authentication prompt, then retry."
        case .biometryNotEnrolled:
            "Open System Settings → Touch ID & Password to enroll a fingerprint."
        case .biometryNotAvailable:
            "This action needs local authentication. Set a Mac login password, or change the access policy."
        case .missingEntitlement:
            "Use the default Homebrew packaging path, or enable sandbox only with a matching signing identity."
        default:
            nil
        }
    }

    private static func statusName(_ status: OSStatus) -> String {
        // SecCopyErrorMessageString is the Apple-recommended translation of an
        // `OSStatus` returned by Security framework calls into a localized
        // string. Combine with the raw code so logs stay grep-able.
        if let cf = SecCopyErrorMessageString(status, nil) {
            return "OSStatus \(status): \(cf as String)"
        }
        return "OSStatus \(status)"
    }

    private static func statusMessage(_ status: OSStatus) -> String {
        switch status {
        case -34018:
            """
            errSecMissingEntitlement - the binary requested a Keychain mode that needs entitlements not present \
            in the current code signature.
            """
        case -50: "errSecParam — invalid parameters passed to the Keychain API."
        case -25291: "errSecNotAvailable — Keychain is not available right now."
        case -25299: "errSecDuplicateItem — an item with this account already exists."
        case -25300: "errSecItemNotFound."
        case -25308: "errSecInteractionNotAllowed — the process cannot interact with the user."
        default: "Unmapped Keychain status."
        }
    }
}
