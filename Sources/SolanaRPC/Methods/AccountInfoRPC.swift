import Foundation

/// `getAccountInfo`: returns one account's data. We always request
/// `encoding: "base64"` so the bytes survive without truncation; callers
/// base64-decode and route to the appropriate domain parser.
///
/// Used for: (1) reading mint accounts to determine owner program (legacy
/// vs Token-2022) and parse extensions, (2) checking recipient ATA existence,
/// (3) reading recipient lamports for SOL "send max" math.
public enum AccountInfoRPC {
    public struct Params: Encodable, Sendable {
        public let address: String
        public let commitment: String
        public let minContextSlot: UInt64?

        public init(address: String, commitment: String = "confirmed", minContextSlot: UInt64? = nil) {
            self.address = address
            self.commitment = commitment
            self.minContextSlot = minContextSlot
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(self.address)
            struct Config: Encodable {
                let encoding: String
                let commitment: String
                let minContextSlot: UInt64?

                enum CodingKeys: String, CodingKey {
                    case encoding
                    case commitment
                    case minContextSlot
                }

                func encode(to encoder: any Encoder) throws {
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    try c.encode(self.encoding, forKey: .encoding)
                    try c.encode(self.commitment, forKey: .commitment)
                    if let minContextSlot { try c.encode(minContextSlot, forKey: .minContextSlot) }
                }
            }
            try container.encode(Config(
                encoding: "base64",
                commitment: self.commitment,
                minContextSlot: self.minContextSlot))
        }
    }

    public enum AccountData: Decodable, Sendable, Equatable {
        case base64(String)
        case unsupported(data: String, encoding: String?)

        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let payload = try container.decode(String.self)
            let encoding = try container.decodeIfPresent(String.self)
            if encoding == "base64" {
                self = .base64(payload)
            } else {
                self = .unsupported(data: payload, encoding: encoding)
            }
        }
    }

    public struct AccountValue: Decodable, Sendable {
        public let lamports: UInt64
        public let owner: String
        public let executable: Bool
        public let rentEpoch: UInt64?
        public let data: AccountData
        public let space: UInt64?

        public var base64Data: String? {
            guard case let .base64(value) = self.data else { return nil }
            return value
        }

        public func validatedBase64Bytes(
            expectedOwner: String? = nil,
            allowExecutable: Bool = false,
            minimumLength: Int = 0) throws -> Data
        {
            if let expectedOwner, self.owner != expectedOwner {
                throw AccountInfoError.ownerMismatch(expected: expectedOwner, actual: self.owner)
            }
            if self.executable, !allowExecutable {
                throw AccountInfoError.executableAccount
            }
            guard let base64Data else {
                throw AccountInfoError.unsupportedEncoding
            }
            guard let bytes = Data(base64Encoded: base64Data) else {
                throw AccountInfoError.invalidBase64
            }
            guard bytes.count >= minimumLength else {
                throw AccountInfoError.dataTooShort(expected: minimumLength, actual: bytes.count)
            }
            return bytes
        }
    }

    public enum AccountInfoError: Error, Sendable, Equatable {
        case ownerMismatch(expected: String, actual: String)
        case executableAccount
        case unsupportedEncoding
        case invalidBase64
        case dataTooShort(expected: Int, actual: Int)
    }

    public struct Result: Decodable, Sendable {
        public let context: RPCContext
        public let value: AccountValue?
    }

    public static func request(
        address: String,
        commitment: String = "confirmed",
        minContextSlot: UInt64? = nil) -> JSONRPCRequest<Params>
    {
        JSONRPCRequest(
            method: "getAccountInfo",
            params: Params(address: address, commitment: commitment, minContextSlot: minContextSlot))
    }
}
