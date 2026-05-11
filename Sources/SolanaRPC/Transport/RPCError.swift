import Foundation

public enum RPCError: Error, Sendable, Equatable {
    case http(status: Int, retryAfter: Duration?)
    case transport(URLError.Code)
    case decoding(String)
    case rpc(JSONRPCError)
    case canceled
}
