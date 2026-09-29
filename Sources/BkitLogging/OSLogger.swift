import os

/// `Logging` through the unified log (`os.Logger`), one subsystem and category per logger.
///
/// A value holding only an `os.Logger`, so it is `Sendable` without qualification and cheap
/// to copy into whatever needs it. Each message is written with the file, line and function
/// it came from. The message is interpolated with the unified log's default privacy, so it
/// reads as `<private>` outside a debugger unless the device is configured to show it.
public struct OSLogger: Logging {
    private let logger: Logger

    public init(subsystem: String, category: String) {
        self.init(logger: Logger(subsystem: subsystem, category: category))
    }

    public init(logger: Logger) {
        self.logger = logger
    }

    public func log(_ level: LogLevel, _ message: String, file: String, function: String, line: Int) {
        let text = Self.format(message, file: file, function: function, line: line)
        switch level {
        case .debug: logger.debug("\(text)")
        case .info: logger.info("\(text)")
        case .warning: logger.warning("\(text)")
        case .error: logger.error("\(text)")
        case .fault: logger.fault("\(text)")
        }
    }

    /// The message with where it came from: the file's name (not its module), line and function.
    static func format(_ message: String, file: String, function: String, line: Int) -> String {
        let fileName = file.split(separator: "/").last.map(String.init) ?? file
        return """
            [ \(fileName)] | Line [\(line)]
            Function: \(function)
            Log: \(message)
            """
    }
}
