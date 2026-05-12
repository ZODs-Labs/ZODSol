import SwiftUI

struct ReceiveNavigator: View {
    @Bindable var viewModel: ReceiveViewModel
    @Bindable var parent: WalletOverviewViewModel

    var body: some View {
        ReceiveView(viewModel: self.viewModel, parent: self.parent)
            .task { self.viewModel.onAppear() }
    }
}

#if DEBUG

#Preview("ReceiveNavigator - placeholder") {
    Text("ReceiveNavigator preview requires WalletOverviewViewModel scaffolding. See ReceiveView previews.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding()
        .frame(width: 380, height: 200)
}

#endif
