import AppKit
import Foundation
import Observation
import SolanaKit

@MainActor @Observable
public final class ReceiveViewModel {
    public let intent: ReceiveIntent
    public let cluster: SolanaNetwork

    enum AmountRequest: Equatable {
        case none
        case requesting(asset: PortfolioRow, amountText: String)
    }

    var amountRequest: AmountRequest = .none
    public private(set) var qrImage: NSImage?
    public private(set) var qrPayload: String = ""
    public private(set) var copyToastVisible: Bool = false

    private let toastDuration: TimeInterval
    private var regenerateTask: Task<Void, Never>?
    private var copyToastTask: Task<Void, Never>?
    private var renderToken: UInt64 = 0

    public init(intent: ReceiveIntent, cluster: SolanaNetwork, toastDuration: TimeInterval = 2.0) {
        self.intent = intent
        self.cluster = cluster
        self.toastDuration = toastDuration
    }

    public func onAppear() {
        self.qrPayload = self.intent.address.base58
        self.regenerate()
    }

    func setAmountRequest(asset: PortfolioRow) {
        let currentText: String = if case let .requesting(_, text) = self.amountRequest {
            text
        } else {
            ""
        }
        self.amountRequest = .requesting(asset: asset, amountText: currentText)
        self.regenerate()
    }

    public func updateAmountText(_ text: String) {
        guard case let .requesting(asset, _) = self.amountRequest else { return }
        self.amountRequest = .requesting(asset: asset, amountText: text)

        self.regenerateTask?.cancel()
        self.regenerateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.regenerate()
        }
    }

    public func clearAmountRequest() {
        self.amountRequest = .none
        self.regenerate()
    }

    public func copyAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(self.qrPayload, forType: .string)
        self.copyToastVisible = true

        self.copyToastTask?.cancel()
        let duration = self.toastDuration
        self.copyToastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.copyToastVisible = false
        }
    }

    private func regenerate() {
        switch self.amountRequest {
        case .none:
            self.qrPayload = self.intent.address.base58
        case let .requesting(asset, text):
            self.qrPayload = self.buildPayload(asset: asset, text: text)
        }
        self.scheduleRender()
    }

    private func buildPayload(asset: PortfolioRow, text: String) -> String {
        let fallback = self.intent.address.base58
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount: Decimal? = {
            guard !trimmed.isEmpty else { return nil }
            return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
        }()

        let splToken: Mint?
        if asset.isNative {
            splToken = nil
        } else if let mint = try? Mint(base58: asset.id) {
            splToken = mint
        } else {
            return fallback
        }

        do {
            let url = try SolanaPayURIBuilder.build(
                recipient: self.intent.address,
                amount: amount,
                splToken: splToken,
                label: "ZODSol")
            return url.absoluteString
        } catch {
            return fallback
        }
    }

    private func scheduleRender() {
        self.renderToken &+= 1
        let token = self.renderToken
        let payload = self.qrPayload
        let pixelSize = self.renderPixelSize()
        Task { [weak self] in
            let image = await QRCodeRenderer.render(
                payload: payload,
                foreground: NSColor.labelColor.cgColor,
                background: NSColor.clear.cgColor,
                sizeInPixels: pixelSize)
            await MainActor.run {
                guard let self else { return }
                guard token == self.renderToken else { return }
                self.qrImage = image
            }
        }
    }

    private func renderPixelSize() -> Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return 256 * Int(scale)
    }
}
