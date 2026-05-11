import Foundation

public extension URLSessionConfiguration {
    static func makeDefault() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 30
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpAdditionalHeaders = ["Accept": "application/json", "Content-Type": "application/json"]
        return c
    }
}
