import Foundation
import HeliusProvider
import SolanaKit
import SolanaRPC
import WalletOverviewUI

extension HeliusAPIKeyStore: APIKeyStore {}

actor LazyProvider: SolanaProvider {
    private let apiKeyStore: HeliusAPIKeyStore
    private let session: URLSession
    private var concrete: HeliusSolanaProvider?

    init(apiKeyStore: HeliusAPIKeyStore, session: URLSession) {
        self.apiKeyStore = apiKeyStore
        self.session = session
    }

    private func resolved() async throws -> HeliusSolanaProvider {
        if let concrete { return concrete }
        guard let key = try await apiKeyStore.currentKey(), !key.isEmpty else {
            throw SolanaProviderError.unauthorized
        }
        let made = HeliusSolanaProvider(network: .mainnet, apiKey: key, session: self.session)
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

actor LazyRPCTransport: RPCTransport {
    private let apiKeyStore: HeliusAPIKeyStore
    private let network: SolanaNetwork
    private let session: URLSession
    private let enableCoalescing: Bool
    private var concrete: (any RPCTransport)?

    init(
        apiKeyStore: HeliusAPIKeyStore,
        network: SolanaNetwork,
        session: URLSession,
        enableCoalescing: Bool = false)
    {
        self.apiKeyStore = apiKeyStore
        self.network = network
        self.session = session
        self.enableCoalescing = enableCoalescing
    }

    func reset() {
        self.concrete = nil
    }

    private func resolved() async throws -> any RPCTransport {
        if let concrete { return concrete }
        guard let key = try await apiKeyStore.currentKey(), !key.isEmpty else {
            throw RPCError.http(status: 401, retryAfter: nil)
        }
        let endpoint = HeliusEndpoint(network: self.network, apiKey: key)
        var components = URLComponents(url: endpoint.rpcURL, resolvingAgainstBaseURL: false)!
        components.queryItems = nil
        let baseURL = components.url!
        let raw = URLSessionRPCTransport(
            endpoint: baseURL,
            queryItems: [URLQueryItem(name: "api-key", value: key)],
            session: self.session)
        let made: any RPCTransport = self.enableCoalescing
            ? CoalescingRPCTransport(inner: raw)
            : raw
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
