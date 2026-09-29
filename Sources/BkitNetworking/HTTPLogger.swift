import Foundation
import os

/// Where `HTTPLogger` writes. `OSLogSink` (the unified log) in apps; a recording sink in tests.
public protocol HTTPLogSink: Sendable {
    func write(_ line: String)
}

/// Writes each line to the unified log through `os.Logger`, at debug level by default.
///
/// The line goes in verbatim and marked public. That is safe because `HTTPLogger` has
/// already redacted it — credential headers, query values, and bodies unless asked for — and
/// necessary, because a dynamic string logged without a privacy level shows as `<private>`
/// everywhere but under a debugger, which would make the log useless on a device.
public struct OSLogSink: HTTPLogSink {
    private let emit: @Sendable (String) -> Void

    public init(subsystem: String = "BkitNetworking", category: String = "http", level: OSLogType = .debug) {
        self.init(logger: Logger(subsystem: subsystem, category: category), level: level)
    }

    public init(logger: Logger, level: OSLogType = .debug) {
        emit = { line in logger.log(level: level, "\(line, privacy: .public)") }
    }

    /// Hands each line to `emit` instead of the unified log, for tests.
    init(emit: @escaping @Sendable (String) -> Void) {
        self.emit = emit
    }

    public func write(_ line: String) {
        emit(line)
    }
}

/// Request and response logging for `HTTPClient`, which logs nothing unless given one.
///
/// Credentials never reach the log: `Authorization`, `Proxy-Authorization`, `Cookie` and
/// `Set-Cookie` values are replaced, whatever their case, and so is every query value
/// (`?api_key=<redacted>&page=<redacted>`) unless its name is in `unredactedQueryItems`.
/// Bodies aren't logged unless `includesBodies` is set — they're where personal data lives.
public struct HTTPLogger: Sendable {
    public static let defaultRedactedHeaders: Set<String> = ["authorization", "proxy-authorization", "cookie", "set-cookie"]

    public var sink: any HTTPLogSink
    public var includesBodies: Bool
    /// Lowercased header names whose values are replaced with "<redacted>".
    public var redactedHeaders: Set<String>
    /// Query item names whose values are logged as sent; every other value is replaced with
    /// "<redacted>". Names are always logged. Matched exactly, after percent-decoding.
    ///
    /// An allow-list, unlike `redactedHeaders`: credential headers have standard names, but a
    /// secret in a query can be called anything (`key`, `sig`, `token`, `code`…), so the only
    /// safe default is to show none. Empty by default.
    public var unredactedQueryItems: Set<String>

    public init(
        sink: any HTTPLogSink = OSLogSink(),
        includesBodies: Bool = false,
        redactedHeaders: Set<String> = defaultRedactedHeaders,
        unredactedQueryItems: Set<String> = []
    ) {
        self.sink = sink
        self.includesBodies = includesBodies
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
        self.unredactedQueryItems = unredactedQueryItems
    }

    func request(_ request: URLRequest, attempt: Int) {
        var line = "→ \(request.httpMethod ?? "GET") \(redacted(request.url))"
        if attempt > 1 { line += " (attempt \(attempt))" }
        line += headerText(request.allHTTPHeaderFields ?? [:])
        if includesBodies, let body = request.httpBody, !body.isEmpty { line += "\n" + String(decoding: body, as: UTF8.self) }
        sink.write(line)
    }

    func response(_ response: HTTPURLResponse, body: Data?, for request: URLRequest) {
        var line = "← \(response.statusCode) \(request.httpMethod ?? "GET") \(redacted(request.url))"
        line += headerText(response.headerFields)
        if includesBodies, let body, !body.isEmpty { line += "\n" + String(decoding: body, as: UTF8.self) }
        sink.write(line)
    }

    func failure(_ error: NetworkError, for request: URLRequest) {
        sink.write("✕ \(request.httpMethod ?? "GET") \(redacted(request.url)): \(error.errorDescription ?? "\(error)")")
    }

    /// The URL as logged: every query value replaced unless its name is in
    /// `unredactedQueryItems`. The fragment is left out; it is never sent to the server.
    func redacted(_ url: URL?) -> String {
        guard let url else { return "?" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "?" }
        let query = components.percentEncodedQuery
        components.percentEncodedQuery = nil
        components.percentEncodedFragment = nil
        guard let base = components.string else { return "?" }
        guard let query, !query.isEmpty else { return base }
        let items = query.split(separator: "&", omittingEmptySubsequences: false).map { item -> String in
            guard let equals = item.firstIndex(of: "=") else { return String(item) }
            let name = item[..<equals]
            let decoded = String(name).removingPercentEncoding ?? String(name)
            return unredactedQueryItems.contains(decoded) ? String(item) : "\(name)=<redacted>"
        }
        return base + "?" + items.joined(separator: "&")
    }

    /// Headers sorted by name, credentials replaced.
    func redacted(_ headers: [String: String]) -> [(String, String)] {
        headers.sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { ($0.key, redactedHeaders.contains($0.key.lowercased()) ? "<redacted>" : $0.value) }
    }

    private func headerText(_ headers: [String: String]) -> String {
        redacted(headers).map { "\n  \($0.0): \($0.1)" }.joined()
    }
}
