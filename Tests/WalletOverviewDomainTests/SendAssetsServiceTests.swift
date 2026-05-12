import CryptoKit
import Foundation
import SolanaKit
import SolanaRPC
import XCTest
@testable import WalletOverviewDomain

/// Orchestrator tests for `DefaultSendAssetsService`. Covers the early-exit
/// safety checks (no RPC), the full SOL happy path, and the per-wallet
/// in-flight guard.
private struct ServiceFixture: @unchecked Sendable {
    let defaults: UserDefaults
    let suite: String
}

private func makeServiceFixture() -> ServiceFixture {
    let suite = "SendAssetsServiceTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return ServiceFixture(defaults: defaults, suite: suite)
}

private func cleanupServiceFixture(_ fixture: ServiceFixture) {
    fixture.defaults.removePersistentDomain(forName: fixture.suite)
}

final class SendAssetsServiceTests: XCTestCase {
    // MARK: - Helpers

    private func makeService(
        transport: MockSendTransport,
        signer: MockSendSigner,
        walletId: UUID,
        from: WalletAddress,
        fixture: ServiceFixture,
        network: SolanaNetwork = .devnet,
        confirmationTimeoutSeconds: Int = 90) -> DefaultSendAssetsService
    {
        let lookup = MockWalletLookup([walletId: from])
        let pendingStore = PendingSendStore(defaults: fixture.defaults, key: "test.pending")
        let config = SendAssetsServiceConfig(
            ataRentLamports: Lamports(rawValue: 2_039_280),
            confirmationTimeoutSeconds: confirmationTimeoutSeconds,
            pollInterval: .milliseconds(10),
            priorityFeeFloorMicroLamports: 1000)
        return DefaultSendAssetsService(
            transport: transport,
            walletLookup: lookup,
            signer: signer,
            pendingStore: pendingStore,
            network: network,
            config: config)
    }

    private func makeSolRequest(
        walletId: UUID,
        from: WalletAddress,
        to: WalletAddress,
        lamports: UInt64) -> SendRequest
    {
        SendRequest(
            walletId: walletId, from: from, recipient: to,
            asset: .sol(amount: Lamports(rawValue: lamports)))
    }

    private func signerAddress(_ signer: MockSendSigner) throws -> WalletAddress {
        try signer.publicKeyAddress()
    }

    /// A random pubkey we know to be on-curve (generated, not derived).
    private func makeOnCurveRecipient() throws -> WalletAddress {
        let key = Curve25519.Signing.PrivateKey()
        return try WalletAddress(base58: Base58.encode(key.publicKey.rawRepresentation))
    }

    // MARK: - Recipient validation (no RPC)

