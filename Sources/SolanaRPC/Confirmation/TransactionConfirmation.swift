import Foundation

public enum TransactionConfirmation {
    public enum Status: Sendable, Equatable {
        case confirmed(slot: UInt64)
        case failed(error: String)
        case expired
    }

    public struct Outcome: Sendable, Equatable {
        public let signatureBase58: String
        public let status: Status

        public init(signatureBase58: String, status: Status) {
            self.signatureBase58 = signatureBase58
            self.status = status
        }
    }

    public struct Config: Sendable {
        public let commitment: Commitment
        public let pollInterval: Duration
        public let timeout: Duration
        public let blockHeightRefreshTicks: Int

        public init(
            commitment: Commitment = .confirmed,
            pollInterval: Duration = .seconds(2),
            timeout: Duration = .seconds(60),
            blockHeightRefreshTicks: Int = 4)
        {
            self.commitment = commitment
            self.pollInterval = pollInterval
            self.timeout = timeout
            self.blockHeightRefreshTicks = blockHeightRefreshTicks
        }
    }

    public static func waitForRecentTransaction(
        signatureBase58: String,
        lastValidBlockHeight: UInt64,
        transport: any RPCTransport,
        clock: any Clock<Duration> = ContinuousClock(),
        config: Config = Config()) async throws -> Outcome
    {
        try await withThrowingTaskGroup(of: Status?.self) { group in
            group.addTask {
                try await RecentSignatureConfirmationStrategy.run(
                    signatureBase58: signatureBase58,
                    transport: transport,
                    clock: clock,
                    config: config)
            }
            group.addTask {
                try await BlockHeightExceedanceStrategy.run(
                    lastValidBlockHeight: lastValidBlockHeight,
                    transport: transport,
                    clock: clock,
                    config: config)
            }
            group.addTask { try await TimeoutStrategy.run(clock: clock, timeout: config.timeout) }

            defer { group.cancelAll() }
            while let resolved = try await group.next() {
                if let status = resolved {
                    return Outcome(signatureBase58: signatureBase58, status: status)
                }
            }
            return Outcome(signatureBase58: signatureBase58, status: .expired)
        }
    }
}

enum RecentSignatureConfirmationStrategy {
    static func run(
        signatureBase58: String,
        transport: any RPCTransport,
        clock: any Clock<Duration>,
        config: TransactionConfirmation.Config) async throws -> TransactionConfirmation.Status?
    {
        if let immediate = try await checkOnce(signatureBase58: signatureBase58, transport: transport, config: config) {
            return immediate
        }
        while true {
            try Task.checkCancellation()
            try await clock.sleep(for: config.pollInterval)
            try Task.checkCancellation()
            if let status = try await Self.checkOnce(
                signatureBase58: signatureBase58,
                transport: transport,
                config: config)
            {
                return status
            }
        }
    }

    private static func checkOnce(
        signatureBase58: String,
        transport: any RPCTransport,
        config: TransactionConfirmation.Config) async throws -> TransactionConfirmation.Status?
    {
        let request = SignatureStatusesRPC.request(signatures: [signatureBase58])
        let response: JSONRPCResponse<SignatureStatusesRPC.Result> = try await transport.send(
            request,
            responseType: JSONRPCResponse<SignatureStatusesRPC.Result>.self)
        let result = try response.unwrap()
        guard let status = result.value.first ?? nil else { return nil }
        if let err = status.err { return .failed(error: self.stringify(err)) }
        let reached = Commitment.parse(status.confirmationStatus)?.isAtLeast(config.commitment) ?? false
        guard reached else { return nil }
        return .confirmed(slot: status.slot)
    }

    private static func stringify(_ err: AnyJSON) -> String {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(err), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "unstructured error"
    }
}

enum BlockHeightExceedanceStrategy {
    static func run(
        lastValidBlockHeight: UInt64,
        transport: any RPCTransport,
        clock: any Clock<Duration>,
        config: TransactionConfirmation.Config) async throws -> TransactionConfirmation.Status?
    {
        var snapshot = try await fetchEpoch(transport: transport, commitment: config.commitment)
        if snapshot.blockHeight > lastValidBlockHeight {
            return .expired
        }
        var slotsToBlocksDelta = snapshot.absoluteSlot &- snapshot.blockHeight

        let probeInterval = config.pollInterval * config.blockHeightRefreshTicks
        while true {
            try Task.checkCancellation()
            try await clock.sleep(for: probeInterval)
            try Task.checkCancellation()

            let probe = try await fetchEpoch(transport: transport, commitment: config.commitment)
            let projectedBlockHeight = probe.absoluteSlot &- slotsToBlocksDelta
            if projectedBlockHeight <= lastValidBlockHeight {
                slotsToBlocksDelta = probe.absoluteSlot &- probe.blockHeight
                snapshot = probe
                continue
            }
            if probe.blockHeight > lastValidBlockHeight {
                return .expired
            }
            slotsToBlocksDelta = probe.absoluteSlot &- probe.blockHeight
            snapshot = probe
        }
    }

    private static func fetchEpoch(
        transport: any RPCTransport,
        commitment: Commitment) async throws -> EpochInfoRPC.Result
    {
        let request = EpochInfoRPC.request(commitment: commitment.wireValue)
        let response: JSONRPCResponse<EpochInfoRPC.Result> = try await transport.send(
            request,
            responseType: JSONRPCResponse<EpochInfoRPC.Result>.self)
        return try response.unwrap()
    }
}

enum TimeoutStrategy {
    static func run(clock: any Clock<Duration>, timeout: Duration) async throws -> TransactionConfirmation.Status? {
        try await clock.sleep(for: timeout)
        return nil
    }
}
