import Foundation

public struct Lamports: Hashable, Sendable, Codable, ExpressibleByIntegerLiteral {
    public let rawValue: UInt64

    public static let lamportsPerSol: UInt64 = 1_000_000_000

    public var solValue: Double {
        Double(self.rawValue) / 1_000_000_000.0
    }

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: UInt64) {
        self.rawValue = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(UInt64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}
