import Foundation

/// Everything needed to make one request, as a value: build it, test it, send it with
/// `HTTPClient`. Nothing here touches the network.
///
/// ```swift
/// let rates = Endpoint(.get, baseURL: URL(string: "https://api.frankfurter.dev")!,
///                      path: "/v2/rates", query: [URLQueryItem(name: "base", value: "USD")])
/// ```
public struct Endpoint: Sendable {
    /// What goes in the request body, and the `Content-Type` that says so.
    public enum Body: Sendable, Equatable {
        /// JSON bytes, sent as `application/json`. `Body.json(encoding:)` encodes a value.
        case json(Data)
        /// `application/x-www-form-urlencoded`, keys sorted so the bytes are stable.
        case form([String: String])
        /// Anything else, with its own content type.
        case raw(Data, contentType: String)

        /// A JSON body from an `Encodable` value. Labelled, because `Data` is `Encodable` too:
        /// `.json(data)` would otherwise be ambiguous between sending bytes and encoding them.
        public static func json<T: Encodable>(encoding value: T, encoder: JSONEncoder = JSONEncoder()) throws -> Body {
            .json(try encoder.encode(value))
        }

        public var contentType: String {
            switch self {
            case .json: "application/json"
            case .form: "application/x-www-form-urlencoded; charset=utf-8"
            case .raw(_, let contentType): contentType
            }
        }

        public var data: Data {
            switch self {
            case .json(let data), .raw(let data, _): data
            case .form(let fields):
                Data(
                    fields.sorted { $0.key < $1.key }
                        .map { "\(Endpoint.percentEncoded($0.key))=\(Endpoint.percentEncoded($0.value))" }
                        .joined(separator: "&")
                        .utf8)
            }
        }
    }

    public var method: HTTPMethod
    /// Scheme, host, port and any leading path ("https://api.example.com/v1").
    public var baseURL: URL
    /// Appended to the base URL's path with exactly one "/" between them, whatever slashes
    /// either side has. Not percent-encoded: "/trips/São Paulo" is fine.
    public var path: String
    /// Added after any query the base URL already has. Names and values are percent-encoded
    /// here, "+" included, so a server can't read it as a space.
    public var query: [URLQueryItem]
    public var headers: [String: String]
    public var body: Body?
    /// Overrides the session's request timeout, in seconds.
    public var timeout: TimeInterval?
    public var cachePolicy: URLRequest.CachePolicy?

    public init(
        _ method: HTTPMethod = .get,
        baseURL: URL,
        path: String = "",
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Body? = nil,
        timeout: TimeInterval? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil
    ) {
        self.method = method
        self.baseURL = baseURL
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.cachePolicy = cachePolicy
    }

    /// A GET for a complete URL, query and all.
    public static func get(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval? = nil) -> Endpoint {
        Endpoint(.get, baseURL: url, headers: headers, timeout: timeout)
    }

    /// The full URL: base, joined path, then the base's query and `query`.
    public func url() throws(NetworkError) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false), components.scheme != nil,
            components.host?.isEmpty == false
        else { throw .invalidURL }
        components.path = Self.join(components.path, path)
        let items = (components.percentEncodedQueryItems ?? [])
            + query.map { URLQueryItem(name: Self.percentEncoded($0.name), value: $0.value.map(Self.percentEncoded)) }
        components.percentEncodedQueryItems = items.isEmpty ? nil : items
        guard let url = components.url else { throw .invalidURL }
        return url
    }

    /// The request `HTTPClient` sends, before interceptors adapt it. A body's `Content-Type`
    /// is set unless `headers` names one.
    public func urlRequest() throws(NetworkError) -> URLRequest {
        var request = URLRequest(url: try url())
        request.httpMethod = method.rawValue
        if let timeout { request.timeoutInterval = timeout }
        if let cachePolicy { request.cachePolicy = cachePolicy }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.httpBody = body.data
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
            }
        }
        return request
    }

    // MARK: - Encoding

    /// "/v1/" + "/rates" → "/v1/rates"; "" + "rates" → "/rates"; a trailing slash on `path` stays.
    static func join(_ base: String, _ path: String) -> String {
        let head = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard !path.isEmpty else { return base }
        let tail = path.hasPrefix("/") ? String(path.drop { $0 == "/" }) : path
        return head + "/" + tail
    }

    /// RFC 3986 unreserved characters stay; everything else — spaces, "+", "&", "=", non-ASCII
    /// as UTF-8 — is percent-encoded.
    static func percentEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
