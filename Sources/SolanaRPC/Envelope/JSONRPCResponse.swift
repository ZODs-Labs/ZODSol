import Foundation

public struct JSONRPCResponse<Result: Decodable & Sendable>: Decodable, Sendable {
    public let jsonrpc: String
    public let id: String
    public let result: Result?
    public let error: JSONRPCError?
}

extension JSONRPCResponse {
    public func unwrap() throws -> Result {
        if let error { throw RPCError.rpc(error) }
        guard let result else { throw RPCError.decoding("missing result and error") }
        return result
    }
}
