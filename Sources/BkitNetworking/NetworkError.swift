import Foundation

/// Everything `HTTPClient` throws. The URL-loading system's errors are folded into the few
/// cases a screen acts on differently — offline, timed out, cancelled — and kept whole in
/// `transport` otherwise.
public enum NetworkError: Error, Sendable, Equatable, LocalizedError {
    /// The endpoint doesn't make a valid URL (no scheme or host).
    case invalidURL
    /// The task was cancelled, or a retry was waiting when it was.
    case cancelled
    case timedOut
    /// No connection, or it dropped mid-request.
    case offline
    /// The server answered outside 2xx. `body` is what it sent (capped for streams).
    case http(status: Int, body: Data, url: URL?)
    /// A 2xx body that didn't decode as `type`. `underlying` describes the `DecodingError`.
    case decoding(type: String, underlying: String)
    /// Any other URL-loading failure.
    case transport(URLError)

    /// Maps whatever a transport, interceptor or sleep threw.
    public init(_ error: any Error) {
        switch error {
        case let error as NetworkError:
            self = error
        case is CancellationError:
            self = .cancelled
        case let error as URLError:
            switch error.code {
            case .cancelled: self = .cancelled
            case .timedOut: self = .timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff: self = .offline
            default: self = .transport(error)
            }
        default:
            self = .transport(URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: String(describing: error)]))
        }
    }

    /// The status of an `http` error.
    public var status: Int? {
        if case .http(let status, _, _) = self { return status }
        return nil
    }

    /// The body of an `http` error as UTF-8 text, for logs and messages.
    public var bodyText: String? {
        guard case .http(_, let body, _) = self, !body.isEmpty else { return nil }
        return String(decoding: body, as: UTF8.self)
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "The request's URL isn't valid."
        case .cancelled: "The request was cancelled."
        case .timedOut: "The request timed out."
        case .offline: "You're offline."
        case .http(let status, _, let url):
            "The server answered \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\(url.map { " for \($0.absoluteString)" } ?? "")."
        case .decoding(let type, let underlying): "The response couldn't be read as \(type): \(underlying)"
        case .transport(let error): error.localizedDescription
        }
    }
}
