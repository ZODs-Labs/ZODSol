import Foundation
import OSLog

/// File-backed storage for the Helius API key. Lives at
/// `~/Library/Application Support/ZODSol/credentials.json` (file mode `0600`,
/// directory mode `0700`).
///
/// Replaces the previous Keychain backing so ad-hoc-signed builds do not
/// trigger legacy login-keychain ACL dialogs on every release update. The key
/// is medium-sensitivity (an RPC quota credential, not money), so file mode
/// `0600` matches the convention used by `gh`, `aws`, `gcloud`, `npm`, etc.
public enum ApplicationSupportKeyStoreError: LocalizedError, Equatable {
    case encoding
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .encoding:
            "Could not encode the API key for storage."
        case let .io(message):
            "Could not write the API key to Application Support: \(message)"
        }
    }
}

struct CredentialsFile: Codable {
    let heliusApiKey: String

    enum CodingKeys: String, CodingKey {
        case heliusApiKey = "helius_api_key"
    }
}

public actor ApplicationSupportKeyStore {
    public typealias WriteError = ApplicationSupportKeyStoreError

    private let fileURL: URL
    private let directoryURL: URL
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "creds-file")

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.directoryURL = fileURL.deletingLastPathComponent()
    }

    /// `~/Library/Application Support/<folder>/credentials.json`. Throws if
    /// the user has somehow disabled Application Support resolution.
    public static func defaultFileURL(folder: String = "ZODSol") throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        return base
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("credentials.json", isDirectory: false)
    }

    public func read() -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let payload = try? JSONDecoder().decode(CredentialsFile.self, from: data) else { return nil }
        let trimmed = payload.heliusApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func write(heliusKey: String) throws {
        let trimmed = heliusKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = CredentialsFile(heliusApiKey: trimmed)
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            throw WriteError.encoding
        }
        do {
            try self.ensureDirectory()
            try self.writeAtomic(data: data)
        } catch let error as WriteError {
            throw error
        } catch {
            throw WriteError.io(String(describing: error))
        }
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                try FileManager.default.removeItem(at: self.fileURL)
            } catch {
                throw WriteError.io(String(describing: error))
            }
        }
    }

    public func fileExists() -> Bool {
        FileManager.default.fileExists(atPath: self.fileURL.path)
    }

    // MARK: - Private

    private func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: self.directoryURL.path) {
            try fm.createDirectory(
                at: self.directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))])
        } else {
            // Tighten permissions on an existing directory just in case it
            // was created by a different process with looser defaults.
            try? fm.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: self.directoryURL.path)
        }
    }

    private func writeAtomic(data: Data) throws {
        let fm = FileManager.default
        let temp = self.directoryURL.appendingPathComponent(".credentials.tmp.\(UUID().uuidString)")
        do {
            try data.write(to: temp, options: [.atomic])
            try fm.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: temp.path)
            if fm.fileExists(atPath: self.fileURL.path) {
                _ = try fm.replaceItemAt(self.fileURL, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: self.fileURL)
            }
            // Ensure final file permissions even when replaceItemAt copied
            // the destination's attributes.
            try? fm.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: self.fileURL.path)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}
