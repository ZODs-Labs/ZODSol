import SwiftUI
import WalletOverviewDomain

/// General app settings. Currently hosts "Launch at login". Matches the
/// inline-navigation idiom of `SecuritySettingsView` - a route the panel
/// mounts, no sheet or popover.
struct GeneralSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var parent: WalletOverviewViewModel
    @Bindable var launchAtLogin: LaunchAtLoginViewModel

    var body: some View {
        VStack(spacing: 0) {
            self.navBar
            Divider().opacity(0.4)
            MinimalScrollView {
                VStack(spacing: 18) {
                    self.startupSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
        // Reflect a change the user may have made in System Settings while the
        // panel was closed, so the toggle is never stale on entry.
        .onAppear { self.launchAtLogin.refresh() }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack(spacing: 6) {
            Button(action: self.back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Manage")
                }
                .font(.callout)
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to manage")

            Spacer()
            Text("General")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Startup

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.sectionHeader("Startup")
            VStack(spacing: 0) {
                Toggle(isOn: self.launchAtLoginBinding) {
                    Text("Launch ZODSol at login")
                        .font(.callout)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                if self.launchAtLogin.needsApproval {
                    Divider().padding(.leading, 16).opacity(0.35)
                    self.approvalRow
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(Self.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = self.launchAtLogin.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var approvalRow: some View {
        Button(action: self.launchAtLogin.openLoginItemsSettings) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Turned off in Login Items")
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Text("Open System Settings to turn it back on")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens System Settings, General, Login Items")
    }

    // MARK: - Bindings and actions

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { self.launchAtLogin.isEnabled },
            set: { newValue in
                Task { await self.launchAtLogin.setEnabled(newValue) }
            })
    }

    private func back() {
        withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            self.parent.route = .manage
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private static let helpText: String =
        "ZODSol opens automatically when you log in and stays quietly in the " +
        "menu bar. Turn this off to start it yourself. You can also manage it " +
        "in System Settings > General > Login Items."
}
