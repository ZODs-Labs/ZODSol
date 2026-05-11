import Foundation
import Observation
import WalletOverviewDomain
import SolanaKit

public enum PanelRoute: Sendable, Equatable {
    case overview
    case switcher
    case manage
    case rename(walletId: UUID)
    case addWallet
}

@MainActor @Observable
public final class WalletOverviewViewModel {
    public private(set) var state: LoadState<WalletOverview> = .idle
    public private(set) var wallets: [WalletIdentity] = []
    public private(set) var activeWalletId: UUID?
    public private(set) var hasAPIKey: Bool = false
    public var route: PanelRoute = .overview

    public let service: any WalletOverviewService
    public let walletStore: WalletStore
    public let apiKeyStore: any APIKeyStore
    private let credentialsDidChange: (@Sendable () async -> Void)?
    private var refreshTask: Task<Void, Never>?

    public init(
        service: any WalletOverviewService,
        walletStore: WalletStore,
        apiKeyStore: any APIKeyStore,
        credentialsDidChange: (@Sendable () async -> Void)? = nil
    ) {
        self.service = service
        self.walletStore = walletStore
        self.apiKeyStore = apiKeyStore
        self.credentialsDidChange = credentialsDidChange
    }

    public func panelDidAppear() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.loadInitialState()
            guard !Task.isCancelled else { return }
            guard let walletId = self.activeWalletId else { return }
            let stream = self.service.stream(for: walletId, tick: .seconds(15))
            for await newState in stream {
                guard !Task.isCancelled else { break }
                self.state = newState
            }
        }
    }

    public func panelDidDisappear() {
        refreshTask?.cancel()
        refreshTask = nil
        // Reset to the default screen so the next panel open starts on the
        // overview, not on a stale switcher/manage screen.
        self.route = .overview
    }

    public func selectWallet(_ id: UUID) async {
        guard id != activeWalletId else {
            self.route = .overview
            return
        }
        self.activeWalletId = id
        await walletStore.setSelectedWallet(id)
        self.state = .loading
        self.route = .overview
        panelDidAppear()
    }

    public func addWallet(privateKeyText: String, label: String) async throws {
        let parsed = try ImportedPrivateKey.parse(privateKeyText)
        let identity = try await walletStore.add(privateKey: parsed, label: label)
        self.wallets = await walletStore.wallets()
        self.activeWalletId = identity.id
        await walletStore.setSelectedWallet(identity.id)
        self.state = .loading
        panelDidAppear()
    }

    public func removeWallet(_ id: UUID) async {
        try? await walletStore.remove(walletId: id)
        self.wallets = await walletStore.wallets()
        if activeWalletId == id {
            activeWalletId = self.wallets.first?.id
            await walletStore.setSelectedWallet(activeWalletId)
            if activeWalletId == nil {
                state = .idle
                refreshTask?.cancel()
            } else {
                panelDidAppear()
            }
        }
    }

    public func renameWallet(_ id: UUID, to newLabel: String) async {
        try? await walletStore.rename(walletId: id, to: newLabel)
        self.wallets = await walletStore.wallets()
    }

    public func setAPIKey(_ key: String) async throws {
        try await apiKeyStore.save(key)
        await credentialsDidChange?()
        await service.invalidateAll()
        self.hasAPIKey = true
    }

    public func clearAPIKey() async {
        try? await apiKeyStore.clear()
        await credentialsDidChange?()
        await service.invalidateAll()
        self.hasAPIKey = false
    }

    public func refresh() async {
        guard let walletId = activeWalletId else { return }
        let result = await service.load(for: walletId, forceRevalidate: true)
        self.state = result
    }

    private func loadInitialState() async {
        self.hasAPIKey = (try? await apiKeyStore.currentKey()) != nil
        self.wallets = await walletStore.wallets()
        self.activeWalletId = await walletStore.selectedWalletId() ?? self.wallets.first?.id
        if !self.hasAPIKey || self.wallets.isEmpty {
            self.state = .idle
        } else {
            self.state = .loading
        }
    }
}
