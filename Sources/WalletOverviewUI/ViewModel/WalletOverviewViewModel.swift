import Foundation
import Observation
import SolanaKit
import WalletOverviewDomain

public enum PanelRoute: Sendable, Equatable {
    case overview
    case switcher
    case manage
    case rename(walletId: UUID)
    case addWallet
    case send(SendIntent)
    case assetPicker(AssetPickerIntent)
    case receive(ReceiveIntent)
    case security
}

public struct ReceiveIntent: Sendable, Equatable {
    public let walletId: UUID
    public let address: WalletAddress
    public let network: SolanaNetwork

    public init(walletId: UUID, address: WalletAddress, network: SolanaNetwork) {
        self.walletId = walletId
        self.address = address
        self.network = network
    }
}

public struct AssetPickerIntent: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case send
        case receive(ReceiveIntent)
    }

    public let walletId: UUID
    public let from: WalletAddress
    public let mode: Mode

    public init(walletId: UUID, from: WalletAddress, mode: Mode) {
        self.walletId = walletId
        self.from = from
        self.mode = mode
    }
}

public struct PendingSendDisplayInfo: Sendable, Equatable {
    public let signature: Signature
    public let outcome: SendOutcome

    public init(signature: Signature, outcome: SendOutcome) {
        self.signature = signature
        self.outcome = outcome
    }
}

@MainActor @Observable
public final class WalletOverviewViewModel {
    public private(set) var state: LoadState<WalletOverview> = .idle
    public private(set) var wallets: [WalletIdentity] = []
    public private(set) var activeWalletId: UUID?
    public private(set) var hasAPIKey: Bool = false
    public var route: PanelRoute = .overview
    public private(set) var pendingSendBanner: PendingSendDisplayInfo?
    var pendingReceiveAsset: PortfolioRow?
    public var preloadConfirmingSignature: Signature?

    public let service: any WalletOverviewService
    public let walletStore: WalletStore
    public let apiKeyStore: any APIKeyStore
    public let sendService: any SendAssetsService
    public let network: SolanaNetwork
    public let recentRecipientsStore: RecentRecipientsStore
    public let session: WalletSession?
    public let sessionPolicyStore: WalletSessionPolicyStore?
    public private(set) var sessionPolicy: WalletSession.Policy = .default
    private let credentialsDidChange: (@Sendable () async -> Void)?
    private var refreshTask: Task<Void, Never>?

    public init(
        service: any WalletOverviewService,
        walletStore: WalletStore,
        apiKeyStore: any APIKeyStore,
        sendService: any SendAssetsService,
        network: SolanaNetwork,
        recentRecipientsStore: RecentRecipientsStore = RecentRecipientsStore(),
        session: WalletSession? = nil,
        sessionPolicyStore: WalletSessionPolicyStore? = nil,
        credentialsDidChange: (@Sendable () async -> Void)? = nil)
    {
        self.service = service
        self.walletStore = walletStore
        self.apiKeyStore = apiKeyStore
        self.sendService = sendService
        self.network = network
        self.recentRecipientsStore = recentRecipientsStore
        self.session = session
        self.sessionPolicyStore = sessionPolicyStore
        self.credentialsDidChange = credentialsDidChange
    }

