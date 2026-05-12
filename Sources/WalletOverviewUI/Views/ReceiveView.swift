import AppKit
import SolanaKit
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
        self.qrCardBody
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

    @ViewBuilder
    private var qrCardBody: some View {
        let content = ZStack {
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

        if #available(macOS 26.0, *) {
            content.glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.background.opacity(0.6)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }

    private var addressCard: some View {
        HStack(spacing: 8) {
            Text(self.viewModel.qrPayload)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            CopyButton(text: self.viewModel.qrPayload) {
                self.viewModel.copyAddress()
            }
            ShareButton(items: [self.viewModel.qrPayload])
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background.opacity(0.6)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .overlay {
            if self.viewModel.copyToastVisible {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
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
                    .foregroundStyle(.secondary)
                    .controlSize(.small)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Request specific amount")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
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

#if DEBUG

/// Static visual approximation of the receive screen used for previews. The
/// real `ReceiveView` requires `ReceiveViewModel` and `WalletOverviewViewModel`,
/// both of which need heavy scaffolding (Keychain, services). This mirror
/// composes the same subviews with literal values so Xcode previews stay
/// responsive without spinning up production stores.
private struct ReceivePreviewMirror: View {
    let address: String
    let cluster: SolanaNetwork

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Main wallet")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                ClusterBadge(network: self.cluster)
            }

            self.qr

            self.addressCard

            DisclosureGroup {
                Text("Request specific amount controls go here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } label: {
                Text("Request specific amount")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done") {}
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var qr: some View {
        let content = ZStack {
            Image(systemName: "qrcode")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(40)
                .foregroundStyle(.primary)
        }
        if #available(macOS 26.0, *) {
            content
                .frame(width: 256, height: 256)
                .frame(maxWidth: .infinity)
                .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            content
                .frame(width: 256, height: 256)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.background.opacity(0.6)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }

    private var addressCard: some View {
        HStack(spacing: 8) {
            Text(self.address)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            CopyButton(text: self.address)
            ShareButton(items: [self.address])
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background.opacity(0.6)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

#Preview("Receive - devnet") {
    ReceivePreviewMirror(
        address: "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq",
        cluster: .mainnet)
        .frame(width: 380, height: 560)
}

#Preview("Receive - mainnet") {
    ReceivePreviewMirror(
        address: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
        cluster: .mainnet)
        .frame(width: 380, height: 560)
}

#endif
