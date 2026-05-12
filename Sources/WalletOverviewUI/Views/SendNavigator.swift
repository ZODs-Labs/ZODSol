import SwiftUI

/// Host for the send flow. Owns one `SendViewModel` whose state drives which
/// sub-screen is rendered (input -> confirm -> status).
struct SendNavigator: View {
    @Bindable var viewModel: SendViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch self.viewModel.state {
            case .input:
                SendInputView(viewModel: self.viewModel)
                    .transition(.identity)
            case .quoting:
                SendQuotingView()
                    .transition(.opacity)
            case let .readyToConfirm(quote):
                SendConfirmView(viewModel: self.viewModel, quote: quote)
                    .transition(.opacity)
            case .signing, .broadcasting, .confirming, .confirmed, .expired, .failed:
                SendStatusView(viewModel: self.viewModel)
                    .transition(.opacity)
            }
        }
        .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.18), value: self.viewModel.state)
    }
}
