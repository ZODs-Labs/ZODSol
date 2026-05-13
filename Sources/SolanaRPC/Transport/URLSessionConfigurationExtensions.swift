import Foundation

extension URLSessionConfiguration {
    public static func makeDefault(clientVersion: String? = nil) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 60
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpShouldUsePipelining = false
        c.httpMaximumConnectionsPerHost = 6
        var headers: [String: String] = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Accept-Encoding": "br,gzip,deflate",
        ]
        headers["Solana-Client"] = "zodsol/\(clientVersion ?? Self.bundleShortVersion)"
        c.httpAdditionalHeaders = headers
        return c
    }

    private static var bundleShortVersion: String {
        let info = Bundle.main.infoDictionary
        if let v = info?["CFBundleShortVersionString"] as? String { return v }
        return "0.0.0"
    }
}
