import Foundation
import OSLog

/// Shared loggers, namespaced by subsystem so they show up correctly in Console.app
/// and `log stream`. Categories are added as new subsystems come online.
enum AppLog {
    private static let subsystem = "dev.zods.zodsol"

    static let app = Logger(subsystem: Self.subsystem, category: "app")
    static let panel = Logger(subsystem: Self.subsystem, category: "panel")
    static let statusItem = Logger(subsystem: Self.subsystem, category: "statusItem")
    static let wallet = Logger(subsystem: Self.subsystem, category: "wallet")
    static let rpc = Logger(subsystem: Self.subsystem, category: "rpc")
    static let helius = Logger(subsystem: Self.subsystem, category: "helius")
    static let keychain = Logger(subsystem: Self.subsystem, category: "keychain")
    static let cache = Logger(subsystem: Self.subsystem, category: "cache")
}
