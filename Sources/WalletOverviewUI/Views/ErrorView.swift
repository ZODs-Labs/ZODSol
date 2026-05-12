import SwiftUI
import WalletOverviewDomain

struct ErrorView: View {
    let error: WalletOverviewError
    let viewModel: WalletOverviewViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text(self.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(self.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                Button("Retry") {
                    Task { await self.viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)

                if self.canChangeAPIKey {
                    Button("Change API key") {
                        Task { await self.viewModel.clearAPIKey() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }

    private var title: String {
        switch self.error {
        case .needsSetup: "Setup required"
        case .networkUnavailable: "No connection"
        case .rateLimited: "Rate limited"
        case .unauthorized: "Unauthorized"
        case .providerUnavailable: "Provider unavailable"
        case .malformedResponse: "Unexpected response"
        case .biometricInvalidated: "Authentication required"
        case .canceled: "Canceled"
        case .unknown: "Something went wrong"
        }
    }

    private var detail: String {
        switch self.error {
        case .needsSetup:
            "Add a Helius API key to load your portfolio."
        case .networkUnavailable:
            "Check your internet connection and try again."
        case .rateLimited:
            "Too many requests. Try again shortly."
        case .unauthorized:
            "Your API key was rejected. Verify the key and retry."
        case let .providerUnavailable(message):
            message
        case let .malformedResponse(message):
            message
        case .biometricInvalidated:
            "Re-authenticate to access your secured keys."
        case .canceled:
            "The previous request was canceled."
        case let .unknown(message):
            message
        }
    }

    private var canChangeAPIKey: Bool {
        switch self.error {
        case .needsSetup, .unauthorized:
            true
        case .networkUnavailable,
             .rateLimited,
             .providerUnavailable,
             .malformedResponse,
             .biometricInvalidated,
             .canceled,
             .unknown:
            false
        }
    }
}
