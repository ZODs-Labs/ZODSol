import SwiftUI
import WalletOverviewDomain

/// Auto-lock and "lock now" controls. Matches the inline-navigation idiom of
/// `ManageWalletsView` - no sheet, no popover, just a route the panel mounts.
struct SecuritySettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: WalletOverviewViewModel

    var body: some View {
        VStack(spacing: 0) {
            self.navBar
            Divider().opacity(0.4)
            MinimalScrollView {
                VStack(spacing: 18) {
                    self.lockWhenSection
                    self.systemEventsSection
                    self.lockNowButton
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
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

            Text("Security")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Sections

    private var lockWhenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.sectionHeader("Lock wallet")
            VStack(spacing: 0) {
                ForEach(Array(AutoLockOption.allCases.enumerated()), id: \.element) { index, option in
                    self.row(for: option)
                    if index != AutoLockOption.allCases.count - 1 {
                        Divider().padding(.leading, 16).opacity(0.35)
                    }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(Self.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(for option: AutoLockOption) -> some View {
        let isSelected = option.matches(self.viewModel.sessionPolicy.trigger)
        return Button(
            action: { self.selectOption(option) },
            label: { self.rowLabel(for: option, isSelected: isSelected) })
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func rowLabel(for option: AutoLockOption, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Text(option.title)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var systemEventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.sectionHeader("Also lock when")
            VStack(spacing: 0) {
                Toggle(isOn: self.systemSleepBinding) {
                    Text("Mac goes to sleep")
                        .font(.callout)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider().padding(.leading, 16).opacity(0.35)
                Toggle(isOn: self.screenLockBinding) {
                    Text("Screen locks")
                        .font(.callout)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var lockNowButton: some View {
        Button(
            action: { self.viewModel.lockNow() },
            label: { self.lockNowLabel })
            .buttonStyle(.plain)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var lockNowLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
            Text("Lock now")
            Spacer()
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Bindings

    private var systemSleepBinding: Binding<Bool> {
        Binding(
            get: { self.viewModel.sessionPolicy.lockOnSystemSleep },
            set: { newValue in
                var p = self.viewModel.sessionPolicy
                p.lockOnSystemSleep = newValue
                Task { await self.viewModel.updateSessionPolicy(p) }
            })
    }

    private var screenLockBinding: Binding<Bool> {
        Binding(
            get: { self.viewModel.sessionPolicy.lockOnScreenLock },
            set: { newValue in
                var p = self.viewModel.sessionPolicy
                p.lockOnScreenLock = newValue
                Task { await self.viewModel.updateSessionPolicy(p) }
            })
    }

    // MARK: - Actions

    private func selectOption(_ option: AutoLockOption) {
        var p = self.viewModel.sessionPolicy
        p.trigger = option.trigger
        Task { await self.viewModel.updateSessionPolicy(p) }
    }

    private func back() {
        withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            self.viewModel.route = .manage
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    private static let helpText: String =
        "Touch ID is required for the first send after the wallet locks. " +
        "Subsequent sends are signed without re-prompting until the lock " +
        "condition fires."
}

/// User-visible auto-lock options. Maps 1:1 onto `WalletSessionLockTrigger`.
enum AutoLockOption: Hashable, CaseIterable {
    case immediately
    case after5min
    case after15min
    case after1hour
    case untilPanelClose
    case untilAppQuit

    var title: String {
        switch self {
        case .immediately: "Immediately after each send"
        case .after5min: "After 5 minutes of inactivity"
        case .after15min: "After 15 minutes of inactivity"
        case .after1hour: "After 1 hour of inactivity"
        case .untilPanelClose: "When the wallet panel closes"
        case .untilAppQuit: "When ZODSol quits"
        }
    }

    var trigger: WalletSessionLockTrigger {
        switch self {
        case .immediately: .immediately
        case .after5min: .afterIdle(minutes: 5)
        case .after15min: .afterIdle(minutes: 15)
        case .after1hour: .afterIdle(minutes: 60)
        case .untilPanelClose: .untilPanelClose
        case .untilAppQuit: .untilAppQuit
        }
    }

    func matches(_ trigger: WalletSessionLockTrigger) -> Bool {
        switch (self, trigger) {
        case (.immediately, .immediately): true
        case let (.after5min, .afterIdle(minutes)): minutes == 5
        case let (.after15min, .afterIdle(minutes)): minutes == 15
        case let (.after1hour, .afterIdle(minutes)): minutes == 60
        case (.untilPanelClose, .untilPanelClose): true
        case (.untilAppQuit, .untilAppQuit): true
        default: false
        }
    }
}
