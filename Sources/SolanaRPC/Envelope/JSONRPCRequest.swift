import Foundation
import Kit

public struct JSONRPCRequest<Params: Encodable & Sendable>: Encodable, Sendable {
    public let jsonrpc: String
    public let id: String
    public let method: String
    public let params: Params

    public init(method: String, params: Params, id: String = UUID().uuidString) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    public func kitPayload() throws -> RpcJsonValue {
        let params = try self.kitParams()
        return Kit.RpcMessage(id: self.id, method: self.method, params: params).jsonValue
    }

    public func kitParams() throws -> RpcJsonValue {
        let data = try JSONEncoder().encode(self.params)
        guard let json = String(data: data, encoding: .utf8) else {
            throw RPCError.decoding("invalid request utf8")
        }
        return try Kit.parseJsonWithBigInts(json)
    }

    public func encodedBodyData() throws -> Data {
        let json = try Kit.stringifyJsonWithBigInts(self.kitPayload())
        return Data(json.utf8)
    }

    public func deduplicationKey() throws -> String? {
        try Kit.getSolanaRpcPayloadDeduplicationKey(self.kitPayload())
    }
}
