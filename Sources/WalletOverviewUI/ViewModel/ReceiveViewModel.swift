import Foundation
import Observation
import SolanaKit

@MainActor @Observable
public final class ReceiveViewModel {
    public let intent: ReceiveIntent
    public let cluster: SolanaNetwork

    public init(intent: ReceiveIntent, cluster: SolanaNetwork) {
        self.intent = intent
        self.cluster = cluster
    }
}
