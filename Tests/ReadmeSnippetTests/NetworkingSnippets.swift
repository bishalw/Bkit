// The README's networking snippets, compiled. ReadmeTests fails if the README's text and
// these drift apart: edit both together.

import BkitNetworking
import Foundation

struct Note: Decodable, Sendable {
    let id: Int
    let title: String
}

let client = HTTPClient(retry: RetryPolicy(maxAttempts: 2))

let inbox = Endpoint(
    .get,
    baseURL: URL(string: "https://api.example.com")!,
    path: "/v1/notes",                                   // joined with exactly one "/"
    query: [URLQueryItem(name: "folder", value: "inbox")] // percent-encoded, "+" included
)

enum InboxState {
    case notes([Note])
    case empty
    case offline
    case failed(NetworkError)
}

func loadInbox() async -> InboxState {
    do {
        return .notes(try await client.send(inbox, as: [Note].self))
    } catch .http(404, _, _, _) {
        return .empty           // any non-2xx: match its status, headers or body
    } catch .offline {
        return .offline         // no connection: show it, don't retry in a loop
    } catch {
        return .failed(error)   // .http, .timedOut, .cancelled, .decoding, .transport, .invalidURL
    }
}

struct BearerToken: RequestInterceptor {
    let token: @Sendable () async throws -> String

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        return request
    }
}

func follow(_ feed: Endpoint, with client: HTTPClient) async throws {
    var feed = feed
    while !Task.isCancelled {
        let stream = client.events(feed, terminator: nil)
        for try await event in stream {
            print(event.event ?? "message", event.data)
        }
        // The server closed the stream: come back where it says, when it says.
        if let id = stream.lastEventID, !id.isEmpty { feed.headers["Last-Event-ID"] = id }
        try await Task.sleep(for: .milliseconds(stream.reconnectionTime ?? 3000))
    }
}
