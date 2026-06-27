import Formatters
import Foundation
import Observation
import WalletOverviewDomain

/// Bridges the engine's snapshot stream into an observable `renderModel` the
/// status item paints. Keeps the last snapshot so a display-mode or enable
/// change re-renders without waiting for the next fetch. The snapshot->render
/// mapping itself is the pure `TickerRenderModel.build`.
@MainActor
@Observable
public final class PriceTickerPresenter {
    public private(set) var renderModel: TickerRenderModel = .hidden

    private let snapshots: AsyncStream<TickerSnapshot>
    private let priceFormatter: TickerPriceFormatter
    private let deltaFormatter: PercentageDeltaFormatter
    private var displayMode: TickerDisplayMode
    private var isEnabled: Bool
    private var lastSnapshot: TickerSnapshot = .empty
    private var consumeTask: Task<Void, Never>?

    public init(
        snapshots: AsyncStream<TickerSnapshot>,
        displayMode: TickerDisplayMode,
        isEnabled: Bool,
        priceFormatter: TickerPriceFormatter = TickerPriceFormatter(locale: Locale(identifier: "en_US")),
        deltaFormatter: PercentageDeltaFormatter = PercentageDeltaFormatter(locale: Locale(identifier: "en_US")))
    {
        self.snapshots = snapshots
        self.displayMode = displayMode
        self.isEnabled = isEnabled
        self.priceFormatter = priceFormatter
        self.deltaFormatter = deltaFormatter
        self.rebuild()
    }

    public func start() {
        guard self.consumeTask == nil else { return }
        let stream = self.snapshots
        self.consumeTask = Task { @MainActor [weak self] in
            for await snapshot in stream {
                guard let self else { break }
                self.lastSnapshot = snapshot
                self.rebuild()
            }
        }
    }

    public func stop() {
        self.consumeTask?.cancel()
        self.consumeTask = nil
    }

    public func update(displayMode: TickerDisplayMode, isEnabled: Bool) {
        self.displayMode = displayMode
        self.isEnabled = isEnabled
        self.rebuild()
    }

    private func rebuild() {
        self.renderModel = TickerRenderModel.build(
            snapshot: self.lastSnapshot,
            displayMode: self.displayMode,
            isEnabled: self.isEnabled,
            priceFormatter: self.priceFormatter,
            deltaFormatter: self.deltaFormatter)
    }
}
