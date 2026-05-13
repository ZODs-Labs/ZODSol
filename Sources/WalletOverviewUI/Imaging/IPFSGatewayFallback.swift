import Foundation

/// Generates alternate URLs at trusted IPFS gateways when a candidate URL
/// references an IPFS CID. Many tokens point their `uri` at `ipfs.io` or the
/// now-dead `cf-ipfs.com`; Helius's image CDN often refuses to proxy those
/// origins (HTTP 403/530). Swapping to `dweb.link`, `nftstorage.link` or
/// `w3s.link` (all already in `ImageURLPolicy.trustedSuffixes`) keeps the
/// asset reachable without bypassing the host allow list.
enum IPFSGatewayFallback {
    /// Path-style gateways. URLSession follows their 301 redirects to the
    /// subdomain form (`<cid>.ipfs.dweb.link`) automatically.
    static let gateways: [String] = [
        "https://dweb.link/ipfs/",
        "https://nftstorage.link/ipfs/",
        "https://w3s.link/ipfs/",
    ]

    /// Returns the same IPFS asset served by each trusted gateway. Empty when
    /// the input URL is not IPFS-flavored.
    static func alternates(for url: URL) -> [URL] {
        guard let parsed = self.parse(url) else { return [] }
        let tail = parsed.rest.isEmpty ? parsed.cid : "\(parsed.cid)/\(parsed.rest)"
        return self.gateways.compactMap { URL(string: $0 + tail) }
    }

    /// Visible for tests. Splits any URL that references a CID via either
    /// the path form (`/ipfs/<cid>/<rest>`) or the subdomain form
    /// (`<cid>.ipfs.<gateway>/<rest>`).
    static func parse(_ url: URL) -> (cid: String, rest: String)? {
        let absolute = url.absoluteString
        if let range = absolute.range(of: "/ipfs/") {
            var tail = String(absolute[range.upperBound...])
            if let q = tail.firstIndex(of: "?") { tail = String(tail[..<q]) }
            if let h = tail.firstIndex(of: "#") { tail = String(tail[..<h]) }
            let parts = tail.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard let head = parts.first, !head.isEmpty else { return nil }
            let cid = String(head)
            let rest = parts.count > 1 ? String(parts[1]) : ""
            return (cid, rest)
        }
        if let host = url.host, let r = host.range(of: ".ipfs.") {
            let cid = String(host[..<r.lowerBound])
            guard !cid.isEmpty else { return nil }
            var path = url.path
            if path.hasPrefix("/") { path.removeFirst() }
            return (cid, path)
        }
        return nil
    }
}
