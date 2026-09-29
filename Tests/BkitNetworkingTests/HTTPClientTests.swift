import Foundation
import Testing
@testable import BkitNetworking

@Suite("HTTPClient")
struct HTTPClientTests {
    struct Rate: Decodable, Sendable, Equatable {
        let quote: String
        let rate: Double
    }

    private func client(_ transport: FakeTransport, retry: RetryPolicy = .none, interceptors: [any RequestInterceptor] = [], logger: HTTPLogger? = nil)
        -> HTTPClient
    {
        HTTPClient(transport: transport, interceptors: interceptors, retry: retry, logger: logger)
    }

    // MARK: - Status and decoding

    @Test func a2xxBodyDecodes() async throws {
        let transport = FakeTransport([.response(status: 200, body: json(#"[{"quote":"NPR","rate":153.45}]"#))])
        let rates = try await client(transport).send(Endpoint(baseURL: api, path: "rates"), as: [Rate].self)
        #expect(rates == [Rate(quote: "NPR", rate: 153.45)])
        #expect(transport.requests.first?.url?.absoluteString == "https://api.example.com/rates")
    }

    @Test("a non-2xx answer throws with its status and body", arguments: [400, 404, 422, 500, 503])
    func non2xx(status: Int) async {
        let transport = FakeTransport([.response(status: status, body: json(#"{"error":"nope"}"#))])
        await #expect(throws: NetworkError.http(status: status, body: json(#"{"error":"nope"}"#), url: URL(string: "https://api.example.com/rates"))) {
            try await client(transport).send(Endpoint(baseURL: api, path: "rates"))
        }
    }

    /// `send` throws `NetworkError` itself, so a caller matches cases without casting — the
    /// README's example.
    @Test func typedThrowsLetsCallersMatchCases() async {
        let transport = FakeTransport([.response(status: 418, body: json("teapot"))])
        do {
            _ = try await client(transport).send(Endpoint(baseURL: api), as: [Rate].self)
            Issue.record("expected an error")
        } catch .http(let status, let body, _) {
            #expect(status == 418)
            #expect(body == json("teapot"))
        } catch {
            Issue.record("got \(error)")
        }
    }

    @Test func aBodyThatDoesntDecodeIsADecodingError() async {
        let transport = FakeTransport([.response(status: 200, body: json(#"{"quote":"NPR"}"#))])
        do {
            _ = try await client(transport).send(Endpoint(baseURL: api), as: Rate.self)
            Issue.record("expected a decoding error")
        } catch {
            guard case .decoding(let type, let underlying) = error else {
                Issue.record("got \(error)")
                return
            }
            #expect(type == "Rate")
            #expect(underlying.contains("rate"))
        }
    }

    @Test("URL errors map to what a screen acts on", arguments: [
        (URLError.Code.cancelled, NetworkError.cancelled),
        (.timedOut, .timedOut),
        (.notConnectedToInternet, .offline),
        (.networkConnectionLost, .offline),
        (.badServerResponse, .transport(URLError(.badServerResponse))),
    ])
    func urlErrors(code: URLError.Code, expected: NetworkError) async {
        let transport = FakeTransport([.failure(URLError(code))])
        await #expect(throws: expected) { try await client(transport).send(Endpoint(baseURL: api)) }
    }

    @Test func anInvalidURLIsNeverSent() async {
        let transport = FakeTransport([])
        await #expect(throws: NetworkError.invalidURL) { try await client(transport).send(Endpoint(baseURL: URL(string: "nohost")!)) }
        #expect(transport.requests.isEmpty)
    }

    // MARK: - Retrying

    @Test func a503IsRetriedAfterItsRetryAfter() async throws {
        let sleeper = RecordingSleeper()
        let transport = FakeTransport([
            .response(status: 503, headers: ["Retry-After": "2"]),
            .response(status: 503),
            .response(status: 200, body: json("[]")),
        ])
        let retry = RetryPolicy(maxAttempts: 3, baseDelay: .seconds(1), jitter: 0, sleeper: sleeper.sleeper)
        let rates = try await client(transport, retry: retry).send(Endpoint(baseURL: api), as: [Rate].self)
        #expect(rates.isEmpty)
        #expect(transport.requests.count == 3)
        // The server's 2 s first; then backoff for the second failure: 1 s × 2¹.
        #expect(sleeper.recorded == [.seconds(2), .seconds(2)])
    }

    @Test func backoffDoublesAndStopsAtMaxAttempts() async {
        let sleeper = RecordingSleeper()
        let transport = FakeTransport(Array(repeating: .response(status: 502), count: 5))
        let retry = RetryPolicy(maxAttempts: 4, baseDelay: .milliseconds(100), jitter: 0, sleeper: sleeper.sleeper)
        await #expect(throws: NetworkError.http(status: 502, body: Data(), url: api)) {
            try await client(transport, retry: retry).send(Endpoint(baseURL: api))
        }
        #expect(transport.requests.count == 4)
        #expect(sleeper.recorded == [.milliseconds(100), .milliseconds(200), .milliseconds(400)])
    }

    @Test func jitterSpreadsTheWait() {
        let low = RetryPolicy(baseDelay: .seconds(1), jitter: 0.2, random: { 0 })
        let high = RetryPolicy(baseDelay: .seconds(1), jitter: 0.2, random: { 0.999_999 })
        #expect(low.delay(afterAttempt: 1, retryAfter: nil) == .milliseconds(800))
        #expect(high.delay(afterAttempt: 1, retryAfter: nil) == .milliseconds(1200))
        #expect(RetryPolicy(baseDelay: .seconds(10), maxDelay: .seconds(15), jitter: 0).delay(afterAttempt: 3, retryAfter: nil) == .seconds(15))
    }

    @Test func aPostIsNotRetriedUnlessAllowed() async {
        let sleeper = RecordingSleeper()
        let transport = FakeTransport([.response(status: 503), .response(status: 200)])
        let retry = RetryPolicy(maxAttempts: 3, sleeper: sleeper.sleeper)
        await #expect(throws: NetworkError.self) { try await client(transport, retry: retry).send(Endpoint(.post, baseURL: api)) }
        #expect(transport.requests.count == 1)

        var allowed = retry
        allowed.retriesNonIdempotent = true
        let second = FakeTransport([.response(status: 503), .response(status: 200)])
        _ = try? await client(second, retry: allowed).send(Endpoint(.post, baseURL: api))
        #expect(second.requests.count == 2)
    }

    @Test func aClientErrorIsNotRetried() async {
        let transport = FakeTransport([.response(status: 404), .response(status: 200)])
        let retry = RetryPolicy(maxAttempts: 3, sleeper: RecordingSleeper().sleeper)
        await #expect(throws: NetworkError.self) { try await client(transport, retry: retry).send(Endpoint(baseURL: api)) }
        #expect(transport.requests.count == 1)
    }

    @Test func aTransientConnectionErrorIsRetriedButOfflineIsNot() async throws {
        let retry = RetryPolicy(maxAttempts: 2, jitter: 0, sleeper: RecordingSleeper().sleeper)
        let flaky = FakeTransport([.failure(URLError(.networkConnectionLost)), .response(status: 200)])
        await #expect(throws: NetworkError.offline) { try await client(flaky, retry: retry).send(Endpoint(baseURL: api)) }
        #expect(flaky.requests.count == 1)

        let dns = FakeTransport([.failure(URLError(.cannotFindHost)), .response(status: 200)])
        try await client(dns, retry: retry).send(Endpoint(baseURL: api))
        #expect(dns.requests.count == 2)
    }

    @Test func aRetryAfterLongerThanTheCapIsNotWaitedFor() async {
        let sleeper = RecordingSleeper()
        let transport = FakeTransport([.response(status: 429, headers: ["Retry-After": "3600"]), .response(status: 200)])
        let retry = RetryPolicy(maxAttempts: 3, maxRetryAfter: .seconds(60), sleeper: sleeper.sleeper)
        await #expect(throws: NetworkError.self) { try await client(transport, retry: retry).send(Endpoint(baseURL: api)) }
        #expect(transport.requests.count == 1)
        #expect(sleeper.recorded.isEmpty)
    }

    @Test func retryAfterReadsSecondsAndDates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RetryPolicy.retryAfter("120") == .seconds(120))
        #expect(RetryPolicy.retryAfter(" 5 ") == .seconds(5))
        let later = now.addingTimeInterval(30)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        #expect(RetryPolicy.retryAfter(formatter.string(from: later), now: now) == .seconds(30))
        #expect(RetryPolicy.retryAfter("soon") == nil)
        #expect(RetryPolicy.retryAfter(nil) == nil)
    }

    @Test func cancellingDuringAWaitStopsRetrying() async {
        let transport = FakeTransport(Array(repeating: .response(status: 503), count: 5))
        let started = AsyncStream<Void>.makeStream()
        let retry = RetryPolicy(
            maxAttempts: 5,
            sleeper: RetryPolicy.Sleeper { _ in
                started.continuation.yield()
                try await Task.sleep(for: .seconds(60))
            })
        let client = client(transport, retry: retry)
        let task = Task { try await client.send(Endpoint(baseURL: api)) }
        for await _ in started.stream { break }
        task.cancel()
        await #expect(throws: NetworkError.cancelled) { try await task.value }
        #expect(transport.requests.count == 1)
    }

    // MARK: - Interceptors

    struct Stamp: RequestInterceptor {
        let name: String
        func adapt(_ request: URLRequest) async throws -> URLRequest {
            var request = request
            let trail = request.value(forHTTPHeaderField: "X-Trail").map { $0 + "," } ?? ""
            request.setValue(trail + name, forHTTPHeaderField: "X-Trail")
            return request
        }
    }

    struct Refuse: RequestInterceptor {
        func adapt(_ request: URLRequest) async throws -> URLRequest { throw URLError(.userAuthenticationRequired) }
    }

    @Test func interceptorsRunInOrderOnEveryAttempt() async throws {
        let transport = FakeTransport([.response(status: 503), .response(status: 204)])
        let retry = RetryPolicy(maxAttempts: 2, sleeper: RecordingSleeper().sleeper)
        try await client(transport, retry: retry, interceptors: [Stamp(name: "auth"), Stamp(name: "attest")]).send(Endpoint(baseURL: api))
        #expect(transport.requests.map { $0.value(forHTTPHeaderField: "X-Trail") } == ["auth,attest", "auth,attest"])
    }

    @Test func anInterceptorThatThrowsStopsTheRequest() async {
        let transport = FakeTransport([.response(status: 200)])
        await #expect(throws: NetworkError.transport(URLError(.userAuthenticationRequired))) {
            try await client(transport, interceptors: [Refuse()]).send(Endpoint(baseURL: api))
        }
        #expect(transport.requests.isEmpty)
    }

    // MARK: - Logging

    @Test func loggingRedactsCredentialsAndLeavesBodiesOut() async throws {
        let sink = RecordingSink()
        let transport = FakeTransport([.response(status: 200, body: json(#"{"secret":"body"}"#), headers: ["Set-Cookie": "session=abc"])])
        let endpoint = Endpoint(
            .post, baseURL: api, path: "login", headers: ["Authorization": "Bearer t0ken", "cookie": "a=b", "Accept": "application/json"],
            body: .json(json(#"{"password":"hunter2"}"#)))
        try await client(transport, logger: HTTPLogger(sink: sink)).send(endpoint)
        let log = sink.written.joined(separator: "\n")
        #expect(log.contains("→ POST https://api.example.com/login"))
        #expect(log.contains("← 200"))
        #expect(log.contains("Authorization: <redacted>"))
        #expect(log.lowercased().contains("\ncookie: <redacted>") || log.lowercased().contains("  cookie: <redacted>"))
        #expect(log.contains("Set-Cookie: <redacted>"))
        #expect(log.contains("Accept: application/json"))
        for secret in ["t0ken", "a=b", "session=abc", "hunter2", "secret"] {
            #expect(!log.contains(secret), "\(secret)")
        }
    }

    @Test func queryValuesAreRedactedUnlessAllowed() async throws {
        let sink = RecordingSink()
        let transport = FakeTransport([.response(status: 200), .failure(URLError(.cannotFindHost))])
        let endpoint = Endpoint(
            baseURL: api, path: "notes",
            query: [
                URLQueryItem(name: "api_key", value: "s3cret"), URLQueryItem(name: "page", value: "2"),
                URLQueryItem(name: "q", value: "tax return"), URLQueryItem(name: "draft", value: nil),
            ])
        let logger = HTTPLogger(sink: sink, unredactedQueryItems: ["page"])
        try await client(transport, logger: logger).send(endpoint)
        _ = try? await client(transport, logger: logger).send(endpoint)
        let log = sink.written.joined(separator: "\n")
        let redacted = "https://api.example.com/notes?api_key=<redacted>&page=2&q=<redacted>&draft"
        #expect(log.contains("→ GET \(redacted)"))
        #expect(log.contains("← 200 GET \(redacted)"))
        #expect(log.contains("✕ GET \(redacted):"))
        for secret in ["s3cret", "tax", "return"] {
            #expect(!log.contains(secret), "\(secret)")
        }
    }

    @Test("a URL is logged with query values redacted", arguments: [
        ("https://api.example.com/v1/notes", "https://api.example.com/v1/notes"),
        ("https://api.example.com/notes?token=abc&page=3", "https://api.example.com/notes?token=<redacted>&page=3"),
        ("https://api.example.com/notes?a%20b=1&empty=&flag", "https://api.example.com/notes?a%20b=<redacted>&empty=<redacted>&flag"),
        ("https://api.example.com/cb?code=xyz#access_token=abc", "https://api.example.com/cb?code=<redacted>"),
        ("http://localhost:8080/notes?key=k", "http://localhost:8080/notes?key=<redacted>"),
    ])
    func loggedURL(url: String, expected: String) {
        #expect(HTTPLogger(sink: RecordingSink(), unredactedQueryItems: ["page"]).redacted(URL(string: url)) == expected)
    }

    @Test func bodiesAreLoggedOnlyWhenAskedFor() async throws {
        let sink = RecordingSink()
        let transport = FakeTransport([.response(status: 200, body: json("pong"))])
        try await client(transport, logger: HTTPLogger(sink: sink, includesBodies: true)).send(Endpoint(.post, baseURL: api, body: .json(json("ping"))))
        let log = sink.written.joined(separator: "\n")
        #expect(log.contains("ping") && log.contains("pong"))
    }
}
