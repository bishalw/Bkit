import Foundation

/// Sends `Endpoint`s: adapts each request through the interceptors, checks the status, retries
/// what `RetryPolicy` allows, decodes, and throws only `NetworkError`.
///
/// ```swift
/// let client = HTTPClient(retry: RetryPolicy(maxAttempts: 2))
/// let notes = try await client.send(endpoint, as: [Note].self)
/// ```
public final class HTTPClient: Sendable {
    /// How much of a non-2xx streaming response is kept in `NetworkError.http`'s body.
    public static let streamErrorBodyLimit = 64 * 1024

    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let interceptors: [any RequestInterceptor]
    private let retry: RetryPolicy
    private let logger: HTTPLogger?

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        decoder: JSONDecoder = JSONDecoder(),
        interceptors: [any RequestInterceptor] = [],
        retry: RetryPolicy = .default,
        logger: HTTPLogger? = nil
    ) {
        self.transport = transport
        self.decoder = decoder
        self.interceptors = interceptors
        self.retry = retry
        self.logger = logger
    }

    // MARK: - Requests

    /// The body of a 2xx response, decoded as `T`.
    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws(NetworkError) -> T {
        let (data, _) = try await send(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw .decoding(type: String(describing: T.self), underlying: String(describing: error))
        }
    }

    /// The raw 2xx response. Anything else throws `.http(status:headers:body:url:)` with the
    /// response's headers and body.
    @discardableResult
    public func send(_ endpoint: Endpoint) async throws(NetworkError) -> (Data, HTTPURLResponse) {
        let base = try endpoint.urlRequest()
        var attempt = 1
        while true {
            if Task.isCancelled { throw .cancelled }
            let request = try await adapt(base)
            logger?.request(request, attempt: attempt)
            let error: NetworkError
            var retryAfter: Duration?
            do {
                let (data, response) = try await transport.data(for: request)
                logger?.response(response, body: data, for: request)
                if (200..<300).contains(response.statusCode) { return (data, response) }
                error = .http(status: response.statusCode, headers: response.headerFields, body: data, url: response.url ?? request.url)
                retryAfter = RetryPolicy.retryAfter(response.value(forHTTPHeaderField: "Retry-After"))
            } catch let caught {
                error = NetworkError(caught)
                logger?.failure(error, for: request)
            }
            guard retry.shouldRetry(error, method: endpoint.method, attempt: attempt) else { throw error }
            if let retryAfter, retryAfter > retry.maxRetryAfter { throw error }
            do {
                try await retry.sleeper.sleep(retry.delay(afterAttempt: attempt, retryAfter: retryAfter))
            } catch {
                throw .cancelled
            }
            attempt += 1
        }
    }

    // MARK: - Streams

    /// The response body line by line (LF, CRLF or CR), as it arrives. Not retried: a stream
    /// that has started can't be replayed. A non-2xx response throws `.http` with its body,
    /// up to `streamErrorBodyLimit`.
    public func lines(_ endpoint: Endpoint) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let bytes = try await self.openStream(endpoint)
                    var splitter = LineSplitter()
                    for try await byte in bytes {
                        if let line = splitter.consume(byte) { continuation.yield(line) }
                    }
                    if let last = splitter.finish() { continuation.yield(last) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: NetworkError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Server-Sent Events from a `text/event-stream` response. Ends when the server closes the
    /// stream or — when `terminator` is set — at the event whose data equals it (`[DONE]` by
    /// default), which isn't yielded.
    public func events(_ endpoint: Endpoint, terminator: String? = "[DONE]") -> AsyncThrowingStream<ServerSentEvent, any Error> {
        var endpoint = endpoint
        if endpoint.headers.keys.contains(where: { $0.caseInsensitiveCompare("Accept") == .orderedSame }) == false {
            endpoint.headers["Accept"] = "text/event-stream"
        }
        let lines = lines(endpoint)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = ServerSentEventParser()
                    for try await line in lines {
                        guard let event = parser.consume(line: line) else { continue }
                        if let terminator, event.data == terminator { break }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func adapt(_ request: URLRequest) async throws(NetworkError) -> URLRequest {
        var request = request
        do {
            for interceptor in interceptors { request = try await interceptor.adapt(request) }
        } catch {
            throw NetworkError(error)
        }
        return request
    }

    private func openStream(_ endpoint: Endpoint) async throws -> AsyncThrowingStream<UInt8, any Error> {
        let request = try await adapt(try endpoint.urlRequest())
        logger?.request(request, attempt: 1)
        let (bytes, response) = try await transport.bytes(for: request)
        logger?.response(response, body: nil, for: request)
        guard (200..<300).contains(response.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= Self.streamErrorBodyLimit { break }
            }
            throw NetworkError.http(status: response.statusCode, headers: response.headerFields, body: body, url: response.url ?? request.url)
        }
        return bytes
    }
}
