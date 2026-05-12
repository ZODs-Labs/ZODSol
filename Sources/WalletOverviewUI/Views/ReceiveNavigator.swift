import SwiftUI

struct ReceiveNavigator: View {
    @Bindable var viewModel: ReceiveViewModel
    @Bindable var parent: WalletOverviewViewModel

    var body: some View {
        ReceiveView(viewModel: self.viewModel, parent: self.parent)
            .task { self.viewModel.onAppear() }
    }
}
