import AppKit
import Caching
import DataProviders
import KeychainKit
import Observation
import OSLog
import SolanaKit
import SolanaRPC
import SwiftUI
import WalletOverviewDomain
import WalletOverviewUI

@MainActor
final class StatusItemController: NSObject {
    private let displayModel: ZODSolDisplayModel
    private let statusItem: NSStatusItem
    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private let viewModel: WalletOverviewViewModel
    private let session: WalletSession
    private let lockObservers: SessionLockObservers
    private let imageLoader: ImageLoader
    private var tickerController: MenuBarTickerController?

    init(displayModel: ZODSolDisplayModel) {
        self.displayModel = displayModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let secureStore = SecureItemStore(service: "dev.zods.zodsol")
        let policyStore = WalletSessionPolicyStore()
        // Hydrate the policy synchronously off the actor; the store reads
        // UserDefaults directly so calling `load()` outside of an actor hop
        // is fine - but we use the actor for symmetry and to keep all writes
        // serialized. The session is created with the persisted policy so
        // the very first send after launch already honors the user's
        // configured idle window.
        let session = WalletSession(policy: .default)
        let apiKeyStore = HeliusAPIKeyStore(secureStore: secureStore)
        let walletStore = WalletStore(secureStore: secureStore, session: session)
        let sharedHTTPSession = URLSession(configuration: .makeDefault())
        let providerHolder = LazyProvider(apiKeyStore: apiKeyStore, session: sharedHTTPSession)
        let overviewCache: TimedCache<UUID, WalletOverview> = TimedCache(ttl: .seconds(15))
        let service = DefaultWalletOverviewService(
            provider: providerHolder,
            walletStore: walletStore,
            network: .mainnet,
            overviewCache: overviewCache)
        let lazyTransport = LazyRPCTransport(
            apiKeyStore: apiKeyStore,
            network: .mainnet,
            session: sharedHTTPSession)
        let pendingSendStore = PendingSendStore()
        let sendService = DefaultSendAssetsService(
            transport: lazyTransport,
            walletLookup: walletStore,
            signer: walletStore,
            pendingStore: pendingSendStore,
            network: .mainnet)
        let recentRecipientsStore = RecentRecipientsStore()
        // One credential-free session shared by both paste resolvers; it never
        // carries the Helius key, so a paste can never leak it to a market host.
        let tickerPasteSession = URLSession(configuration: .makeCredentialFree())
        let pasteResolver = TokenPasteResolver(
            solana: JupiterTokenResolver(session: tickerPasteSession),
            evm: EVMDexResolverClient(session: tickerPasteSession))
        self.session = session
        self.viewModel = WalletOverviewViewModel(
            service: service,
            walletStore: walletStore,
            apiKeyStore: apiKeyStore,
            sendService: sendService,
            network: .mainnet,
            recentRecipientsStore: recentRecipientsStore,
            session: session,
            sessionPolicyStore: policyStore,
            tickerSettings: TickerSettingsViewModel(
                store: TickerSettingsStore(),
                pasteResolver: pasteResolver),
            credentialsDidChange: {
                await providerHolder.reset()
                await lazyTransport.reset()
            })

        self.lockObservers = SessionLockObservers(session: session)
        self.imageLoader = ImageLoader()
        super.init()
        self.statusItem.behavior = .removalAllowed
        self.statusItem.autosaveName = "dev.zods.zodsol.StatusItem"
        self.configureStatusItem()
        self.lockObservers.start()
        Task { @MainActor [policyStore, session] in
            let persisted = await policyStore.load()
            await session.setPolicy(persisted)
        }
        self.installTicker()
    }

    private func installTicker() {
        let controller = MenuBarTickerController { [weak self] model in
            self?.applyTickerRenderModel(model)
        }
        self.tickerController = controller
        self.viewModel.tickerSettings?.onChange = { [weak self] settings in
            self?.tickerController?.applySettings(settings)
        }
        controller.start()
    }

    func releaseStatusItem() {
        self.closePanel()
        self.lockObservers.stop()
        self.tickerController?.stop()
        NSStatusBar.system.removeStatusItem(self.statusItem)
    }

