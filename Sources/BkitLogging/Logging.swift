/// Somewhere log messages go, at five levels.
///
/// A conformer implements one method, `log(_:_:file:function:line:)`. Callers use the level
/// methods in the extension below — `debug`, `info`, `warning`, `error`, `fault` — which fill
/// in the file, function and line of the call. Because those defaults live in the extension,
/// they work the same through `any Logging`, so a type can take its logger as a protocol and
/// a test can hand it a recording one.
public protocol Logging: Sendable {
    /// Writes one message. `file` is a `#fileID` ("Module/File.swift").
    func log(_ level: LogLevel, _ message: String, file: String, function: String, line: Int)
}

/// How severe a message is, lowest first. The names follow `os.Logger`'s methods.
public enum LogLevel: Sendable, Hashable, CaseIterable {
    case debug
    case info
    case warning
    case error
    case fault
}

public extension Logging {
    func debug(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }

    func fault(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(.fault, message, file: file, function: function, line: line)
    }
}
