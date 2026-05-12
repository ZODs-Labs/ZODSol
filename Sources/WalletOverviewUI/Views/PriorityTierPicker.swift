import SwiftUI
import WalletOverviewDomain

struct PriorityTierPicker: View {
    @Binding var selection: PriorityTier

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Priority")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Priority", selection: self.$selection) {
                Label("Standard", systemImage: "tortoise.fill").tag(PriorityTier.standard)
                Label("Fast", systemImage: "hare.fill").tag(PriorityTier.fast)
                Label("Turbo", systemImage: "bolt.fill").tag(PriorityTier.turbo)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
