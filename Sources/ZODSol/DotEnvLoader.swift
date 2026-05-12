#if DEBUG
import Foundation
import OSLog

/// Debug-build helper that loads developer-time variables from a project-root
/// `.env` file into the process environment before any service reads it.
///
/// Necessary because Xcode's default SwiftPM scheme does not source shell
/// files, so secrets set in `.env` would otherwise not reach
/// `ProcessInfo.processInfo.environment`. The loader uses `setenv(_:_:0)`,
/// which never overwrites an already-set variable - explicit `export` from
/// a parent shell (or an Xcode scheme entry) always wins.
///
/// Excluded from release builds entirely via `#if DEBUG`.
enum DotEnvLoader {
    private static let logger = Logger(subsystem: "dev.zods.zodsol", category: "dotenv")

    /// Locates the repo-root `.env` (next to `Package.swift`), parses simple
    /// `KEY=VALUE` entries and applies them to the process environment.
    /// Silent no-op when the file is missing.
    static func applyToProcessEnvironment() {
        guard let url = self.projectRootDotEnv() else { return }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            self.logger.debug("dotenv \("read-failed", privacy: .public) at \(url.path, privacy: .public)")
            return
        }
        let entries = self.parse(content)
        var applied = 0
        for (key, value) in entries where setenv(key, value, 0) == 0 {
            applied += 1
        }
        self.logger.notice(
            "dotenv applied \(applied, privacy: .public)/\(entries.count, privacy: .public) from \(url.path, privacy: .public)")
    }

    /// Walks up from this source file's compile-time path looking for the
    /// first directory that holds both `Package.swift` and `.env`. Returns
    /// `nil` if neither pairing is found within a reasonable depth.
    private static func projectRootDotEnv() -> URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let env = dir.appendingPathComponent(".env")
            let pkg = dir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: pkg.path),
               FileManager.default.fileExists(atPath: env.path)
            {
                return env
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// Minimal `.env` parser. Supports `KEY=value`, optional `export ` prefix,
    /// `"double"` and `'single'` quoted values, blank lines and `#` comments.
    /// Does not interpolate, escape, or honor inline comments inside values.
    static func parse(_ content: String) -> [(String, String)] {
        var out: [(String, String)] = []
        for raw in content.split(whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let stripped = line.hasPrefix("export ")
                ? String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
                : line
            guard let eq = stripped.firstIndex(of: "=") else { continue }
            let key = String(stripped[..<eq]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
            var value = String(stripped[stripped.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2 {
                if value.first == "\"", value.last == "\"" {
                    value = String(value.dropFirst().dropLast())
                } else if value.first == "'", value.last == "'" {
                    value = String(value.dropFirst().dropLast())
                }
            }
            out.append((key, value))
        }
        return out
    }
}
#endif
