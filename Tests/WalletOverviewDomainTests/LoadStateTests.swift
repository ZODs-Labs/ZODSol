import XCTest
@testable import WalletOverviewDomain

final class LoadStateTests: XCTestCase {

    func testIdleCase() {
        let state = LoadState<Int>.idle
        if case .idle = state { return }
        XCTFail("expected .idle")
    }

    func testLoadingCase() {
        let state = LoadState<Int>.loading
        if case .loading = state { return }
        XCTFail("expected .loading")
    }

    func testLoadedCase() {
        let date = Date(timeIntervalSince1970: 100)
        let state = LoadState<Int>.loaded(42, lastRefreshed: date)
        if case let .loaded(value, lastRefreshed: refreshed) = state {
            XCTAssertEqual(value, 42)
            XCTAssertEqual(refreshed, date)
            return
        }
        XCTFail("expected .loaded")
    }

    func testPartialCase() {
        let state = LoadState<String>.partial("data", error: .networkUnavailable)
        if case let .partial(value, error) = state {
            XCTAssertEqual(value, "data")
            XCTAssertEqual(error, .networkUnavailable)
            return
        }
        XCTFail("expected .partial")
    }

    func testFailedCase() {
        let state = LoadState<Int>.failed(.unauthorized)
        if case let .failed(error) = state {
            XCTAssertEqual(error, .unauthorized)
            return
        }
        XCTFail("expected .failed")
    }
}