    func testOffCurveRecipientRefusedForSOLBeforeAnyRPC() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        // The Metaplex metadata PDA is a known off-curve address.
        let pda = try WalletAddress(base58: "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq")
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let walletId = UUID()
        let transport = MockSendTransport()
        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture)
        let request = self.makeSolRequest(walletId: walletId, from: from, to: pda, lamports: 1000)
        do {
            _ = try await service.quote(request)
            XCTFail("expected off-curve refusal")
        } catch let error as SendError {
            XCTAssertEqual(error, .invalidRecipient(.offCurveForSol))
        }
        let pending = await transport.pendingStepCount
        let observed = await transport.observedMethods.count
        XCTAssertEqual(observed, 0, "should never reach RPC")
        XCTAssertEqual(pending, 0)
    }

    func testKnownProgramAddressRefusedBeforeAnyRPC() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let walletId = UUID()
        let transport = MockSendTransport()
        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture)
        let request = self.makeSolRequest(
            walletId: walletId, from: from, to: ProgramAddresses.token, lamports: 1)
        do {
            _ = try await service.quote(request)
            XCTFail("expected known-program refusal")
        } catch let error as SendError {
            XCTAssertEqual(error, .invalidRecipient(.knownProgramAddress))
        }
        let observed = await transport.observedMethods.count
        XCTAssertEqual(observed, 0)
    }

    func testWalletAddressMismatchRefusedBeforeAnyRPC() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let actualFrom = try signerAddress(signer)
        // Lookup maps walletId -> a different address than the request.
        let differentFrom = try makeOnCurveRecipient()
        let walletId = UUID()
        let lookup = MockWalletLookup([walletId: differentFrom])
        let pending = PendingSendStore(defaults: fixture.defaults, key: "test.pending")
        let transport = MockSendTransport()
        let service = DefaultSendAssetsService(
            transport: transport,
            walletLookup: lookup,
            signer: signer,
            pendingStore: pending,
            network: .devnet,
            config: .default)
        let request = try makeSolRequest(
            walletId: walletId, from: actualFrom, to: makeOnCurveRecipient(), lamports: 1)
        do {
            _ = try await service.quote(request)
            XCTFail("expected walletAddressMismatch")
        } catch let error as SendError {
            XCTAssertEqual(error, .walletAddressMismatch)
        }
    }

    // MARK: - SOL balance enforcement

    func testInsufficientSolForFeeRefusedAfterFeeMath() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let to = try makeOnCurveRecipient()
        let walletId = UUID()

        let transport = MockSendTransport()
        let bh = try Blockhash(bytes: Data((0..<32).map { UInt8($0) }))
        await transport.enqueue(method: "getLatestBlockhash", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(bh
            .base58)","lastValidBlockHeight":1500}}}
        """)
        await transport.enqueue(method: "getRecentPrioritizationFees", json: """
        {"jsonrpc":"2.0","id":"x","result":[]}
        """)
        await transport.enqueue(method: "simulateTransaction", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"err":null,"logs":[],"unitsConsumed":150}}}
        """)
        await transport.enqueue(method: "simulateTransaction", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"err":null,"logs":[],"unitsConsumed":150}}}
        """)
        // Sender has only 100 lamports — far below fee.
        await transport.enqueue(method: "getAccountInfo", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{
            "lamports":100,"owner":"11111111111111111111111111111111",
            "executable":false,"rentEpoch":0,"data":["","base64"]
        }}}
        """)

        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture)
        let request = self.makeSolRequest(walletId: walletId, from: from, to: to, lamports: 1_000_000)
        do {
            _ = try await service.quote(request)
            XCTFail("expected insufficientSolForFee")
        } catch let error as SendError {
            switch error {
            case let .insufficientSolForFee(_, available):
                XCTAssertEqual(available, Lamports(rawValue: 100))
            default:
                XCTFail("expected .insufficientSolForFee, got \(error)")
            }
        }
        // No signing happens for an unsigned quote.
        let count = await signer.signCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Simulate-failed propagation

    func testSimulationErrPropagatesAsSimulationFailed() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let to = try makeOnCurveRecipient()
        let walletId = UUID()

        let transport = MockSendTransport()
        let bh = try Blockhash(bytes: Data((0..<32).map { UInt8($0) }))
        await transport.enqueue(method: "getLatestBlockhash", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(bh
            .base58)","lastValidBlockHeight":1500}}}
        """)
        await transport.enqueue(method: "getRecentPrioritizationFees", json: """
        {"jsonrpc":"2.0","id":"x","result":[]}
        """)
        // First simulate fails with an err.
        await transport.enqueue(method: "simulateTransaction", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"err":{"InstructionError":[0,{"Custom":1}]},"logs":["log1","log2"],"unitsConsumed":null}}}
        """)

        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture)
        let request = self.makeSolRequest(walletId: walletId, from: from, to: to, lamports: 1000)
        do {
            _ = try await service.quote(request)
            XCTFail("expected simulationFailed")
        } catch let error as SendError {
            switch error {
            case let .simulationFailed(logs, _):
                XCTAssertEqual(logs, ["log1", "log2"])
            default:
                XCTFail("expected simulationFailed, got \(error)")
            }
        }
    }

    // MARK: - send() failure path clears in-flight guard

    func testSendFailureClearsInFlightAllowingRetry() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let to = try makeOnCurveRecipient()
        let walletId = UUID()

        let transport = MockSendTransport()
        let bh = try Blockhash(bytes: Data((0..<32).map { UInt8($0) }))

        func enqueueSuccessfulQuote() async {
            await transport.enqueue(method: "getLatestBlockhash", json: """
            {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(bh
                .base58)","lastValidBlockHeight":1500}}}
            """)
            await transport.enqueue(method: "getRecentPrioritizationFees", json: """
            {"jsonrpc":"2.0","id":"x","result":[]}
            """)
            await transport.enqueue(method: "simulateTransaction", json: """
            {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"err":null,"logs":[],"unitsConsumed":150}}}
            """)
            await transport.enqueue(method: "simulateTransaction", json: """
            {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"err":null,"logs":[],"unitsConsumed":150}}}
            """)
            await transport.enqueue(method: "getAccountInfo", json: """
            {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{
                "lamports":10000000,"owner":"11111111111111111111111111111111",
                "executable":false,"rentEpoch":0,"data":["","base64"]
            }}}
            """)
        }
        await enqueueSuccessfulQuote()
        await transport.enqueue(method: "sendTransaction", error: RPCError.transport(.timedOut))

        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture)
        let request = self.makeSolRequest(walletId: walletId, from: from, to: to, lamports: 1000)
        let quote1 = try await service.quote(request)
        do {
            _ = try await service.send(quote: quote1)
            XCTFail("expected send to fail")
        } catch let error as SendError {
            switch error {
            case .rpc, .broadcastFailed:
                break
            default:
                XCTFail("expected .rpc or .broadcastFailed, got \(error)")
            }
        }
        // Retry path. The in-flight guard must have been cleared.
        await enqueueSuccessfulQuote()
        await transport.enqueue(method: "sendTransaction", error: RPCError.transport(.timedOut))
        let quote2 = try await service.quote(request)
        do {
            _ = try await service.send(quote: quote2)
            XCTFail("expected second send to fail too")
        } catch let error as SendError {
            XCTAssertNotEqual(error, .sendAlreadyInFlight)
        }
    }

    // MARK: - Priority tier percentile selection

    /// Sample set [2000, 3000, ... 11000] (10 entries, all above the 1_000
    /// microLamport floor). With the nearest-rank selector
    /// `Int(count * percentile)`, p50 -> index 5 -> 7000, p75 -> index 7 ->
    /// 9000, p95 -> index 9 -> 11000. The three tiers must each yield a
    /// distinct, predictable value uninfluenced by the floor.
    private func enqueueDeterministicQuoteRPCs(transport: MockSendTransport, lifetimeBlockhash: Blockhash) async {
        await transport.enqueue(method: "getLatestBlockhash", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(lifetimeBlockhash
            .base58)","lastValidBlockHeight":1500}}}
        """)
        await transport.enqueue(method: "getRecentPrioritizationFees", json: """
        {"jsonrpc":"2.0","id":"x","result":[
            {"slot":1,"prioritizationFee":2000},
            {"slot":2,"prioritizationFee":3000},
            {"slot":3,"prioritizationFee":4000},
            {"slot":4,"prioritizationFee":5000},
            {"slot":5,"prioritizationFee":6000},
            {"slot":6,"prioritizationFee":7000},
            {"slot":7,"prioritizationFee":8000},
            {"slot":8,"prioritizationFee":9000},
            {"slot":9,"prioritizationFee":10000},
            {"slot":10,"prioritizationFee":11000}
        ]}
        """)
        await transport.enqueue(method: "simulateTransaction", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"err":null,"logs":[],"unitsConsumed":150}}}
        """)
        await transport.enqueue(method: "simulateTransaction", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"err":null,"logs":[],"unitsConsumed":150}}}
        """)
        await transport.enqueue(method: "getAccountInfo", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{
            "lamports":10000000,"owner":"11111111111111111111111111111111",
            "executable":false,"rentEpoch":0,"data":["","base64"]
        }}}
        """)
    }
}

