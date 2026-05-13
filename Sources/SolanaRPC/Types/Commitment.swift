import Foundation

public enum Commitment: String, Sendable, CaseIterable, Codable {
    case processed
    case confirmed
    case finalized

    public var rank: Int {
        switch self {
        case .processed: 0
        case .confirmed: 1
        case .finalized: 2
        }
    }

    public var wireValue: String {
        self.rawValue
    }
}

public func commitmentComparator(_ lhs: Commitment, _ rhs: Commitment) -> Int {
    if lhs.rank < rhs.rank { return -1 }
    if lhs.rank > rhs.rank { return 1 }
    return 0
}

extension Commitment {
    public static func parse(_ raw: String?) -> Commitment? {
        guard let raw else { return nil }
        return Commitment(rawValue: raw)
    }

    public func isAtLeast(_ other: Commitment) -> Bool {
        commitmentComparator(self, other) >= 0
    }
}
