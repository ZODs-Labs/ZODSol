import Foundation

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
}
