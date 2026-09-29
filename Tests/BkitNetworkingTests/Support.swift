import Foundation
@testable import BkitNetworking

/// A transport that answers from a script and records every request it got.
final class FakeTransport: HTTPTransport {
    enum Answer: Sendable {
        case response(status: Int, body: Data = Data(), headers: [String: String] = [:])
        case failure(URLError)
        /// A streamed body, delivered in these chunks.
        case stream(status: Int, chunks: [Data], headers: [String: String] = [:])
    }

    private let state: Locked<(answers: [Answer], requests: [URLRequest])>

    init(_ answers: [Answer]) {
        state = Locked((answers, []))
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    private func next(_ request: URLRequest) -> Answer {
        state.withLock { state in
            state.requests.append(request)
            return state.answers.isEmpty ? .failure(URLError(.resourceUnavailable)) : state.answers.removeFirst()
        }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        switch next(request) {
        case .response(let status, let body, let headers): return (body, Self.response(request, status, headers))
        case .failure(let error): throw error
        case .stream(let status, let chunks, let headers): return (chunks.reduce(Data(), +), Self.response(request, status, headers))
        }
    }

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, any Error>, HTTPURLResponse) {
        let answer = next(request)
        let (status, chunks, headers): (Int, [Data], [String: String])
        switch answer {
        case .response(let code, let body, let fields): (status, chunks, headers) = (code, [body], fields)
        case .failure(let error): throw error
        case .stream(let code, let parts, let fields): (status, chunks, headers) = (code, parts, fields)
        }
        let stream = AsyncThrowingStream<UInt8, any Error> { continuation in
            for chunk in chunks {
                for byte in chunk { continuation.yield(byte) }
            }
            continuation.finish()
        }
        return (stream, Self.response(request, status, headers))
    }

    private static func response(_ request: URLRequest, _ status: Int, _ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

/// Records the waits a retry asks for instead of waiting.
final class RecordingSleeper: Sendable {
    private let waits = Locked<[Duration]>([])
    var recorded: [Duration] { waits.withLock { $0 } }

    var sleeper: RetryPolicy.Sleeper {
        RetryPolicy.Sleeper { [waits] duration in
            try Task.checkCancellation()
            waits.withLock { $0.append(duration) }
        }
    }
}

final class RecordingSink: HTTPLogSink {
    private let lines = Locked<[String]>([])
    var written: [String] { lines.withLock { $0 } }
    func write(_ line: String) { lines.withLock { $0.append(line) } }
}

/// A value behind a lock (`Mutex` needs macOS 15; the package supports 13).
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

let api = URL(string: "https://api.example.com")!

func json(_ text: String) -> Data { Data(text.utf8) }
