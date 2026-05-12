import Foundation
import HeliusProvider
import SolanaKit
import SolanaRPC
import WalletOverviewUI

extension HeliusAPIKeyStore: APIKeyStore {}

/// Defers building `HeliusSolanaProvider` until the first API call so the UI
/// can render onboarding when the user has not yet supplied a Helius API key.
/// Called via `reset()` on credentials change.
actor LazyProvider: SolanaProvider {
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
        try await self.resolved().solBalance(for: address, network: network)
    }

    func tokenAccounts(for address: WalletAddress, network: SolanaNetwork) async throws -> [ParsedTokenAccount] {
        try await self.resolved().tokenAccounts(for: address, network: network)
    }

    func assets(
        for address: WalletAddress,
        network: SolanaNetwork,
        options: AssetQueryOptions) async throws -> AssetPage
    {
        try await self.resolved().assets(for: address, network: network, options: options)
    }

    func prices(for mints: [Mint]) async throws -> [Mint: PriceQuote] {
        try await self.resolved().prices(for: mints)
    }

    func solChange24h() async throws -> Double? {
        try await self.resolved().solChange24h()
    }
}

/// Same lazy-resolution pattern as `LazyProvider` but for the raw RPC
/// transport used by the send pipeline. Defers building
/// `URLSessionRPCTransport` until the user has configured an API key, so
/// onboarding does not crash.
actor LazyRPCTransport: RPCTransport {
    private let apiKeyStore: HeliusAPIKeyStore
    private let network: SolanaNetwork
    private var concrete: URLSessionRPCTransport?

    init(apiKeyStore: HeliusAPIKeyStore, network: SolanaNetwork) {
        self.apiKeyStore = apiKeyStore
        self.network = network
    }

    func reset() {
        self.concrete = nil
    }

    private func resolved() async throws -> URLSessionRPCTransport {
        if let concrete { return concrete }
        guard let key = try await apiKeyStore.currentKey(), !key.isEmpty else {
            throw RPCError.http(status: 401, retryAfter: nil)
        }
        let endpoint = HeliusEndpoint(network: network, apiKey: key)
        var components = URLComponents(url: endpoint.rpcURL, resolvingAgainstBaseURL: false)!
        components.queryItems = nil
        let baseURL = components.url!
        let made = URLSessionRPCTransport(
            endpoint: baseURL,
            queryItems: [URLQueryItem(name: "api-key", value: key)])
        self.concrete = made
        return made
    }

    func send<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        try await self.resolved().send(request, responseType: responseType)
    }

    func sendOnce<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        try await self.resolved().sendOnce(request, responseType: responseType)
    }
}
