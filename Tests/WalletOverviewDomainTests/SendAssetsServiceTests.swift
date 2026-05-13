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
        confirmationTimeoutSeconds: Int = 90,
        priorityFeeCapMicroLamports: UInt64 = 250_000) -> DefaultSendAssetsService
    {
        let lookup = MockWalletLookup([walletId: from])
        let pendingStore = PendingSendStore(defaults: fixture.defaults, key: "test.pending")
        let config = SendAssetsServiceConfig(
            ataRentLamports: Lamports(rawValue: 2_039_280),
            confirmationTimeoutSeconds: confirmationTimeoutSeconds,
            pollInterval: .milliseconds(10),
            priorityFeeFloorMicroLamports: 1000,
            priorityFeeCapMicroLamports: priorityFeeCapMicroLamports)
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
        await transport.enqueue(method: "getRecentPrioritizationFees", json: """
        {"jsonrpc":"2.0","id":"x","result":[]}
        """)
        await transport.enqueue(method: "getLatestBlockhash", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(bh
            .base58)","lastValidBlockHeight":1500}}}
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
        await transport.enqueue(method: "getRecentPrioritizationFees", json: """
        {"jsonrpc":"2.0","id":"x","result":[]}
        """)
        await transport.enqueue(method: "getLatestBlockhash", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(bh
            .base58)","lastValidBlockHeight":1500}}}
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

    func testSendRefusesWhenFreshPrepareExceedsReviewedFee() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let to = try makeOnCurveRecipient()
        let walletId = UUID()
        let transport = MockSendTransport()
        let bh = try Blockhash(bytes: Data((0..<32).map { UInt8($0) }))

        await enqueueSolQuote(
            transport: transport,
            blockhash: bh,
            prioritizationFee: 1000,
            senderLamports: 10_000_000)
        await enqueueSolQuote(
            transport: transport,
            blockhash: bh,
            prioritizationFee: 2000,
            senderLamports: 10_000_000)

        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture)
        let request = self.makeSolRequest(walletId: walletId, from: from, to: to, lamports: 1000)
        let quote = try await service.quote(request)

        do {
            _ = try await service.send(quote: quote)
            XCTFail("expected quoteExpired")
        } catch let error as SendError {
            XCTAssertEqual(error, .quoteExpired(changedField: "priority fee"))
        }
        let signCount = await signer.signCount
        XCTAssertEqual(signCount, 0)
    }

    func testSendRefusesWhenFreshPrepareChangesReviewedInstructionShape() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let to = try makeOnCurveRecipient()
        let walletId = UUID()
        let transport = MockSendTransport()
        let bh = try Blockhash(bytes: Data((0..<32).map { UInt8($0) }))
        let mintBytes = Data(repeating: 3, count: 32)
        let mint = try WalletAddress(base58: Base58.encode(mintBytes))
        let fromBytes = try Base58.decode(from.base58)
        let mintAccount = Self.mintAccountData(decimals: 6)
        let senderTokenAccount = Self.tokenAccountData(mint: mintBytes, owner: fromBytes, amount: 10_000)

        await self.enqueueSplQuote(
            transport: transport,
            blockhash: bh,
            mintAccountData: mintAccount,
            senderTokenAccountData: senderTokenAccount,
            recipientAtaExists: false)
        await self.enqueueSplQuote(
            transport: transport,
            blockhash: bh,
            mintAccountData: mintAccount,
            senderTokenAccountData: senderTokenAccount,
            recipientAtaExists: true)

        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture)
        let request = SendRequest(
            walletId: walletId,
            from: from,
            recipient: to,
            asset: .splToken(mint: mint, amount: 100, decimals: 6))
        let quote = try await service.quote(request)
        XCTAssertTrue(quote.recipientAtaWillBeCreated)

        do {
            _ = try await service.send(quote: quote)
            XCTFail("expected quoteExpired")
        } catch let error as SendError {
            XCTAssertEqual(error, .quoteExpired(changedField: "recipient token account"))
        }
        let signCount = await signer.signCount
        XCTAssertEqual(signCount, 0)
    }

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
            await transport.enqueue(method: "getRecentPrioritizationFees", json: """
            {"jsonrpc":"2.0","id":"x","result":[]}
            """)
            await transport.enqueue(method: "getLatestBlockhash", json: """
            {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(bh
                .base58)","lastValidBlockHeight":1500}}}
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

    func testResyncPrunesStalePendingSendWithoutSynthesizingExpiredOutcome() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let walletId = UUID()
        let signature = try Signature(bytes: Data(repeating: 9, count: 64))
        let pendingStore = PendingSendStore(defaults: fixture.defaults, key: "test.pending")
        await pendingStore.add(PendingSend(
            walletId: walletId,
            signatureBase58: signature.base58,
            lastValidBlockHeight: UInt64.max,
            network: .devnet,
            createdAt: Date().addingTimeInterval(-25 * 60 * 60)))
        let transport = MockSendTransport()
        await transport.enqueue(method: "getSignatureStatuses", error: RPCError.transport(.timedOut))
        let service = DefaultSendAssetsService(
            transport: transport,
            walletLookup: MockWalletLookup([walletId: from]),
            signer: signer,
            pendingStore: pendingStore,
            network: .devnet,
            config: SendAssetsServiceConfig(
                ataRentLamports: Lamports(rawValue: 2_039_280),
                confirmationTimeoutSeconds: 90,
                pollInterval: .milliseconds(10),
                priorityFeeFloorMicroLamports: 1000))

        let outcomes = await service.resync(walletId: walletId)

        XCTAssertTrue(outcomes.isEmpty)
        let remaining = await pendingStore.all()
        XCTAssertTrue(remaining.isEmpty)
    }

    private func enqueueSolQuote(
        transport: MockSendTransport,
        blockhash: Blockhash,
        prioritizationFee: UInt64,
        senderLamports: UInt64) async
    {
        await transport.enqueue(method: "getRecentPrioritizationFees", json: """
        {"jsonrpc":"2.0","id":"x","result":[{"slot":1,"prioritizationFee":\(prioritizationFee)}]}
        """)
        await transport.enqueue(method: "getLatestBlockhash", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(blockhash
            .base58)","lastValidBlockHeight":1500}}}
        """)
        await transport.enqueue(method: "simulateTransaction", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"err":null,"logs":[],"unitsConsumed":150}}}
        """)
        await transport.enqueue(method: "simulateTransaction", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"err":null,"logs":[],"unitsConsumed":150}}}
        """)
        await transport.enqueue(method: "getAccountInfo", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{
            "lamports":\(senderLamports),"owner":"11111111111111111111111111111111",
            "executable":false,"rentEpoch":0,"data":["","base64"]
        }}}
        """)
    }

    private func enqueueSplQuote(
        transport: MockSendTransport,
        blockhash: Blockhash,
        mintAccountData: Data,
        senderTokenAccountData: Data,
        recipientAtaExists: Bool) async
    {
        await transport.enqueue(method: "getAccountInfo", json: Self.accountInfoJSON(
            owner: ProgramAddresses.token.base58,
            data: mintAccountData))
        await transport.enqueue(method: "getAccountInfo", json: Self.accountInfoJSON(
            owner: ProgramAddresses.token.base58,
            data: senderTokenAccountData))
        if recipientAtaExists {
            await transport.enqueue(method: "getAccountInfo", json: Self.accountInfoJSON(
                owner: ProgramAddresses.token.base58,
                data: senderTokenAccountData))
        } else {
            await transport.enqueue(method: "getAccountInfo", json: """
            {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":null}}
            """)
        }
        await transport.enqueue(method: "getRecentPrioritizationFees", json: """
        {"jsonrpc":"2.0","id":"x","result":[{"slot":1,"prioritizationFee":1000}]}
        """)
        await transport.enqueue(method: "getLatestBlockhash", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(blockhash
            .base58)","lastValidBlockHeight":1500}}}
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

    private static func mintAccountData(decimals: UInt8) -> Data {
        var data = Data(repeating: 0, count: TokenMint.size)
        data[44] = decimals
        data[45] = 1
        return data
    }

    private static func tokenAccountData(mint: Data, owner: Data, amount: UInt64) -> Data {
        var data = Data(repeating: 0, count: TokenAccount.baseSize)
        data.replaceSubrange(0..<32, with: mint)
        data.replaceSubrange(32..<64, with: owner)
        self.writeU64(amount, into: &data, at: 64)
        data[108] = TokenAccountProfile.State.initialized.rawValue
        return data
    }

    private static func writeU64(_ value: UInt64, into data: inout Data, at offset: Int) {
        for index in 0..<8 {
            data[offset + index] = UInt8((value >> (8 * index)) & 0xff)
        }
    }

    private static func accountInfoJSON(owner: String, data: Data) -> String {
        """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{
            "lamports":10000000,"owner":"\(owner)",
            "executable":false,"rentEpoch":0,"data":["\(data.base64EncodedString())","base64"]
        }}}
        """
    }

    // MARK: - Priority tier percentile selection

    /// Sample set [2000, 3000, ... 11000] (10 entries, all above the 1_000
    /// microLamport floor). With the nearest-rank selector
    /// `Int(count * percentile)`, p50 -> index 5 -> 7000, p75 -> index 7 ->
    /// 9000, p95 -> index 9 -> 11000. The three tiers must each yield a
    /// distinct, predictable value uninfluenced by the floor.
    private func enqueueDeterministicQuoteRPCs(transport: MockSendTransport, lifetimeBlockhash: Blockhash) async {
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
        await transport.enqueue(method: "getLatestBlockhash", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(lifetimeBlockhash
            .base58)","lastValidBlockHeight":1500}}}
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
        await transport.enqueue(method: "getRecentPrioritizationFees", json: """
        {"jsonrpc":"2.0","id":"x","result":[
            {"slot":1,"prioritizationFee":2000},
            {"slot":2,"prioritizationFee":3000},
            {"slot":3,"prioritizationFee":5000},
            {"slot":4,"prioritizationFee":1500}
        ]}
        """)
        await transport.enqueue(method: "getLatestBlockhash", json: """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":{"blockhash":"\(lifetimeBlockhash
            .base58)","lastValidBlockHeight":1500}}}
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
            "getRecentPrioritizationFees",
            "getLatestBlockhash",
            "simulateTransaction",
            "simulateTransaction",
            "getAccountInfo",
        ])

        // Compute unit limit = ceil(150 * 1.1), then floored for a stable margin.
        XCTAssertEqual(quote.computeUnitLimit, 25000)
        // Priority fee = 75th percentile of [1500,2000,3000,5000] = sorted index 3 = 5000.
        XCTAssertEqual(quote.priorityFeeMicroLamports, 5000)
        // Fee = 1 * 5000 base + ceil(25000 * 5000 / 1_000_000) = 5000 + 125 = 5125.
        XCTAssertEqual(quote.networkFeeLamports.rawValue, 5125)
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
        XCTAssertEqual(quote.reviewDetails.lastValidBlockHeight, 1500)
        XCTAssertEqual(quote.reviewDetails.simulationStatus, "Simulation passed, 269 bytes")
        XCTAssertEqual(quote.reviewDetails.instructions.map(\.name), [
            "Set compute unit limit",
            "Set compute unit price",
            "Transfer SOL",
        ])
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

    func testQuoteSurfacesPriorityFeeCapWhenBidIsThrottled() async throws {
        let fixture = makeServiceFixture()
        defer { cleanupServiceFixture(fixture) }
        let signer = MockSendSigner()
        let from = try signerAddress(signer)
        let to = try makeOnCurveRecipient()
        let walletId = UUID()
        let transport = MockSendTransport()
        let bh = try Blockhash(bytes: Data((0..<32).map { UInt8($0) }))
        await enqueueSolQuote(
            transport: transport,
            blockhash: bh,
            prioritizationFee: 10_000,
            senderLamports: 10_000_000)

        let service = self.makeService(
            transport: transport,
            signer: signer,
            walletId: walletId,
            from: from,
            fixture: fixture,
            priorityFeeCapMicroLamports: 1_500)
        let request = self.makeSolRequest(walletId: walletId, from: from, to: to, lamports: 1_000_000)
        let quote = try await service.quote(request)

        XCTAssertEqual(quote.priorityFeeMicroLamports, 1_500)
        XCTAssertEqual(quote.reviewDetails.priorityFeeCapMicroLamports, 1_500)
        XCTAssertTrue(quote.reviewDetails.priorityFeeWasCapped)
    }
}
