import Foundation
import Testing
@testable import BkitNetworking

@Suite("Streaming and Server-Sent Events")
struct StreamingTests {
    private func collect<S: AsyncSequence>(_ stream: S) async throws -> [S.Element] {
        var items: [S.Element] = []
        for try await item in stream { items.append(item) }
        return items
    }

    // MARK: - Parser

    @Test func multiLineDataJoinsWithNewlines() {
        var parser = ServerSentEventParser()
        #expect(parser.consume(line: "data: first") == nil)
        #expect(parser.consume(line: "data:second") == nil)
        #expect(parser.consume(line: "data:  indented") == nil)
        #expect(parser.consume(line: "") == ServerSentEvent(data: "first\nsecond\n indented"))
    }

    @Test func eventNamesIDsAndRetry() {
        var parser = ServerSentEventParser()
        for line in ["event: delta", "id: 7", "retry: 3000", "data: {}"] { _ = parser.consume(line: line) }
        #expect(parser.consume(line: "") == ServerSentEvent(event: "delta", data: "{}", id: "7", retry: 3000))
        // The id and the reconnection time are the stream's, so they carry over; the name doesn't.
        _ = parser.consume(line: "data: next")
        #expect(parser.consume(line: "") == ServerSentEvent(data: "next", id: "7", retry: 3000))
        #expect(parser.lastEventID == "7")
    }

    @Test func aRetryWithoutDataStillSetsTheReconnectionTime() {
        var parser = ServerSentEventParser()
        #expect(parser.reconnectionTime == nil)
        #expect(parser.consume(line: "retry: 5000") == nil)
        // Takes effect as soon as it arrives, before the block ends.
        #expect(parser.reconnectionTime == 5000)
        // A block with no data dispatches nothing, but the setting stays.
        #expect(parser.consume(line: "") == nil)
        #expect(parser.reconnectionTime == 5000)
        _ = parser.consume(line: "data: x")
        #expect(parser.consume(line: "") == ServerSentEvent(data: "x", retry: 5000))
    }

    @Test("a retry that isn't only ASCII digits is ignored", arguments: ["-1", "+5", "  5", "5s", "", "٥", "99999999999999999999999"])
    func invalidRetry(value: String) {
        var parser = ServerSentEventParser()
        _ = parser.consume(line: "retry: 1000")
        _ = parser.consume(line: "retry:" + value)
        #expect(parser.reconnectionTime == 1000)
    }

    @Test func aByteOrderMarkIsStrippedAtTheStartOfTheStreamOnly() {
        var parser = ServerSentEventParser()
        _ = parser.consume(line: "\u{FEFF}data: first")
        #expect(parser.consume(line: "") == ServerSentEvent(data: "first"))
        // Later, U+FEFF is part of the field name, so the line is an unknown field.
        _ = parser.consume(line: "\u{FEFF}data: second")
        #expect(parser.consume(line: "") == nil)
    }

    @Test func anEmptyEventNameMeansTheDefault() {
        var parser = ServerSentEventParser()
        _ = parser.consume(line: "event:")
        _ = parser.consume(line: "data: x")
        #expect(parser.consume(line: "") == ServerSentEvent(data: "x"))
        // And it replaces a name set earlier in the same block.
        for line in ["event: delta", "event", "data: y"] { _ = parser.consume(line: line) }
        #expect(parser.consume(line: "")?.event == nil)
    }

    @Test func commentsAndEmptyEventsAreSkipped() {
        var parser = ServerSentEventParser()
        #expect(parser.consume(line: ": keep-alive") == nil)
        #expect(parser.consume(line: "") == nil)
        #expect(parser.consume(line: "event: ping") == nil)
        #expect(parser.consume(line: "") == nil)
        #expect(parser.consume(line: "data") == nil)
        #expect(parser.consume(line: "") == ServerSentEvent(data: ""))
    }

    @Test func linesSplitAtLFCRLFAndCR() {
        var splitter = LineSplitter()
        var lines: [String] = []
        for byte in Array("one\ntwo\r\nthree\rfour".utf8) {
            if let line = splitter.consume(byte) { lines.append(line) }
        }
        if let last = splitter.finish() { lines.append(last) }
        #expect(lines == ["one", "two", "three", "four"])
    }

    // MARK: - Through the client

    @Test func eventsArriveAcrossChunksAndStopAtDone() async throws {
        let body = "event: delta\ndata: {\"text\":\"Hel\ndata: lo\"}\n\n: ping\n\ndata: 🇳🇵\n\ndata: [DONE]\n\ndata: after\n\n"
        let bytes = Array(body.utf8)
        // Chunks that cut through a field name, a CRLF-free boundary and the flag's UTF-8.
        let chunks = stride(from: 0, to: bytes.count, by: 5).map { Data(bytes[$0..<min($0 + 5, bytes.count)]) }
        let transport = FakeTransport([.stream(status: 200, chunks: chunks)])
        let events = try await collect(HTTPClient(transport: transport, retry: .none).events(Endpoint(baseURL: api, path: "stream")))
        #expect(events == [ServerSentEvent(event: "delta", data: "{\"text\":\"Hel\nlo\"}"), ServerSentEvent(data: "🇳🇵")])
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }

