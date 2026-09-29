import Foundation
import Testing
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
        let logger: any Logging & Sendable = OSLogger(subsystem: "BkitLoggingTests", category: "tests")
        for level in LogLevel.allCases {
            logger.log(level, "level \(level)", file: #fileID, function: #function, line: #line)
        }
        logger.warning("through the extension")
    }

    @Test func anOSLoggerMessageNamesTheFileLineAndFunction() {
        let text = OSLogger.format("Saved", file: "App/NoteStore.swift", function: "save(_:)", line: 42)
        #expect(text == "[ NoteStore.swift] | Line [42]\nFunction: save(_:)\nLog: Saved")
    }
}
