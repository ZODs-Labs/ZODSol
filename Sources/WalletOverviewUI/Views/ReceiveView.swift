import AppKit
import SwiftUI

struct ReceiveView: View {
    @Bindable var viewModel: ReceiveViewModel
    @Bindable var parent: WalletOverviewViewModel
    @State private var isAmountRequestExpanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header

            self.qrCard

            self.addressCard

            self.amountRequestDisclosure

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Done") {
                    self.parent.route = .overview
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .task(id: self.parent.pendingReceiveAsset?.id) {
            if let asset = self.parent.pendingReceiveAsset {
                self.viewModel.setAmountRequest(asset: asset)
                self.isAmountRequestExpanded = true
                self.parent.pendingReceiveAsset = nil
            }
        }
        .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.22), value: self.isAmountRequestExpanded)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(self.walletLabel)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            ClusterBadge(network: self.viewModel.cluster)
        }
    }

    private var qrCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.08))
            if let image = self.viewModel.qrImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            } else {
                ProgressView()
            }
        }
        .frame(width: 256, height: 256)
        .frame(maxWidth: .infinity)
        .onDrag {
            let provider = NSItemProvider()
            if let image = self.viewModel.qrImage {
                provider.registerObject(image, visibility: .all)
            }
            return provider
        } preview: {
            if let image = self.viewModel.qrImage {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 64, height: 64)
            } else {
                Image(systemName: "qrcode")
                    .frame(width: 64, height: 64)
            }
        }
        .accessibilityLabel("QR code for \(self.viewModel.qrPayload)")
    }

    private var addressCard: some View {
        HStack(spacing: 8) {
            Text(self.viewModel.qrPayload)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            CopyButton(text: self.viewModel.qrPayload) {
                self.viewModel.copyAddress()
            }
            ShareButton(items: [self.viewModel.qrPayload])
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        .overlay {
            if self.viewModel.copyToastVisible {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.85))
                    .overlay {
                        Text("Copied")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.white)
                    }
                    .transition(.opacity)
            }
        }
        .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.2), value: self.viewModel.copyToastVisible)
    }

    private var amountRequestDisclosure: some View {
        DisclosureGroup(isExpanded: self.$isAmountRequestExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    let intent = AssetPickerIntent(
                        walletId: self.viewModel.intent.walletId,
                        from: self.viewModel.intent.address,
                        mode: .receive(self.viewModel.intent))
                    self.parent.route = .assetPicker(intent)
                } label: {
                    HStack {
                        if case let .requesting(asset, _) = self.viewModel.amountRequest {
                            Text(asset.symbol)
                        } else {
                            Text("Select asset")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)

                if case let .requesting(_, currentText) = self.viewModel.amountRequest {
                    TextField("Amount", text: Binding(
                        get: { currentText },
                        set: { self.viewModel.updateAmountText($0) }))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button("Clear amount") {
                        self.viewModel.clearAmountRequest()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Request specific amount")
                .font(.subheadline.weight(.medium))
        }
    }

    // MARK: - Helpers

    private var walletLabel: String {
        if let identity = self.parent.wallets.first(where: { $0.id == self.viewModel.intent.walletId }) {
            return identity.label
        }
        return self.viewModel.intent.address.shortened()
    }
}
