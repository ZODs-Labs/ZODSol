import Security

extension SecureItemStore {
    static func mapStatus(_ status: OSStatus) -> KeychainError {
        switch status {
        case errSecItemNotFound:          return .itemNotFound
        case errSecDuplicateItem:         return .duplicateItem
        case errSecAuthFailed:            return .biometricFailed
        case OSStatus(-128):              return .userCanceled
        case errSecInteractionNotAllowed: return .interactionRequired
        case OSStatus(-6):                return .biometryNotAvailable
        case OSStatus(-8):                return .biometryLockout
        case OSStatus(-7):                return .biometryNotEnrolled
        case OSStatus(-34018):            return .missingEntitlement(status)
        default:                          return .unhandledStatus(status)
        }
    }
}
