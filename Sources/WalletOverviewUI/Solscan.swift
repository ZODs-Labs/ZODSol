import AppKit
import Foundation
import SolanaKit

/// Solscan deep-link builders + a one-liner for opening them.
///
/// Solscan is the canonical Solana mainnet block explorer; "View on Solscan"
/// is the affordance Mac users expect from a portfolio row, equivalent to
/// Finder's "Show in" reveal. Centralising the URL shape here keeps the
/// views free of stringly-typed URLs and gives a single place to swap the
/// explorer if a user preference is ever added.
enum Solscan {
    static func token(mint: String) -> URL {
        URL(string: "https://solscan.io/token/\(mint)")!
    }

    static func account(address: String) -> URL {
        URL(string: "https://solscan.io/account/\(address)")!
    }

    /// Account page anchored at the collectibles tab.
    static func nfts(address: String) -> URL {
        URL(string: "https://solscan.io/account/\(address)#collectibles")!
    }

    /// Transaction page for a base58 signature on the given cluster.
    static func transaction(signature: String, network: SolanaNetwork) -> URL {
        let cluster = switch network {
        case .mainnet: ""
        case .devnet: "?cluster=devnet"
        case .testnet: "?cluster=testnet"
        }
        return URL(string: "https://solscan.io/tx/\(signature)\(cluster)")!
    }

    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// Pasteboard helper for copy-address / copy-mint context-menu actions.
enum WalletPasteboard {
    @MainActor
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
