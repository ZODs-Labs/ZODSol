import Foundation

/// Composes the URL chain that `ImageLoader` walks after the primary URL
/// fails. Pure logic with no view or actor isolation so it stays trivially
/// testable. Order matters - the loader stops at the first success:
/// 1. IPFS gateway alternates derived from any CID we can spot. Helius's
///    image CDN routinely refuses to proxy `ipfs.io` / `cf-ipfs.com`
///    origins; trusted gateways reach the same content.
/// 2. Caller-supplied alternates from the mapping layer.
/// 3. The raw CDN-wrapped origin as a last resort.
enum AssetImageFallbacks {
    static func chain(url: URL, primary: URL, initial: [URL]) -> [URL] {
        var out: [URL] = []
        var seen: Set<String> = [primary.absoluteString]
        let ipfsSources = [primary, url] + initial
        for source in ipfsSources {
            for alt in IPFSGatewayFallback.alternates(for: source)
                where seen.insert(alt.absoluteString).inserted
            {
                out.append(alt)
            }
        }
        for alt in initial where seen.insert(alt.absoluteString).inserted {
            out.append(alt)
        }
        if let origin = HeliusCDNRewriter.origin(url),
           seen.insert(origin.absoluteString).inserted
        {
            out.append(origin)
        }
        return out
    }
}