    public func panelDidAppear() {
        self.refreshTask?.cancel()
        self.refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.loadInitialState()
            guard !Task.isCancelled else { return }
            guard let walletId = self.activeWalletId else { return }
            await self.resyncPendingSends(walletId: walletId)
            let stream = self.service.stream(for: walletId, tick: .seconds(15))
            for await newState in stream {
                guard !Task.isCancelled else { break }
                self.state = newState
            }
        }
    }

    public func panelDidDisappear() {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        // Reset to the default screen so the next panel open starts on the
        // overview, not on a stale switcher/manage screen.
        self.route = .overview
        // Honor the "lock on panel close" policy. The session no-ops if the
        // active policy uses a different trigger.
        if let session {
            Task { await session.handlePanelDidDisappear() }
        }
    }

    /// Force-clear all cached seeds. Used by the "Lock now" affordance.
    public func lockNow() {
        guard let session else { return }
        Task { await session.lockAll() }
    }

    /// Update and persist the auto-lock policy. The new policy takes effect
    /// immediately - if the new trigger is `.immediately` or has a tighter
    /// idle window than what the cache already exceeds, entries are purged.
    public func updateSessionPolicy(_ policy: WalletSession.Policy) async {
        self.sessionPolicy = policy
        await self.sessionPolicyStore?.save(policy)
        await self.session?.setPolicy(policy)
    }

    public func selectWallet(_ id: UUID) async {
        guard id != self.activeWalletId else {
            self.route = .overview
            return
        }
        self.activeWalletId = id
        await self.walletStore.setSelectedWallet(id)
        self.state = .loading
        self.route = .overview
        self.panelDidAppear()
    }

    public func addWallet(privateKeyText: String, label: String) async throws {
        let parsed = try ImportedPrivateKey.parse(privateKeyText)
        let identity = try await walletStore.add(privateKey: parsed, label: label)
        self.wallets = await self.walletStore.wallets()
        self.activeWalletId = identity.id
        await self.walletStore.setSelectedWallet(identity.id)
        self.state = .loading
        self.panelDidAppear()
    }

    public func removeWallet(_ id: UUID) async {
        try? await self.walletStore.remove(walletId: id)
        self.wallets = await self.walletStore.wallets()
        if self.activeWalletId == id {
            self.activeWalletId = self.wallets.first?.id
            await self.walletStore.setSelectedWallet(self.activeWalletId)
            if self.activeWalletId == nil {
                self.state = .idle
                self.refreshTask?.cancel()
            } else {
                self.panelDidAppear()
            }
        }
    }

    public func renameWallet(_ id: UUID, to newLabel: String) async {
        try? await self.walletStore.rename(walletId: id, to: newLabel)
        self.wallets = await self.walletStore.wallets()
    }

    public func setAPIKey(_ key: String) async throws {
        try await self.apiKeyStore.save(key)
        await self.credentialsDidChange?()
        await self.service.invalidateAll()
        self.hasAPIKey = true
        self.route = .overview
        guard self.activeWalletId != nil else {
            self.state = .idle
            return
        }
        self.state = .loading
        self.panelDidAppear()
    }

    public func clearAPIKey() async {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        try? await self.apiKeyStore.clear()
        await self.credentialsDidChange?()
        await self.service.invalidateAll()
        self.hasAPIKey = false
        self.state = .idle
        self.route = .overview
    }

    public func refresh() async {
        guard let walletId = activeWalletId else { return }
        let result = await service.load(for: walletId, forceRevalidate: true)
        self.state = result
    }

    private func loadInitialState() async {
        self.hasAPIKey = await (try? self.apiKeyStore.currentKey()) != nil
        self.wallets = await self.walletStore.wallets()
        self.activeWalletId = await self.walletStore.selectedWalletId() ?? self.wallets.first?.id
        if let store = sessionPolicyStore {
            self.sessionPolicy = await store.load()
        } else if let session {
            self.sessionPolicy = await session.currentPolicy()
        }
        if !self.hasAPIKey || self.wallets.isEmpty {
            self.state = .idle
        } else {
            self.state = .loading
        }
    }

    public func handleHeaderSend() {
        guard let walletId = self.activeWalletId,
              let address = self.activeWalletAddress
        else { return }
        let intent = AssetPickerIntent(walletId: walletId, from: address, mode: .send)
        self.route = .assetPicker(intent)
    }

    public func handleHeaderReceive() {
        guard let walletId = self.activeWalletId,
              let address = self.activeWalletAddress
        else { return }
        let intent = ReceiveIntent(walletId: walletId, address: address, network: self.network)
        self.route = .receive(intent)
    }

    func handleAssetPicked(_ row: PortfolioRow) {
        guard case let .assetPicker(intent) = self.route else { return }
        switch intent.mode {
        case .send:
            guard let asset = row.toSendAsset() else { return }
            let sendIntent = SendIntent(walletId: intent.walletId, from: intent.from, asset: asset)
            self.route = .send(sendIntent)
        case let .receive(receiveIntent):
            self.pendingReceiveAsset = row
            self.route = .receive(receiveIntent)
        }
    }

    public func acknowledgePendingSend(_ info: PendingSendDisplayInfo) {
        guard let walletId = self.activeWalletId,
              let address = self.activeWalletAddress
        else { return }
        self.preloadConfirmingSignature = info.signature
        let intent = SendIntent(walletId: walletId, from: address, asset: .sol)
        self.route = .send(intent)
    }

    public var activeWalletAddress: WalletAddress? {
        guard let walletId = self.activeWalletId else { return nil }
        return self.wallets.first(where: { $0.id == walletId })?.address
    }

    /// `true` once both an address is selected and the overview has loaded
    /// (`loaded` or `partial`). Header send/receive buttons gate on this so
    /// taps during initial load are not silently dropped.
    public var canSendOrReceive: Bool {
        if self.activeWalletAddress == nil { return false }
        switch self.state {
        case .loaded, .partial: return true
        case .idle, .loading, .failed: return false
        }
    }

    private func resyncPendingSends(walletId: UUID) async {
        let outcomes = await self.sendService.resync(walletId: walletId)
            .sorted { $0.createdAt < $1.createdAt }
        if let resolution = outcomes.first {
            self.pendingSendBanner = PendingSendDisplayInfo(
                signature: resolution.signature,
                outcome: resolution.outcome)
        } else {
            self.pendingSendBanner = nil
        }
    }
}

extension PortfolioRow {
    /// Map a portfolio row onto the `SendAssetKind` the send pipeline accepts.
    /// Returns `nil` only when the row is an SPL token whose mint cannot be
    /// parsed back into a 32-byte base58 address (which shouldn't happen in
    /// production because Helius only emits valid mints).
    func toSendAsset() -> SendAssetKind? {
        if self.isNative { return .sol }
        guard let mint = try? Mint(base58: self.id) else { return nil }
        return .splToken(
            mint: mint,
            decimals: self.amount.decimals,
            symbol: self.symbol,
            name: self.name)
    }
}
