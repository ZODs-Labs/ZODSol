import AppKit
import SwiftUI
import OSLog
import HeliusProvider
import KeychainKit
import WalletOverviewDomain
import WalletOverviewUI
import SolanaKit
import Caching

@MainActor
final class StatusItemController: NSObject {
    private let displayModel: ZODSolDisplayModel
    private let statusItem: NSStatusItem
    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private let viewModel: WalletOverviewViewModel

    init(displayModel: ZODSolDisplayModel) {
        self.displayModel = displayModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let secureStore = SecureItemStore(service: "dev.zods.zodsol")
        let apiKeyStore = HeliusAPIKeyStore(secureStore: secureStore)
        let walletStore = WalletStore(secureStore: secureStore)
        let providerHolder = LazyProvider(apiKeyStore: apiKeyStore)
        let overviewCache: TimedCache<UUID, WalletOverview> = TimedCache(ttl: .seconds(15))
        let service = DefaultWalletOverviewService(
            provider: providerHolder,
            walletStore: walletStore,
            network: .mainnet,
            overviewCache: overviewCache
        )
        self.viewModel = WalletOverviewViewModel(
            service: service,
            walletStore: walletStore,
            apiKeyStore: apiKeyStore,
            credentialsDidChange: {
                await providerHolder.reset()
            }
        )

        super.init()
        self.statusItem.behavior = .removalAllowed
        self.statusItem.autosaveName = "dev.zods.zodsol.StatusItem"
        self.configureStatusItem()
    }

    func releaseStatusItem() {
        self.closePanel()
        NSStatusBar.system.removeStatusItem(self.statusItem)
    }

    private func configureStatusItem() {
        guard let button = self.statusItem.button else { return }
        button.title = self.displayModel.statusItemTitle
        button.font = NSFont.menuBarFont(ofSize: 0)
        button.imagePosition = .imageLeading
        button.toolTip = self.displayModel.appName
        button.setAccessibilityLabel(self.displayModel.appName)
        button.target = self
        button.action = #selector(self.togglePanel(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func makePanel() -> NSPanel {
        let panelView = WalletPanelView(viewModel: self.viewModel)
        let contentSize = NSSize(
            width: self.displayModel.panelWidth,
            height: self.displayModel.panelHeight)
        let panel = WalletPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        let glass = GlassPanelView(size: contentSize, cornerRadius: 16)
        let hosting = VibrantHostingView(rootView: panelView)
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        glass.install(content: hosting)

        panel.contentView = glass
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow
        return panel
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if let panel = self.panel, panel.isVisible {
            self.closePanel()
            return
        }
        let panel = self.panel ?? self.makePanel()
        self.panel = panel
        self.position(panel, below: sender)
        panel.orderFrontRegardless()
        self.startEventMonitoring()
        self.viewModel.panelDidAppear()
    }

    private func closePanel() {
        self.viewModel.panelDidDisappear()
        self.panel?.orderOut(nil)
        self.stopEventMonitoring()
    }

    private func position(_ panel: NSPanel, below sender: NSStatusBarButton) {
        guard let window = sender.window else { return }
        let buttonFrame = window.convertToScreen(sender.convert(sender.bounds, to: nil))
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? buttonFrame
        let horizontalInset: CGFloat = 8
        let verticalGap: CGFloat = 4
        let panelSize = panel.frame.size
        let unclampedX = buttonFrame.midX - (panelSize.width / 2)
        let minX = visibleFrame.minX + horizontalInset
        let maxX = visibleFrame.maxX - panelSize.width - horizontalInset
        let x = min(max(unclampedX, minX), maxX)
        let y = buttonFrame.minY - panelSize.height - verticalGap
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startEventMonitoring() {
        guard self.localEventMonitor == nil, self.globalEventMonitor == nil else { return }
        let statusItemWindow = self.statusItem.button?.window
        self.localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    // Walk the event window's parent chain so clicks on any
                    // child window (autocomplete popup from a SecureField, a
                    // contextual menu, an attached alert, etc.) are still
                    // recognized as inside our panel.
                    if self.isEventInOurUI(event, statusItemWindow: statusItemWindow) { return }
                    self.closePanel()
                }
                return event
            }
        self.globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    self?.closePanel()
                }
            }
    }

    private func isEventInOurUI(_ event: NSEvent, statusItemWindow: NSWindow?) -> Bool {
        guard let panel = self.panel else { return false }
        var window: NSWindow? = event.window
        while let candidate = window {
            if candidate === panel { return true }
            if let statusItemWindow, candidate === statusItemWindow { return true }
            window = candidate.parent
        }
        return false
    }

    private func stopEventMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }
}

// MARK: - WalletPanel

/// Borderless, non-activating panel that is still allowed to become the key
/// window. NSWindow returns `canBecomeKey = false` for `.borderless`, which
/// means TextField/SecureField inside the panel can never take keystrokes.
/// `.nonactivatingPanel` keeps the app from activating, so making the panel
/// key here does not steal focus from the user's active app.
@MainActor
final class WalletPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - HeliusAPIKeyStore conformance to APIKeyStore

extension HeliusAPIKeyStore: APIKeyStore {}

// MARK: - LazyProvider

fileprivate actor LazyProvider: SolanaProvider {
    private let apiKeyStore: HeliusAPIKeyStore
    private var concrete: HeliusSolanaProvider?

    init(apiKeyStore: HeliusAPIKeyStore) {
        self.apiKeyStore = apiKeyStore
    }

    private func resolved() async throws -> HeliusSolanaProvider {
        if let concrete { return concrete }
        guard let key = try await apiKeyStore.currentKey(), !key.isEmpty else {
            throw SolanaProviderError.unauthorized
        }
        let made = HeliusSolanaProvider(network: .mainnet, apiKey: key)
        self.concrete = made
        return made
    }

    func reset() {
        self.concrete = nil
    }

    func solBalance(for address: WalletAddress, network: SolanaNetwork) async throws -> Lamports {
        try await resolved().solBalance(for: address, network: network)
    }

    func tokenAccounts(for address: WalletAddress, network: SolanaNetwork) async throws -> [ParsedTokenAccount] {
        try await resolved().tokenAccounts(for: address, network: network)
    }

    func assets(for address: WalletAddress, network: SolanaNetwork, options: AssetQueryOptions) async throws -> AssetPage {
        try await resolved().assets(for: address, network: network, options: options)
    }

    func priceChange24h(for mints: [Mint]) async throws -> [Mint: Double] {
        try await resolved().priceChange24h(for: mints)
    }

    func solChange24h() async throws -> Double? {
        try await resolved().solChange24h()
    }
}
