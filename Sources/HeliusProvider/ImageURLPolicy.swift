import Foundation

enum ImageURLPolicy {
    static let trustedHosts: Set<String> = [
        "cdn.helius-rpc.com",
        "arweave.net",
        "shdw-drive.genesysgo.net",
        "nftstorage.link",
        "metadata.degods.com",
        "metadata.y00ts.com",
        "shadow-drive.genesysgo.net",
        "image.solana.com",
        "img.fotofolio.xyz",
        "i.imgur.com",
        "imgur.com",
        "gateway.irys.xyz",
        "node1.irys.xyz",
        "node2.irys.xyz",
        "i.ibb.co",
        "ibb.co",
        "cf-ipfs.com",
        "dweb.link",
        "w3s.link",
        "4everland.io",
        "4everland.ipfs.io",
        "ipfs.fleek.co",
        "raw.githubusercontent.com",
    ]

    static let trustedSuffixes: [String] = [
        ".arweave.net",
        ".nftstorage.link",
        ".raydium.io",
        ".jup.ag",
        ".metaplex.com",
        ".helius-rpc.com",
        ".helius.dev",
        ".ipfs.dweb.link",
        ".ipfs.nftstorage.link",
        ".ipfs.w3s.link",
        ".ipfs.4everland.io",
        ".irys.xyz",
    ]

    static let blockedHostSubstrings: [String] = [
        "ipfs.io",
        "gateway.pinata.cloud",
        "cloudflare-ipfs.com",
    ]

    static func isPermitted(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if Self.isBlockedHost(host) { return false }
        if Self.isSuspiciousHost(host) { return false }
        if Self.trustedHosts.contains(host) { return true }
        for suffix in self.trustedSuffixes where host.hasSuffix(suffix) {
            return true
        }
        return false
    }

    private static func isBlockedHost(_ host: String) -> Bool {
        for needle in self.blockedHostSubstrings where host.contains(needle) {
            return true
        }
        return false
    }

    private static func isSuspiciousHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard let first = parts.first else { return true }
        let firstString = String(first)
        if firstString.allSatisfy(\.isNumber) { return true }
        let nonNumericCount = firstString.count(where: { !$0.isNumber })
        if firstString.count >= 8, nonNumericCount <= 2 { return true }
        return false
    }
}
