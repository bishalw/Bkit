// The README's testing snippet, compiled and run.

import BkitNetworking
import Foundation
import Testing

struct CannedTransport: HTTPTransport {
    let status: Int
    let body: Data

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, any Error>, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        return (AsyncThrowingStream { continuation in
            data.forEach { continuation.yield($0) }
            continuation.finish()
        }, response)
    }
}

@Test func anUnavailableServerIsAnError() async throws {
    let client = HTTPClient(
        transport: CannedTransport(status: 503, body: Data()),
        retry: RetryPolicy(maxAttempts: 3, sleeper: .init { _ in })  // no real waiting
    )
    await #expect(throws: NetworkError.http(status: 503, body: Data(), url: try inbox.url())) {
        try await client.send(inbox)
    }
}
