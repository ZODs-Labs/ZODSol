import XCTest
@testable import DataProviders

final class EnvironmentKeySourceTests: XCTestCase {
    func test_returnsTrimmedValue_whenSet() {
        let source = EnvironmentKeySource(
            variableName: "ZODSOL_TEST_KEY",
            environment: { ["ZODSOL_TEST_KEY": "abc-123"] })
        XCTAssertEqual(source.value(), "abc-123")
    }

    func test_returnsNil_whenVariableMissing() {
        let source = EnvironmentKeySource(
            variableName: "ZODSOL_TEST_KEY",
            environment: { ["UNRELATED": "value"] })
        XCTAssertNil(source.value())
    }

    func test_returnsNil_whenEmptyString() {
        let source = EnvironmentKeySource(
            variableName: "ZODSOL_TEST_KEY",
            environment: { ["ZODSOL_TEST_KEY": ""] })
        XCTAssertNil(source.value())
    }

    func test_returnsNil_whenWhitespaceOnly() {
        let source = EnvironmentKeySource(
            variableName: "ZODSOL_TEST_KEY",
            environment: { ["ZODSOL_TEST_KEY": "   \n\t  "] })
        XCTAssertNil(source.value())
    }

    func test_trimsLeadingAndTrailingWhitespace() {
        let source = EnvironmentKeySource(
            variableName: "ZODSOL_TEST_KEY",
            environment: { ["ZODSOL_TEST_KEY": "  key-with-spaces  \n"] })
        XCTAssertEqual(source.value(), "key-with-spaces")
    }

    func test_preservesInternalCharacters() {
        let source = EnvironmentKeySource(
            variableName: "ZODSOL_TEST_KEY",
            environment: { ["ZODSOL_TEST_KEY": "abc def_ghi-123.456"] })
        XCTAssertEqual(source.value(), "abc def_ghi-123.456")
    }

    func test_namePropertyMatchesVariableName() {
        let source = EnvironmentKeySource(
            variableName: "ZODSOL_TEST_KEY",
            environment: { [:] })
        XCTAssertEqual(source.name, "ZODSOL_TEST_KEY")
    }

    func test_reevaluatesEnvironmentOnEachCall() {
        let storage = MutableEnvironment()
        let source = EnvironmentKeySource(
            variableName: "ZODSOL_TEST_KEY",
            environment: { storage.values })
        storage.set("ZODSOL_TEST_KEY", to: "first")
        XCTAssertEqual(source.value(), "first")
        storage.set("ZODSOL_TEST_KEY", to: "second")
        XCTAssertEqual(source.value(), "second")
        storage.clear()
        XCTAssertNil(source.value())
    }
}

private final class MutableEnvironment: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: String] = [:]

    var values: [String: String] {
        self.lock.lock(); defer { self.lock.unlock() }
        return self.stored
    }

    func set(_ key: String, to value: String) {
        self.lock.lock(); defer { self.lock.unlock() }
        self.stored[key] = value
    }

    func clear() {
        self.lock.lock(); defer { self.lock.unlock() }
        self.stored.removeAll()
    }
}
