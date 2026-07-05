import Foundation

enum FixtureLoader {
    static func load(_ name: String) throws -> Data {
        let thisFile = URL(fileURLWithPath: #filePath)
        let fixturesDir = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let url = fixturesDir.appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
}
