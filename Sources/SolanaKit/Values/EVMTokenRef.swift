import Foundation

/// The identity of an EVM token: its chain plus its lowercased contract address.
/// Serializes to and from the opaque `sourceIdentifier` the ticker engine and
/// stores key on, so the whole refresh and persistence machine stays unchanged.
///
/// Wire format: `evm:{chain.slug}:{lowercased-0x-address}`
/// e.g. `evm:base:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913`.
public struct EVMTokenRef: Sendable, Hashable {
    public let chain: EVMChain
    public let address: String

    public init(chain: EVMChain, address: String) {
        self.chain = chain
        self.address = address.lowercased()
    }

    public var sourceIdentifier: String {
        "evm:\(self.chain.slug):\(self.address)"
    }

    /// Parses a `sourceIdentifier` back into a ref, or nil when it is not an EVM
    /// identifier or names a chain that is no longer supported.
    public init?(sourceIdentifier: String) {
        let parts = sourceIdentifier.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "evm",
              let chain = EVMChain.supported(slug: String(parts[1]))
        else {
            return nil
        }
        self.chain = chain
        self.address = String(parts[2])
    }
}
