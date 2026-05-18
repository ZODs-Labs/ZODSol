import Foundation
import Kit

public struct Lamports: Hashable, Sendable, Codable, ExpressibleByIntegerLiteral {
    public let rawValue: UInt64

    public static let lamportsPerSol: UInt64 = 1_000_000_000

    public var solValue: Double {
        do {
            return try Kit.decimalFixedPointToNumber(Kit.lamportsToSol(self.rawValue))
        } catch {
            return Double(self.rawValue) / Double(Self.lamportsPerSol)
        }
    }

    public init(rawValue: UInt64) {
        self.rawValue = Kit.lamports(rawValue)
    }

    public init(integerLiteral value: UInt64) {
        self.rawValue = value
    }

    public init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(UInt64.self)
    }

    public func encode(to encoder: any Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}
