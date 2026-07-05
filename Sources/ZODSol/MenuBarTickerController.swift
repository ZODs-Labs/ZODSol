import AppKit
import DataProviders
import Foundation
import Observation
import SolanaRPC
import WalletOverviewDomain
import WalletOverviewUI

/// Owns the menu-bar price ticker stack: the polling engine, its presenter and
/// the OS gating observers (display sleep, session lock, reachability, Low Power
/// Mode) plus the panel-open cadence hook. Reports render-model changes through
/// `onRender` so the status item remains the sole owner of its button. Lives in
/// the executable target alongside the other OS-signal observers.
@MainActor
final class MenuBarTickerController {
    private let engine: PriceTickerEngine
    private let settingsStore: TickerSettingsStore
    private let reachabilityMonitor = NetworkReachabilityMonitor()
    private let onRender: (TickerRenderModel) -> Void
    private var presenter: PriceTickerPresenter?
    private var observers: [NSObjectProtocol] = []
    private var reachabilityTask: Task<Void, Never>?

    init(onRender: @escaping (TickerRenderModel) -> Void) {
        self.onRender = onRender
        self.settingsStore = TickerSettingsStore()
        self.engine = PriceTickerEngine(
            provider: LayeredTickerPriceProvider(
                session: URLSession(configuration: .makeCredentialFree()),
                krakenToCoinbaseProducts: TickerCatalog.krakenToCoinbaseProducts),
            lastKnownStore: LastKnownPricesStore())
    }

    func start() {
        Task { @MainActor in await self.setup() }
    }

    func setPanelOpen(_ open: Bool) {
        Task { await self.engine.setPanelOpen(open) }
    }

    /// Re-applies settings changed in the panel UI without rebuilding the stack.
    func applySettings(_ settings: TickerSettings) {
        Task { @MainActor in
            await self.engine.configure(entries: settings.entries.filter(\.isEnabled))
            await self.engine.setWidgetEnabled(settings.isWidgetEnabled)
            self.presenter?.update(displayMode: settings.displayMode, isEnabled: settings.isWidgetEnabled)
            if let model = self.presenter?.renderModel { self.onRender(model) }
        }
    }

    func stop() {
        self.reachabilityTask?.cancel()
        self.reachabilityTask = nil
        self.presenter?.stop()
        let center = NSWorkspace.shared.notificationCenter
        for token in self.observers {
            center.removeObserver(token)
        }
        self.observers.removeAll()
        let engine = self.engine
        let monitor = self.reachabilityMonitor
        Task {
            await engine.stop()
            await monitor.stop()
        }
    }

    private func setup() async {
        let settings = await self.settingsStore.load()
        await self.engine.configure(entries: settings.entries.filter(\.isEnabled))
        await self.engine.setWidgetEnabled(settings.isWidgetEnabled)
        await self.engine.setLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled)

        let presenter = await PriceTickerPresenter(
            snapshots: self.engine.snapshots(),
            displayMode: settings.displayMode,
            isEnabled: settings.isWidgetEnabled)
        self.presenter = presenter
        presenter.start()
        await self.engine.start()

        self.registerPowerObservers()
        self.startReachability()
        self.observeRenderModel()
        self.onRender(presenter.renderModel)
    }

    private func observeRenderModel() {
        withObservationTracking {
            _ = self.presenter?.renderModel
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeRenderModel()
                if let model = self.presenter?.renderModel { self.onRender(model) }
            }
        }
    }

    private func startReachability() {
        self.reachabilityTask = Task { @MainActor [weak self] in
            guard let monitor = self?.reachabilityMonitor else { return }
            for await isOnline in await monitor.updates() {
                await self?.engine.setOnline(isOnline)
            }
        }
    }

    private func registerPowerObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let engine = self.engine
        func observe(_ name: NSNotification.Name, _ handler: @escaping @Sendable () -> Void) {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in handler() })
        }
        observe(NSWorkspace.screensDidSleepNotification) {
            Task { await engine.setScreenAwake(false) }
        }
        observe(NSWorkspace.screensDidWakeNotification) {
            Task {
                await engine.setLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled)
                await engine.setScreenAwake(true)
            }
        }
        observe(NSWorkspace.sessionDidResignActiveNotification) {
            Task { await engine.setSessionLocked(true) }
        }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) {
            Task { await engine.setSessionLocked(false) }
        }
    }
}
