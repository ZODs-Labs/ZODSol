import Foundation
import OSLog
import SolanaKit
import SolanaRPC

public struct HeliusSolanaProvider: SolanaProvider {
    private let transport: any RPCTransport
    private let pricer: JupiterPriceProvider
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "helius")

    public init(network: SolanaNetwork, apiKey: String) {
        let endpoint = HeliusEndpoint(network: network, apiKey: apiKey)
        var c = URLComponents(url: endpoint.rpcURL, resolvingAgainstBaseURL: false)!
        c.queryItems = nil
        let baseURL = c.url!
        let queryItems = [URLQueryItem(name: "api-key", value: apiKey)]
        self.transport = URLSessionRPCTransport(
            endpoint: baseURL,
            queryItems: queryItems)
        self.pricer = JupiterPriceProvider()
    }

    public init(network: SolanaNetwork, apiKey: String, transport: any RPCTransport, priceTransport: any RPCTransport) {
        self.transport = transport
        self.pricer = JupiterPriceProvider()
    }

    public func solBalance(for address: WalletAddress, network: SolanaNetwork) async throws -> Lamports {
        struct Params: Encodable, Sendable {
            let address: String
            func encode(to encoder: any Encoder) throws {
                var c = encoder.unkeyedContainer()
                try c.encode(self.address)
            }
        }
        let request = JSONRPCRequest(method: "getBalance", params: Params(address: address.base58))
        do {
            let resp: JSONRPCResponse<HeliusBalanceResult> = try await transport.send(
                request,
                responseType: JSONRPCResponse<HeliusBalanceResult>.self)
            let result = try resp.unwrap()
            return Lamports(rawValue: result.value)
        } catch let e as RPCError {
            throw Self.mapRPCError(e)
        }
    }

    public func tokenAccounts(for address: WalletAddress, network: SolanaNetwork) async throws -> [ParsedTokenAccount] {
        struct Params: Encodable, Sendable {
            let owner: String
            let filter: [String: String]
            let config: [String: String]
            func encode(to encoder: any Encoder) throws {
                var c = encoder.unkeyedContainer()
                try c.encode(self.owner)
                try c.encode(self.filter)
                try c.encode(self.config)
            }
        }
        let params = Params(
            owner: address.base58,
            filter: ["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"],
            config: ["encoding": "jsonParsed", "commitment": "confirmed"])
        let request = JSONRPCRequest(method: "getTokenAccountsByOwner", params: params)
        do {
            let resp: JSONRPCResponse<HeliusTokenAccountsResult> = try await transport.send(
                request,
                responseType: JSONRPCResponse<HeliusTokenAccountsResult>.self)
            let result = try resp.unwrap()
            return try result.value.map { try Self.mapHolding($0, owner: address) }
        } catch let e as RPCError {
            throw Self.mapRPCError(e)
        }
    }

    /// Returns SPL Token v1 accounts only. Token-2022 holdings are surfaced via `assets(for:network:options:)`
    /// with `showFungible=true` (Helius DAS indexes both programs). This method exists to satisfy the
    /// `TokenAccountsProvider` protocol; the overview UI consumes `assets(...)`, not this method.
    public func assets(
        for address: WalletAddress,
        network: SolanaNetwork,
        options: AssetQueryOptions) async throws -> AssetPage
    {
        let params = HeliusAssetsByOwnerParams(
            ownerAddress: address.base58,
            page: options.page,
            limit: options.limit,
            displayOptions: .init(
                showFungible: options.showFungible,
                showNativeBalance: options.showNativeBalance,
                showZeroBalance: options.showZeroBalance))
        let request = JSONRPCRequest(method: "getAssetsByOwner", params: params)
        do {
            let resp: JSONRPCResponse<HeliusAssetsByOwnerResult> = try await transport.send(
                request,
                responseType: JSONRPCResponse<HeliusAssetsByOwnerResult>.self)
            let result = try resp.unwrap()
            return try Self.buildPage(result, options: options)
        } catch let e as RPCError {
            throw Self.mapRPCError(e)
        }
    }

    public func prices(for mints: [Mint]) async throws -> [Mint: PriceQuote] {
        try await self.pricer.prices(for: mints)
    }

    public func solChange24h() async throws -> Double? {
        try await self.pricer.solChange24h()
    }
}
