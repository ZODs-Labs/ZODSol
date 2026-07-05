import SwiftUI
import WalletOverviewDomain

/// Menu Bar Widget settings: master toggle, what each token shows and which
/// curated blue-chips appear. Matches the inline-navigation idiom of
/// `SecuritySettingsView` - a route the panel mounts, no sheet or popover.
struct TickerSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var parent: WalletOverviewViewModel
    @Bindable var ticker: TickerSettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            self.navBar
            Divider().opacity(0.4)
            MinimalScrollView {
                VStack(spacing: 18) {
                    self.enableSection
                    self.displaySection
                    self.tokensSection
                    if self.ticker.canResolve {
                        TickerCustomTokensSection(ticker: self.ticker)
                    }
                    Text(Self.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
        .task { await self.ticker.load() }
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
            Text("Menu Bar Widget")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Sections

    private var enableSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: self.enabledBinding) {
                Text("Show prices in the menu bar")
                    .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.sectionHeader("Each token shows")
            VStack(spacing: 0) {
                let modes = TickerDisplayMode.allCases
                ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                    self.checkRow(
                        title: Self.title(for: mode),
                        isSelected: self.ticker.displayMode == mode,
                        action: { self.ticker.setDisplayMode(mode) })
                    if index != modes.count - 1 {
                        Divider().padding(.leading, 16).opacity(0.35)
                    }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var tokensSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.sectionHeader("Tokens")
            VStack(spacing: 0) {
                let chips = self.ticker.availableBlueChips
                ForEach(Array(chips.enumerated()), id: \.element.symbol) { index, chip in
                    self.tokenRow(chip)
                    if index != chips.count - 1 {
                        Divider().padding(.leading, 16).opacity(0.35)
                    }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func tokenRow(_ chip: TickerCatalog.BlueChip) -> some View {
        let isAdded = self.ticker.isAdded(chip)
        let isDisabled = !isAdded && !self.ticker.canAddMore
        return Button(
            action: { self.ticker.toggle(chip) },
            label: {
                HStack(spacing: 10) {
                    Text(chip.symbol)
                        .font(.callout.weight(.medium))
                    Text(chip.displayName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isAdded {
                        Image(systemName: "checkmark")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.4 : 1)
            .accessibilityAddTraits(isAdded ? .isSelected : [])
    }

    private func checkRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(
            action: action,
            label: {
                HStack(spacing: 10) {
                    Text(title)
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
            })
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: - Bindings and actions

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { self.ticker.isWidgetEnabled },
            set: { self.ticker.setWidgetEnabled($0) })
    }

    private func back() {
        withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            self.parent.route = .manage
        }
    }

    private static func title(for mode: TickerDisplayMode) -> String {
        switch mode {
        case .priceOnly: "Price only"
        case .symbolAndPrice: "Symbol and price"
        case .symbolPriceAndChange: "Symbol, price and change"
        }
    }

    private static let helpText: String =
        "Prices refresh every 10 seconds while the panel is open and every 30 " +
        "seconds otherwise. Keep the selection small so the menu bar stays " +
        "readable on notched displays."
}
