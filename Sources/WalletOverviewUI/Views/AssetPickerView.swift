import SwiftUI

struct AssetPickerView: View {
    let intent: AssetPickerIntent
    @Bindable var viewModel: WalletOverviewViewModel

    var body: some View {
        Text("Asset picker")
    }
}
