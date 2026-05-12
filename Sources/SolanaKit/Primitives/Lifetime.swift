import Foundation

/// How a transaction's recency is enforced by the cluster.
///
/// V1 ships only `.blockhash`. The `.nonce` case is reserved as a forward-
/// compatibility seam so adding durable-nonce support later is additive and
/// does not require changing the surrounding `TransactionMessage` shape.
public enum Lifetime: Hashable, Sendable {
    case blockhash(Blockhash, lastValidBlockHeight: UInt64)
}