    @Test func aBOMAndACRLFSplitAcrossChunksArriveWhole() async throws {
        let chunks = [Data([0xEF, 0xBB]), Data([0xBF]) + json("data: a\r"), json("\n\r"), json("\ndata: b\r\n\r\n")]
        let transport = FakeTransport([.stream(status: 200, chunks: chunks)])
        let events = try await collect(HTTPClient(transport: transport, retry: .none).events(Endpoint(baseURL: api)))
        #expect(events == [ServerSentEvent(data: "a"), ServerSentEvent(data: "b")])
    }

    @Test func aCRLFSplitAcrossChunksIsOneLineBreak() async throws {
        let transport = FakeTransport([.stream(status: 200, chunks: [json("a\r"), json("\nb\r"), json("\n"), json("\rc")])])
        #expect(try await collect(HTTPClient(transport: transport, retry: .none).lines(Endpoint(baseURL: api))) == ["a", "b", "", "c"])
    }

    /// A block with no data dispatches no event, so the stream itself says what the last
    /// blocks set: a client reconnects with them after the server closes.
    @Test func theStreamKeepsTheReconnectionSettingsATrailingBlockSets() async throws {
        let body = "id: 1\ndata: a\n\nretry: 9000\nid: 42\n\n"
        let transport = FakeTransport([.stream(status: 200, chunks: [json(body)])])
        let stream = HTTPClient(transport: transport, retry: .none).events(Endpoint(baseURL: api))
        #expect(try await collect(stream) == [ServerSentEvent(data: "a", id: "1")])
        #expect(stream.lastEventID == "42")
        #expect(stream.reconnectionTime == 9000)
    }

    @Test func atTheTerminatorTheStreamKeepsWhatCameBeforeIt() async throws {
        let body = "retry: 100\ndata: [DONE]\n\nretry: 200\nid: later\n\n"
        let transport = FakeTransport([.stream(status: 200, chunks: [json(body)])])
        let stream = HTTPClient(transport: transport, retry: .none).events(Endpoint(baseURL: api))
        #expect(try await collect(stream).isEmpty)
        #expect(stream.reconnectionTime == 100)
        #expect(stream.lastEventID == nil)
    }

    @Test func withoutATerminatorEverythingIsYielded() async throws {
        let transport = FakeTransport([.stream(status: 200, chunks: [json("data: [DONE]\n\ndata: more\n\n")])])
        let events = try await collect(HTTPClient(transport: transport, retry: .none).events(Endpoint(baseURL: api), terminator: nil))
        #expect(events.map(\.data) == ["[DONE]", "more"])
    }

    @Test func anEventDecodesItsJSON() throws {
        struct Delta: Decodable, Equatable { let text: String }
        #expect(try ServerSentEvent(data: #"{"text":"hi"}"#).decode(Delta.self) == Delta(text: "hi"))
        #expect(throws: NetworkError.self) { try ServerSentEvent(data: "nope").decode(Delta.self) }
    }

    @Test func linesYieldTheLastLineWithoutANewline() async throws {
        let transport = FakeTransport([.stream(status: 200, chunks: [json("a\r\nb"), json("c\nd")])])
        #expect(try await collect(HTTPClient(transport: transport, retry: .none).lines(Endpoint(baseURL: api))) == ["a", "bc", "d"])
    }

    @Test func aNon2xxStreamThrowsWithItsBody() async {
        let transport = FakeTransport([.stream(status: 429, chunks: [json(#"{"error":"slow down"}"#)])])
        await #expect(throws: NetworkError.http(status: 429, body: json(#"{"error":"slow down"}"#), url: api)) {
            _ = try await collect(HTTPClient(transport: transport, retry: .none).events(Endpoint(baseURL: api)))
        }
    }

    @Test func aNon2xxStreamCarriesTheResponseHeaders() async {
        let transport = FakeTransport([.stream(status: 503, chunks: [json("busy")], headers: ["Retry-After": "7"])])
        await #expect(throws: NetworkError.http(status: 503, headers: ["Retry-After": "7"], body: json("busy"), url: api)) {
            _ = try await collect(HTTPClient(transport: transport, retry: .none).lines(Endpoint(baseURL: api)))
        }
    }

    @Test func aStreamErrorBodyIsCapped() async throws {
        let big = Data(repeating: 0x41, count: HTTPClient.streamErrorBodyLimit * 2)
        let transport = FakeTransport([.stream(status: 500, chunks: [big])])
        do {
            _ = try await collect(HTTPClient(transport: transport, retry: .none).lines(Endpoint(baseURL: api)))
            Issue.record("expected an error")
        } catch let error as NetworkError {
            guard case .http(500, _, let body, _) = error else {
                Issue.record("got \(error)")
                return
            }
            #expect(body.count == HTTPClient.streamErrorBodyLimit)
        }
    }
}
