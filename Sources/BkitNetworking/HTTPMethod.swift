/// An HTTP request method. A struct rather than an enum so a method this file doesn't name
/// (`OPTIONS`, `PROPFIND`) can still be sent: `HTTPMethod(rawValue: "OPTIONS")`.
public struct HTTPMethod: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public static let get = HTTPMethod(rawValue: "GET")
    public static let post = HTTPMethod(rawValue: "POST")
    public static let put = HTTPMethod(rawValue: "PUT")
    public static let patch = HTTPMethod(rawValue: "PATCH")
    public static let delete = HTTPMethod(rawValue: "DELETE")
    public static let head = HTTPMethod(rawValue: "HEAD")

    /// Sending it twice has the same effect as sending it once (RFC 9110 §9.2.2), so a retry
    /// can't, say, charge a card twice. `RetryPolicy` only retries these unless told otherwise.
    public var isIdempotent: Bool {
        switch self {
        case .get, .head, .put, .delete, HTTPMethod(rawValue: "OPTIONS"), HTTPMethod(rawValue: "TRACE"): true
        default: false
        }
    }

    public var description: String { rawValue }
}
