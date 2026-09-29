import Foundation

/// What actually moves bytes. `URLSessionTransport` in apps; a fake in tests, so a client's
/// requests and its handling of every answer can be checked without a network.
public protocol HTTPTransport: Sendable {
    /// The whole response. Throws only for failures to get one; any status is an answer.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// The response head, then the body as it arrives.
    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, any Error>, HTTPURLResponse)
}

/// `URLSession` as a transport.
public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        return (data, try Self.http(response))
    }

    public func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, any Error>, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        let http = try Self.http(response)
        let stream = AsyncThrowingStream<UInt8, any Error> { continuation in
            let task = Task {
                do {
                    for try await byte in bytes { continuation.yield(byte) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (stream, http)
    }

    private static func http(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return http
    }
}

/// Adapts every request before it's sent — an `Authorization` header, an App Attest assertion,
/// a request id. Interceptors run in the order given to `HTTPClient`, on every attempt, so a
/// retry gets a fresh token. Throwing stops the request.
public protocol RequestInterceptor: Sendable {
    func adapt(_ request: URLRequest) async throws -> URLRequest
}
