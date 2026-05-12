import XCTest

final class APIKeyLeakTests: XCTestCase {
    func test_apiKey_neverInSourceLogs() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testDir = thisFile.deletingLastPathComponent()
        let repoRoot = testDir.deletingLastPathComponent().deletingLastPathComponent()
        let sourcesDir = repoRoot.appendingPathComponent("Sources/HeliusProvider")

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sourcesDir, includingPropertiesForKeys: nil) else {
            XCTFail("Cannot enumerate Sources/HeliusProvider")
            return
        }

        var offendingLines: [String] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            for (i, line) in content.components(separatedBy: .newlines).enumerated() {
                let isLogLine = line.contains("Logger")
                    || line.contains("os_log")
                    || line.contains("print(")
                if isLogLine, line.contains("apiKey") {
                    offendingLines
                        .append("\(url.lastPathComponent):\(i + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(
            offendingLines.isEmpty,
            "API key referenced in log line(s):\n\(offendingLines.joined(separator: "\n"))")
    }
}
