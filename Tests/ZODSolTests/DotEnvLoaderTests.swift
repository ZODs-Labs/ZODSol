#if DEBUG
import XCTest
@testable import ZODSol

final class DotEnvLoaderTests: XCTestCase {
    func test_parsesSimpleKeyValue() {
        let parsed = DotEnvLoader.parse("FOO=bar")
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].0, "FOO")
        XCTAssertEqual(parsed[0].1, "bar")
    }

    func test_skipsBlankLinesAndComments() {
        let content = """

        # this is a comment
        FOO=bar

        # another
        BAZ=qux
        """
        let parsed = DotEnvLoader.parse(content)
        XCTAssertEqual(parsed.map(\.0), ["FOO", "BAZ"])
        XCTAssertEqual(parsed.map(\.1), ["bar", "qux"])
    }

    func test_stripsExportPrefix() {
        let parsed = DotEnvLoader.parse("export FOO=bar")
        XCTAssertEqual(parsed.first?.0, "FOO")
        XCTAssertEqual(parsed.first?.1, "bar")
    }

    func test_stripsDoubleQuotes() {
        let parsed = DotEnvLoader.parse(#"FOO="hello world""#)
        XCTAssertEqual(parsed.first?.1, "hello world")
    }

    func test_stripsSingleQuotes() {
        let parsed = DotEnvLoader.parse("FOO='hello world'")
        XCTAssertEqual(parsed.first?.1, "hello world")
    }

    func test_preservesEqualsInsideValue() {
        let parsed = DotEnvLoader.parse("URL=https://example.com/path?q=1")
        XCTAssertEqual(parsed.first?.1, "https://example.com/path?q=1")
    }

    func test_skipsMalformedKeys() {
        let parsed = DotEnvLoader.parse("=novalue\nbad key=x\nGOOD=y")
        XCTAssertEqual(parsed.map(\.0), ["GOOD"])
    }

    func test_skipsLineWithoutEquals() {
        let parsed = DotEnvLoader.parse("noEqualsHere\nFOO=bar")
        XCTAssertEqual(parsed.map(\.0), ["FOO"])
    }

    func test_acceptsAlphanumericAndUnderscoreInKey() {
        let parsed = DotEnvLoader.parse("ZODSOL_HELIUS_API_KEY=abc123\nA1_B2=ok")
        XCTAssertEqual(parsed.map(\.0), ["ZODSOL_HELIUS_API_KEY", "A1_B2"])
    }

    func test_trimsSurroundingWhitespaceAroundKeyAndValue() {
        let parsed = DotEnvLoader.parse("  FOO  =  bar  ")
        XCTAssertEqual(parsed.first?.0, "FOO")
        XCTAssertEqual(parsed.first?.1, "bar")
    }

    func test_emptyValueAllowed() {
        let parsed = DotEnvLoader.parse("EMPTY=")
        XCTAssertEqual(parsed.first?.0, "EMPTY")
        XCTAssertEqual(parsed.first?.1, "")
    }
}
#endif
