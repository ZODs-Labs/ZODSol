import Foundation

public struct JSONRPCError: Decodable, Sendable, Error, Equatable {
    public let code: Int
    public let message: String
    public let data: AnyJSON?

    public init(code: Int, message: String, data: AnyJSON? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}
