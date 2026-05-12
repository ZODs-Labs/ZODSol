import XCTest
@testable import KeychainKit

final class StaticBiometricAuthenticatorTests: XCTestCase {
    func test_allow_returnsImmediately() async throws {
        let auth = StaticBiometricAuthenticator(.allow)
        try await auth.authenticate(reason: "any")
        // Reaching this point without throwing is the test.
    }

    func test_deny_throwsConfiguredError() async {
        let auth = StaticBiometricAuthenticator(.deny(.userCanceled))
        do {
            try await auth.authenticate(reason: "any")
            XCTFail("expected userCanceled")
        } catch let error as KeychainError {
            XCTAssertEqual(error, .userCanceled)
        } catch {
            XCTFail("expected KeychainError, got \(error)")
        }
    }

    func test_deny_supportsBiometricLockout() async {
        let auth = StaticBiometricAuthenticator(.deny(.biometryLockout))
        do {
            try await auth.authenticate(reason: "any")
            XCTFail("expected biometryLockout")
        } catch let error as KeychainError {
            XCTAssertEqual(error, .biometryLockout)
        } catch {
            XCTFail("expected KeychainError, got \(error)")
        }
    }
}
