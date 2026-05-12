import Foundation
import XCTest
@testable import SolanaRPC

// MARK: - MockURLProtocol

/// URLProtocol subclass that delegates to a static handler so tests can stub responses
/// for any URLSession that registers this class. `@unchecked Sendable` is acceptable in
/// the test target ONLY — production code under Sources/SolanaRPC may not use it (H2).
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(self.request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Thread-safe counter helper

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    func increment() {
        self.lock.lock(); defer { lock.unlock() }
        self._value += 1
    }

    var value: Int {
        self.lock.lock(); defer { lock.unlock() }
        return self._value
    }
}

// MARK: - Tests

final class URLSessionTransportTests: XCTestCase {
    private let endpoint = URL(string: "https://test.example.com/")!

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeTransport(jitter: Double = 0.0, maxAttempts: Int = 3) -> URLSessionRPCTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSessionRPCTransport(
            endpoint: self.endpoint,
            configuration: config,
            retryPolicy: RetryPolicy(
                maxAttempts: maxAttempts,
                initialDelay: .milliseconds(10),
                maxDelay: .seconds(30),
                jitter: jitter))
    }

    private func makeHTTPResponse(status: Int, headers: [String: String] = [:], url: URL? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url ?? self.endpoint,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers)!
    }

    // MARK: - 1. success_200

    func test_success200_returnsDecodedResponse() async throws {
        let body = #"{"jsonrpc":"2.0","id":"test","result":42}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil)!,
                body)
        }

        let transport = self.makeTransport()
        let req = JSONRPCRequest(method: "getBalance", params: ["testWallet"], id: "test")
        let response = try await transport.send(req, responseType: JSONRPCResponse<Int>.self)
        XCTAssertEqual(response.result, 42)
        XCTAssertNil(response.error)
    }

    // MARK: - 2. retry_on_429

    func test_retryOn429_thenSuccess_makesExactlyTwoAttempts() async throws {
        let counter = Counter()
        let successBody = #"{"jsonrpc":"2.0","id":"test","result":7}"#.data(using: .utf8)!
        let endpoint = self.endpoint

        MockURLProtocol.requestHandler = { request in
            counter.increment()
            if counter.value == 1 {
                let resp = HTTPURLResponse(
                    url: request.url ?? endpoint,
                    statusCode: 429,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Retry-After": "1"])!
                return (resp, Data())
            } else {
                let resp = HTTPURLResponse(
                    url: request.url ?? endpoint,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil)!
                return (resp, successBody)
            }
        }

        let transport = self.makeTransport()
        let req = JSONRPCRequest(method: "getBalance", params: ["w"], id: "test")
        let response = try await transport.send(req, responseType: JSONRPCResponse<Int>.self)
        XCTAssertEqual(response.result, 7)
        XCTAssertEqual(counter.value, 2, "expected exactly 2 attempts (one 429 + one success)")
    }

    // MARK: - 3. five_xx_exhausted

    func test_fiveXXExhausted_throwsHTTPStatus500() async throws {
        let counter = Counter()
        let endpoint = self.endpoint
        MockURLProtocol.requestHandler = { request in
            counter.increment()
            let resp = HTTPURLResponse(
                url: request.url ?? endpoint,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (resp, Data())
        }

        let transport = self.makeTransport(maxAttempts: 2)
        let req = JSONRPCRequest(method: "getBalance", params: ["w"], id: "test")
        do {
            _ = try await transport.send(req, responseType: JSONRPCResponse<Int>.self)
            XCTFail("expected throw after exhausting retries")
        } catch let error as RPCError {
            XCTAssertEqual(error, .http(status: 500, retryAfter: nil))
            XCTAssertEqual(counter.value, 2, "expected exactly maxAttempts=2 calls")
        } catch {
            XCTFail("expected RPCError, got \(error)")
        }
    }

    // MARK: - 4. rpc_error_body

    func test_rpcErrorBody_unwrapThrowsRPCError() async throws {
        let body = #"""
        {"jsonrpc":"2.0","id":"x","error":{"code":-32600,"message":"Invalid Request","data":null}}
        """#.data(using: .utf8)!
        let endpoint = self.endpoint
        MockURLProtocol.requestHandler = { request in
            let resp = HTTPURLResponse(
                url: request.url ?? endpoint,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (resp, body)
        }

        let transport = self.makeTransport()
        let req = JSONRPCRequest(method: "noop", params: [String](), id: "x")
        let response = try await transport.send(req, responseType: JSONRPCResponse<Int>.self)
        XCTAssertNil(response.result)
        XCTAssertNotNil(response.error)

        XCTAssertThrowsError(try response.unwrap()) { error in
            guard let rpc = error as? RPCError else {
                XCTFail("expected RPCError, got \(error)")
                return
            }
            switch rpc {
            case let .rpc(inner):
                XCTAssertEqual(inner.code, -32600)
                XCTAssertEqual(inner.message, "Invalid Request")
            default:
                XCTFail("expected .rpc, got \(rpc)")
            }
        }
    }

    // MARK: - 5. malformed_json

    func test_malformedJSON_throwsRPCErrorDecoding() async throws {
        let endpoint = self.endpoint
        MockURLProtocol.requestHandler = { request in
            let resp = HTTPURLResponse(
                url: request.url ?? endpoint,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (resp, "not json".data(using: .utf8)!)
        }

        let transport = self.makeTransport()
        let req = JSONRPCRequest(method: "noop", params: [String](), id: "x")
        do {
            _ = try await transport.send(req, responseType: JSONRPCResponse<Int>.self)
            XCTFail("expected decode failure")
        } catch let error as RPCError {
            switch error {
            case .decoding:
                break
            default:
                XCTFail("expected .decoding, got \(error)")
            }
        } catch {
            XCTFail("expected RPCError.decoding, got \(error)")
        }
    }

    // MARK: - 6. auth_error

    // MARK: - 7. sendOnce bypasses retry on 5xx

    func test_sendOnce_doesNotRetryOn500() async throws {
        let counter = Counter()
        let endpoint = self.endpoint
        MockURLProtocol.requestHandler = { request in
            counter.increment()
            let resp = HTTPURLResponse(
                url: request.url ?? endpoint,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (resp, Data())
        }

        // Configure a normally-retrying transport, but call sendOnce.
        let transport = self.makeTransport(maxAttempts: 5)
        let req = JSONRPCRequest(method: "sendTransaction", params: [String](), id: "x")
        do {
            _ = try await transport.sendOnce(req, responseType: JSONRPCResponse<String>.self)
            XCTFail("expected 500 to throw")
        } catch let error as RPCError {
            XCTAssertEqual(error, .http(status: 500, retryAfter: nil))
            XCTAssertEqual(counter.value, 1, "sendOnce must do exactly one attempt regardless of policy")
        } catch {
            XCTFail("expected RPCError, got \(error)")
        }
    }

    func test_sendOnce_doesNotRetryOn429() async throws {
        let counter = Counter()
        let endpoint = self.endpoint
        MockURLProtocol.requestHandler = { request in
            counter.increment()
            let resp = HTTPURLResponse(
                url: request.url ?? endpoint,
                statusCode: 429,
                httpVersion: "HTTP/1.1",
                headerFields: ["Retry-After": "1"])!
            return (resp, Data())
        }

        let transport = self.makeTransport(maxAttempts: 5)
        let req = JSONRPCRequest(method: "sendTransaction", params: [String](), id: "x")
        do {
            _ = try await transport.sendOnce(req, responseType: JSONRPCResponse<String>.self)
            XCTFail("expected 429 to throw")
        } catch let error as RPCError {
            XCTAssertEqual(error, .http(status: 429, retryAfter: .seconds(1)))
            XCTAssertEqual(counter.value, 1, "sendOnce must not honor Retry-After")
        } catch {
            XCTFail("expected RPCError, got \(error)")
        }
    }

    // MARK: - 6. auth_error

    func test_auth401_throwsHTTPImmediatelyWithoutRetry() async throws {
        let counter = Counter()
        let endpoint = self.endpoint
        MockURLProtocol.requestHandler = { request in
            counter.increment()
            let resp = HTTPURLResponse(
                url: request.url ?? endpoint,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (resp, Data())
        }

        let transport = self.makeTransport()
        let req = JSONRPCRequest(method: "noop", params: [String](), id: "x")
        do {
            _ = try await transport.send(req, responseType: JSONRPCResponse<Int>.self)
            XCTFail("expected 401 to throw")
        } catch let error as RPCError {
            XCTAssertEqual(error, .http(status: 401, retryAfter: nil))
            XCTAssertEqual(counter.value, 1, "401 must not retry")
        } catch {
            XCTFail("expected RPCError, got \(error)")
        }
    }
}
