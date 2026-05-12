import SwiftUI

struct ReceiveNavigator: View {
    @Bindable var viewModel: ReceiveViewModel

    var body: some View {
        ReceiveView(viewModel: viewModel)
    }
}
