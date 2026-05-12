import XCTest
@testable import KeychainKit

/// Verifies that `SecureItemStore` routes user-presence prompts through the
/// injected `BiometricAuthenticating`, so the production `LAContext` path is
/// never engaged during automated test runs.
final class SecureItemStoreAuthenticationTests: XCTestCase {
    /// When the injected authenticator denies, `read(_:prompt:)` must
    /// propagate the typed error without ever calling `SecItemCopyMatching`.
    func test_read_withDenyingAuthenticator_throwsBeforeKeychainCall() async {
        let service = "dev.zods.zodsol.test.\(UUID().uuidString)"
        let store = SecureItemStore(
            service: service,
            authenticator: StaticBiometricAuthenticator(.deny(.userCanceled)))
        let item = SecureItem(service: service, account: "any")

        do {
            _ = try await store.read(item, prompt: "Authorize")
            XCTFail("expected userCanceled")
        } catch let error as KeychainError {
            XCTAssertEqual(error, .userCanceled)
        } catch {
            XCTFail("expected KeychainError, got \(error)")
        }
    }

    /// When the injected authenticator allows but the item is missing, the
    /// store reaches the `SecItemCopyMatching` call and surfaces
    /// `itemNotFound` — proving the authentication seam fires first and then
    /// the keychain lookup runs.
    func test_read_withAllowingAuthenticator_andMissingItem_throwsItemNotFound() async {
        let service = "dev.zods.zodsol.test.\(UUID().uuidString)"
        let store = SecureItemStore(
            service: service,
            authenticator: StaticBiometricAuthenticator(.allow))
        let item = SecureItem(service: service, account: "ghost")

        do {
            _ = try await store.read(item, prompt: "Authorize")
            XCTFail("expected itemNotFound")
        } catch let error as KeychainError {
            XCTAssertEqual(error, .itemNotFound)
        } catch {
            XCTFail("expected KeychainError, got \(error)")
        }
    }

    /// Read calls with no prompt skip authentication entirely - confirming
    /// the existing "silent read for non-biometric items" contract.
    func test_read_withoutPrompt_doesNotInvokeAuthenticator() async {
        let service = "dev.zods.zodsol.test.\(UUID().uuidString)"
        // A denying authenticator must NOT be invoked when prompt is nil.
        let store = SecureItemStore(
            service: service,
            authenticator: StaticBiometricAuthenticator(.deny(.userCanceled)))
        let item = SecureItem(service: service, account: "ghost")

        do {
            _ = try await store.read(item)
            XCTFail("expected itemNotFound")
        } catch let error as KeychainError {
            // itemNotFound means we reached SecItemCopyMatching without
            // consulting the authenticator (which would have thrown
            // userCanceled).
            XCTAssertEqual(error, .itemNotFound)
        } catch {
            XCTFail("expected KeychainError, got \(error)")
        }
    }
}
