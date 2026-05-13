import Foundation

/// Helius's image CDN is a thin wrapper over Cloudflare's `cdn-cgi/image`
/// resizer. Helius hands us URLs with an empty options slot - the literal
/// `cdn-cgi/image//https://origin/...` - which keeps the cache key tied to
/// the full origin image. We rewrite those to inject a pixel width and a
/// quality/format hint so requests for a 22pt row do not pull a 1024px PNG.
enum HeliusCDNRewriter {
    private static let host = "cdn.helius-rpc.com"
    private static let marker = "/cdn-cgi/image/"

    /// Returns a URL with options filled in, or `nil` if the input is not a
    /// rewritable Helius CDN URL.
    static func optimized(_ url: URL, pixelWidth: Int) -> URL? {
        guard let host = url.host?.lowercased(), host == Self.host else { return nil }
        let absolute = url.absoluteString
        guard let markerRange = absolute.range(of: Self.marker) else { return nil }
        let afterMarker = absolute[markerRange.upperBound...]
        guard let nextSlash = afterMarker.firstIndex(of: "/") else { return nil }
        let originStart = afterMarker.index(after: nextSlash)
        guard originStart < afterMarker.endIndex else { return nil }
        let origin = String(afterMarker[originStart...])
        let prefix = String(absolute[..<markerRange.upperBound])
        let options = "width=\(pixelWidth),quality=85,format=auto,fit=cover"
        return URL(string: "\(prefix)\(options)/\(origin)")
    }

    /// Returns the raw origin URL inside a Helius CDN wrapper. Useful as a
    /// last-resort fallback when the CDN itself is returning 5xx (origin
    /// reachable but Cloudflare resize worker failed).
    static func origin(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(), host == Self.host else { return nil }
        let absolute = url.absoluteString
        guard let markerRange = absolute.range(of: Self.marker) else { return nil }
        let afterMarker = absolute[markerRange.upperBound...]
        guard let nextSlash = afterMarker.firstIndex(of: "/") else { return nil }
        let originStart = afterMarker.index(after: nextSlash)
        guard originStart < afterMarker.endIndex else { return nil }
        let origin = String(afterMarker[originStart...])
        guard origin.hasPrefix("https://") || origin.hasPrefix("http://") else { return nil }
        return URL(string: origin)
    }
}