extension SendAssetsServiceTests {
    // MARK: - quote() happy path for SOL

    func testSolHappyPathBuildsCorrectQuoteAndCallsRPCInOrder() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let to = try makeOnCurveRecipient()
        let walletId = UUID()

        let transport = MockSendTransport()
        let lifetimeBlockhash = try Blockhash(bytes: Data((0..<32).map { UInt8($0) }))
        await transport.enqueue(method: "getLatestBlockhash", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(lifetimeBlockhash
            .base58)","lastValidBlockHeight":1500}}}
        """)
        await transport.enqueue(method: "getRecentPrioritizationFees", json: """
        {"jsonrpc":"2.0","id":"x","result":[
            {"slot":1,"prioritizationFee":2000},
            {"slot":2,"prioritizationFee":3000},
            {"slot":3,"prioritizationFee":5000},
            {"slot":4,"prioritizationFee":1500}
        ]}
        """)
        // First simulate: returns unitsConsumed = 150 (System.transfer is cheap).
        await transport.enqueue(method: "simulateTransaction", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{
            "err":null,
            "logs":["Program 11111111111111111111111111111111 invoke [1]",
                    "Program 11111111111111111111111111111111 success"],
            "unitsConsumed":150
        }}}
        """)
        // Second simulate: same shape, used as safety check.
        await transport.enqueue(method: "simulateTransaction", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"err":null,"logs":["safety-ok"],"unitsConsumed":150}}}
        """)
        // Sender balance check.
        await transport.enqueue(method: "getAccountInfo", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{
            "lamports":10000000,"owner":"11111111111111111111111111111111",
            "executable":false,"rentEpoch":0,"data":["","base64"]
        }}}
        """)

        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture)
        let request = self.makeSolRequest(walletId: walletId, from: from, to: to, lamports: 1_000_000)
        let quote = try await service.quote(request)

        // Verify the order of RPC calls.
        let methods = await transport.observedMethods
        XCTAssertEqual(methods, [
            "getLatestBlockhash",
            "getRecentPrioritizationFees",
            "simulateTransaction",
            "simulateTransaction",
            "getAccountInfo",
        ])

        // Compute unit limit = ceil(150 * 1.1) = 166, floored at 5000.
        XCTAssertEqual(quote.computeUnitLimit, 5000)
        // Priority fee = 75th percentile of [1500,2000,3000,5000] = sorted index 3 = 5000.
        XCTAssertEqual(quote.priorityFeeMicroLamports, 5000)
        // Fee = 1 * 5000 base + ceil(5000 * 5000 / 1_000_000) = 5000 + 25 = 5025.
        XCTAssertEqual(quote.networkFeeLamports.rawValue, 5025)
        // No ATA creation for SOL.
        XCTAssertFalse(quote.recipientAtaWillBeCreated)
        XCTAssertEqual(quote.rentForRecipientAta.rawValue, 0)
        // No Token-2022 notice for SOL.
        XCTAssertNil(quote.token2022Notice)
        // SOL: recipient receives the same amount.
        XCTAssertEqual(quote.recipientReceives, request.asset)
        // Cluster reflected.
        XCTAssertEqual(quote.cluster, .devnet)
        // Logs surfaced from second simulate.
        XCTAssertEqual(quote.simulationLogs, ["safety-ok"])
        // Lifetime carries the blockhash + last valid block height.
        if case let .blockhash(bh, lvbh) = quote.lifetime {
            XCTAssertEqual(bh, lifetimeBlockhash)
            XCTAssertEqual(lvbh, 1500)
        } else {
            XCTFail("expected blockhash lifetime")
        }
        // signableMessage is a non-trivial V0-encoded blob.
        XCTAssertGreaterThan(quote.signableMessage.count, 100)
        XCTAssertEqual(quote.signableMessage.first, 0x80, "V0 version prefix")
    }

    // MARK: - Priority tier selection

    func test_quote_priorityTier_turbo_selects95thPercentile() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let to = try makeOnCurveRecipient()
        let walletId = UUID()

        let transport = MockSendTransport()
        let bh = try Blockhash(bytes: Data((0..<32).map { UInt8($0) }))
        await self.enqueueDeterministicQuoteRPCs(transport: transport, lifetimeBlockhash: bh)

        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture)
        let request = self.makeSolRequest(walletId: walletId, from: from, to: to, lamports: 1_000_000)
        let quote = try await service.quote(request, tier: .turbo)

        XCTAssertEqual(quote.priorityFeeMicroLamports, 11000)
    }

    func test_quote_priorityTier_standard_selects50thPercentile() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let to = try makeOnCurveRecipient()
        let walletId = UUID()

        let transport = MockSendTransport()
        let bh = try Blockhash(bytes: Data((0..<32).map { UInt8($0) }))
        await self.enqueueDeterministicQuoteRPCs(transport: transport, lifetimeBlockhash: bh)

        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture)
        let request = self.makeSolRequest(walletId: walletId, from: from, to: to, lamports: 1_000_000)
        let quote = try await service.quote(request, tier: .standard)

        XCTAssertEqual(quote.priorityFeeMicroLamports, 7000)
    }
}
