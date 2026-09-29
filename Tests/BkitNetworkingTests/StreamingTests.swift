import Foundation
import Testing
@testable import BkitNetworking

@Suite("Streaming and Server-Sent Events")
struct StreamingTests {
    private func collect<T>(_ stream: AsyncThrowingStream<T, any Error>) async throws -> [T] {
        var items: [T] = []
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
        // The id carries over; the event name and retry don't.
        _ = parser.consume(line: "data: next")
        #expect(parser.consume(line: "") == ServerSentEvent(data: "next", id: "7"))
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

    @Test func withoutATerminatorEverythingIsYielded() async throws {
        let transport = FakeTransport([.stream(status: 200, chunks: [json("data: [DONE]\n\ndata: more\n\n")])])
        let events = try await collect(HTTPClient(transport: transport, retry: .none).events(Endpoint(baseURL: api), terminator: nil))
        #expect(events.map(\.data) == ["[DONE]", "more"])
        #expect(events[0].isDone)
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

    @Test func aStreamErrorBodyIsCapped() async throws {
        let big = Data(repeating: 0x41, count: HTTPClient.streamErrorBodyLimit * 2)
        let transport = FakeTransport([.stream(status: 500, chunks: [big])])
        do {
            _ = try await collect(HTTPClient(transport: transport, retry: .none).lines(Endpoint(baseURL: api)))
            Issue.record("expected an error")
        } catch let error as NetworkError {
            guard case .http(500, let body, _) = error else {
                Issue.record("got \(error)")
                return
            }
            #expect(body.count == HTTPClient.streamErrorBodyLimit)
        }
    }
}
