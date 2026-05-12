import Foundation

public enum AnyJSON: Codable, Sendable, Equatable {
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null
    case array([AnyJSON])
    case object([String: AnyJSON])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
            return
        }
        if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
            return
        }
        if let decimalVal = try? container.decode(Decimal.self) {
            self = .number(decimalVal)
            return
        }
        if let arrayVal = try? container.decode([AnyJSON].self) {
            self = .array(arrayVal)
            return
        }
        if let objectVal = try? container.decode([String: AnyJSON].self) {
            self = .object(objectVal)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyJSON: unsupported value")
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(s): try container.encode(s)
        case let .number(d): try container.encode(d)
        case let .bool(b): try container.encode(b)
        case .null: try container.encodeNil()
        case let .array(a): try container.encode(a)
        case let .object(o): try container.encode(o)
        }
    }
}
