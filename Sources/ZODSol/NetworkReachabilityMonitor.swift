import Foundation
import Network

/// Bridges `NWPathMonitor` into an `AsyncStream<Bool>` of "is the network
/// reachable" so the price ticker can suspend its loop when offline and fire an
/// immediate refresh on reconnect, instead of polling into a dead socket.
///
/// Lives in the executable target alongside the other OS-signal observers: it
/// is infrastructure with no Solana coupling, so the domain layer should not
/// import `Network`. The ticker engine just receives the booleans.
actor NetworkReachabilityMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.zods.zodsol.reachability")
    private var continuation: AsyncStream<Bool>.Continuation?
    private var isStarted = false

    func updates() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        self.continuation = continuation
        if !self.isStarted {
            self.isStarted = true
            self.monitor.pathUpdateHandler = { [continuation] path in
                continuation.yield(path.status == .satisfied)
            }
            self.monitor.start(queue: self.queue)
        }
        return stream
    }

    func stop() {
        self.monitor.cancel()
        self.continuation?.finish()
        self.continuation = nil
        self.isStarted = false
    }
}
