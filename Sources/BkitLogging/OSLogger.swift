import os

/// `Logging` through the unified log (`os.Logger`), one subsystem and category per logger.
///
/// Each message is followed by where it was logged from, on the same line:
/// `Synced 3 notes [NoteStore.swift:42 sync()]`. The unified log records a call site of its
/// own, but for a message logged through this type that site is always this file, so the
/// caller's file, line and function are the only way a reader finds the code that logged.
///
/// Messages are private by default, as the unified log treats any dynamic string: they read
/// `<private>` unless a debugger is attached or the device is configured to show them. A
/// logger whose messages never hold personal data can be made `.public`, so they read on any
/// device. The location is always public; it names code, not people.
public struct OSLogger: Logging {
    /// Whether messages are readable outside a debugger.
    public enum Privacy: Sendable, Hashable {
        /// Shown as `<private>` unless a debugger is attached or the device's logging
        /// configuration reveals it. The unified log's default, and the safe one.
        case `private`
        /// Readable wherever the log is read: Console, a sysdiagnose, `log collect`. Only for
        /// messages that never include personal data.
        case `public`
    }

    /// What one call hands the unified log.
    struct Entry: Equatable, Sendable {
        let type: OSLogType
        let privacy: Privacy
        let message: String
        let location: String
    }

    /// Whether this logger's messages are readable outside a debugger.
    public let privacy: Privacy
    private let emit: @Sendable (Entry) -> Void

    public init(subsystem: String, category: String, privacy: Privacy = .private) {
        self.init(logger: Logger(subsystem: subsystem, category: category), privacy: privacy)
    }

    public init(logger: Logger, privacy: Privacy = .private) {
        // `privacy:` must be a literal where the message is built, so each choice gets its
        // own call.
        self.init(privacy: privacy) { entry in
            switch entry.privacy {
            case .private: logger.log(level: entry.type, "\(entry.message, privacy: .private) \(entry.location, privacy: .public)")
            case .public: logger.log(level: entry.type, "\(entry.message, privacy: .public) \(entry.location, privacy: .public)")
            }
        }
    }

    /// Hands each entry to `emit` instead of the unified log, for tests.
    init(privacy: Privacy = .private, emit: @escaping @Sendable (Entry) -> Void) {
        self.privacy = privacy
        self.emit = emit
    }

    public func log(_ level: LogLevel, _ message: String, file: String, function: String, line: Int) {
        let location = Self.location(file: file, function: function, line: line)
        emit(Entry(type: Self.type(of: level), privacy: privacy, message: message, location: location))
    }

    /// The unified log's type for a level, as `os.Logger`'s methods choose it: `warning`
    /// logs at `.error`, as `Logger.warning(_:)` does.
    static func type(of level: LogLevel) -> OSLogType {
        switch level {
        case .debug: .debug
        case .info: .info
        case .warning, .error: .error
        case .fault: .fault
        }
    }

    /// "[NoteStore.swift:42 sync()]": the file's name without its module, the line, the function.
    static func location(file: String, function: String, line: Int) -> String {
        let fileName = file.split(separator: "/").last.map(String.init) ?? file
        return "[\(fileName):\(line) \(function)]"
    }
}
