import BkitLogging
import Foundation

/// Where `HTTPLogger` writes. `BkitLoggingSink` (os.Logger through BkitLogging) in apps; a
/// recording sink in tests.
public protocol HTTPLogSink: Sendable {
    func write(_ line: String)
}

/// Writes through BkitLogging's `LoggerManager` at debug level.
public struct BkitLoggingSink: HTTPLogSink {
    private let logger: LoggerManager

    public init(subsystem: String = "BkitNetworking", category: String = "http") {
        logger = LoggerManager(subsystem: subsystem, category: category)
    }

    public func write(_ line: String) {
        logger.debug(line)
    }
}

/// Request and response logging for `HTTPClient`, which logs nothing unless given one.
///
/// Credentials never reach the log: `Authorization`, `Proxy-Authorization`, `Cookie` and
/// `Set-Cookie` values are replaced, whatever their case. Bodies aren't logged unless
/// `includesBodies` is set — they're where personal data lives.
public struct HTTPLogger: Sendable {
    public static let defaultRedactedHeaders: Set<String> = ["authorization", "proxy-authorization", "cookie", "set-cookie"]

    public var sink: any HTTPLogSink
    public var includesBodies: Bool
    /// Lowercased header names whose values are replaced with "<redacted>".
    public var redactedHeaders: Set<String>

    public init(sink: any HTTPLogSink = BkitLoggingSink(), includesBodies: Bool = false, redactedHeaders: Set<String> = defaultRedactedHeaders) {
        self.sink = sink
        self.includesBodies = includesBodies
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
    }

    func request(_ request: URLRequest, attempt: Int) {
        var line = "→ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "?")"
        if attempt > 1 { line += " (attempt \(attempt))" }
        line += headerText(request.allHTTPHeaderFields ?? [:])
        if includesBodies, let body = request.httpBody, !body.isEmpty { line += "\n" + String(decoding: body, as: UTF8.self) }
        sink.write(line)
    }

    func response(_ response: HTTPURLResponse, body: Data?, for request: URLRequest) {
        var line = "← \(response.statusCode) \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "?")"
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
        line += headerText(headers)
        if includesBodies, let body, !body.isEmpty { line += "\n" + String(decoding: body, as: UTF8.self) }
        sink.write(line)
    }

    func failure(_ error: NetworkError, for request: URLRequest) {
        sink.write("✕ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "?"): \(error.errorDescription ?? "\(error)")")
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
