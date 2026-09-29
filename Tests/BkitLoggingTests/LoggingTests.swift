import Foundation
import Testing
import os
@testable import BkitLogging

@Suite("Logging")
struct LoggingTests {
    /// Records what reaches it, instead of writing anywhere. Unchecked because the lock, not
    /// the compiler, guards `recorded`.
    final class RecordingLogger: Logging, @unchecked Sendable {
        struct Entry: Equatable {
            let level: LogLevel
            let message: String
            let file: String
            let function: String
            let line: Int
        }

        private let lock = NSLock()
        private var recorded: [Entry] = []

        var entries: [Entry] { lock.withLock { recorded } }

        func log(_ level: LogLevel, _ message: String, file: String, function: String, line: Int) {
            lock.withLock { recorded.append(Entry(level: level, message: message, file: file, function: function, line: line)) }
        }
    }

    @Test func theLevelMethodsWorkThroughAnyLoggingAndSayWhereTheCallWas() {
        let recorder = RecordingLogger()
        let logger: any Logging = recorder

        let line = #line
        logger.debug("d")
        logger.info("i")
        logger.warning("w")
        logger.error("e")
        logger.fault("f")

        #expect(recorder.entries.map(\.level) == LogLevel.allCases)
        #expect(recorder.entries.map(\.message) == ["d", "i", "w", "e", "f"])
        #expect(recorder.entries.map(\.line) == Array(line + 1...line + 5))
        #expect(recorder.entries.allSatisfy { $0.file == "BkitLoggingTests/LoggingTests.swift" })
        #expect(recorder.entries.allSatisfy { $0.function == "theLevelMethodsWorkThroughAnyLoggingAndSayWhereTheCallWas()" })
    }

    @Test func anOSLoggerIsSendableAndLogsThroughTheProtocol() {
        let logger: any Logging & Sendable = OSLogger(subsystem: "BkitLoggingTests", category: "tests", privacy: .public)
        for level in LogLevel.allCases {
            logger.log(level, "level \(level)", file: #fileID, function: #function, line: #line)
        }
        logger.warning("through the extension")
    }

    /// What an OSLogger hands the unified log, caught at its emit seam: the message as given,
    /// the OS level, the privacy, and a one-line location — no banner.
    @Test func anOSLoggerWritesTheMessageWithItsPrivacyAndWhereItCameFrom() {
        let entries = Recorded<OSLogger.Entry>()
        let logger: any Logging = OSLogger { entries.append($0) }

        let line = #line
        logger.info("Synced 3 notes")
        logger.warning("Retrying")

        #expect(
            entries.all == [
                OSLogger.Entry(type: .info, privacy: .private, message: "Synced 3 notes", location: "[LoggingTests.swift:\(line + 1) \(#function)]"),
                OSLogger.Entry(type: .error, privacy: .private, message: "Retrying", location: "[LoggingTests.swift:\(line + 2) \(#function)]"),
            ])
    }

    @Test func aPublicOSLoggerMarksItsMessagesPublic() {
        let entries = Recorded<OSLogger.Entry>()
        OSLogger(privacy: .public) { entries.append($0) }.debug("hello")
        #expect(entries.all.map(\.privacy) == [.public])
    }

    @Test("each level maps to the unified log's type, as os.Logger's methods do", arguments: [
        (LogLevel.debug, OSLogType.debug), (.info, .info), (.warning, .error), (.error, .error), (.fault, .fault),
    ])
    func levels(level: LogLevel, type: OSLogType) {
        let entries = Recorded<OSLogger.Entry>()
        OSLogger { entries.append($0) }.log(level, "m", file: "App/NoteStore.swift", function: "save(_:)", line: 42)
        #expect(entries.all == [OSLogger.Entry(type: type, privacy: .private, message: "m", location: "[NoteStore.swift:42 save(_:)]")])
    }
}

/// Values appended from a `@Sendable` closure.
final class Recorded<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []
    var all: [Value] { lock.withLock { values } }
    func append(_ value: Value) { lock.withLock { values.append(value) } }
}
