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

    /// An ephemeral, credential-free configuration for contacting keyless public
    /// hosts (the price ticker). Carries no cookies or credentials so it can
    /// never leak an API key, and times out fast so a hung socket cannot wedge a
    /// short polling tick.
    public static func makeCredentialFree() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.urlCredentialStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 8
        c.waitsForConnectivity = false
        return c
    }

    private static var bundleShortVersion: String {
        let info = Bundle.main.infoDictionary
        if let v = info?["CFBundleShortVersionString"] as? String { return v }
        return "0.0.0"
    }
}
