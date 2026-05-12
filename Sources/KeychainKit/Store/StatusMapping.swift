import Security

extension SecureItemStore {
    static func mapStatus(_ status: OSStatus) -> KeychainError {
        switch status {
        case errSecItemNotFound: .itemNotFound
        case errSecDuplicateItem: .duplicateItem
        case errSecAuthFailed: .biometricFailed
        case OSStatus(-128): .userCanceled
        case errSecInteractionNotAllowed: .interactionRequired
        case OSStatus(-6): .biometryNotAvailable
        case OSStatus(-8): .biometryLockout
        case OSStatus(-7): .biometryNotEnrolled
        case OSStatus(-34018): .missingEntitlement(status)
        default: .unhandledStatus(status)
        }
    }
}