    private func configureStatusItem() {
        guard let button = self.statusItem.button else { return }
        if let icon = Self.loadStatusItemIcon() {
            button.image = icon
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.title = self.displayModel.statusItemTitle
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.imagePosition = .imageLeading
        }
        button.toolTip = self.displayModel.appName
        button.setAccessibilityLabel(self.displayModel.appName)
        button.target = self
        button.action = #selector(self.togglePanel(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// The status bar renders status item images at the menu bar's intrinsic
    /// height. Sizing the image to 22pt and shipping a 44px asset gives us a
    /// crisp @2x rendering on Retina without needing a multi-rep asset
    /// catalog. `isTemplate = false` preserves the logo's neon cyan; setting
    /// it to true would force the system monochrome tint and lose the brand.
    private static func loadStatusItemIcon() -> NSImage? {
        let name = "zods_menubar_icon"
        let ext = "png"
        let candidates: [Bundle] = [.module, .main]
        for bundle in candidates {
            if let url = bundle.url(forResource: name, withExtension: ext),
               let image = NSImage(contentsOf: url)
            {
                image.size = NSSize(width: 22, height: 22)
                image.isTemplate = false
                return image
            }
        }
        let fileName = "\(name).\(ext)"
        let directories: [URL] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
        ].compactMap(\.self)
        for directory in directories {
            let url = directory.appendingPathComponent(fileName)
            if let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 22, height: 22)
                image.isTemplate = false
                return image
            }
        }
        return nil
    }

    private func makePanel() -> NSPanel {
        let panelView = WalletPanelView(viewModel: self.viewModel)
            .environment(\.imageLoader, self.imageLoader)
        let initialHeight = WalletPanelMetrics.clampedHeight(screen: NSScreen.main)
        let contentSize = NSSize(width: WalletPanelMetrics.width, height: initialHeight)
        let panel = WalletPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        let glass = GlassPanelView(size: contentSize, cornerRadius: WalletPanelMetrics.cornerRadius)
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
        panel.tabbingMode = .disallowed
        // Force the shadow to be regenerated now that the contentView's layer
        // has its rounded mask in place, otherwise the first shadow pass uses
        // the rectangular bounds set during NSWindow init.
        panel.invalidateShadow()
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
        // Order front AND make key in one step. `orderFrontRegardless` alone
        // shows the panel as non-key, and the first click inside flips it to
        // key - that transition makes NSGlassEffectView / NSVisualEffectView
        // visibly change material, which the user reads as "the background
        // jumped". Native menu-bar panels (Battery, Wi-Fi, Control Center)
        // open already-key for the same reason. `.nonactivatingPanel` keeps
        // the user's frontmost app active even though we become key.
        panel.orderFrontRegardless()
        panel.makeKey()
        self.startEventMonitoring()
        self.viewModel.panelDidAppear()
        self.tickerController?.setPanelOpen(true)
    }

    private func closePanel() {
        self.viewModel.panelDidDisappear()
        self.panel?.orderOut(nil)
        self.stopEventMonitoring()
        self.tickerController?.setPanelOpen(false)
    }

    private func position(_ panel: NSPanel, below sender: NSStatusBarButton) {
        guard let window = sender.window else { return }
        let buttonFrame = window.convertToScreen(sender.convert(sender.bounds, to: nil))
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? buttonFrame
        let panelSize = panel.frame.size
        let unclampedX = buttonFrame.midX - (panelSize.width / 2)
        let minX = visibleFrame.minX + WalletPanelMetrics.horizontalEdgeInset
        let maxX = visibleFrame.maxX - panelSize.width - WalletPanelMetrics.horizontalEdgeInset
        let x = min(max(unclampedX, minX), maxX)
        let topY = buttonFrame.minY - WalletPanelMetrics.menuBarGap
        let y = max(visibleFrame.minY + WalletPanelMetrics.bottomSafetyMargin, topY - panelSize.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startEventMonitoring() {
        guard self.localEventMonitor == nil, self.globalEventMonitor == nil else { return }
        let statusItemWindow = self.statusItem.button?.window
        self.localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown])
        { [weak self] event in
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
            matching: [.leftMouseDown, .rightMouseDown])
        { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }
    }

    private func isEventInOurUI(_ event: NSEvent, statusItemWindow: NSWindow?) -> Bool {
        guard let panel = self.panel else { return false }
        // An NSAlert/sheet attached to the panel keeps the panel's flow alive
        // even though the click lands in a different NSWindow. Without this
        // we'd treat the alert's own Delete button as an outside-click and
        // tear down the panel mid-action.
        if NSApp.modalWindow != nil { return true }
        if panel.attachedSheet != nil { return true }
        var window: NSWindow? = event.window
        while let candidate = window {
            if candidate === panel { return true }
            if let statusItemWindow, candidate === statusItemWindow { return true }
            window = candidate.parent ?? candidate.sheetParent
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

    // MARK: - Price ticker

    private func applyTickerRenderModel(_ model: TickerRenderModel) {
        guard let button = self.statusItem.button else { return }
        guard let title = StatusItemTickerRenderer.attributedTitle(for: model) else {
            self.configureStatusItem()
            return
        }
        button.image = nil
        button.imagePosition = .noImage
        button.attributedTitle = title
        button.setAccessibilityLabel(
            StatusItemTickerRenderer.accessibilityLabel(for: model) ?? self.displayModel.appName)
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
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
