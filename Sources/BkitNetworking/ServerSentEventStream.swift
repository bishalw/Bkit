import os

/// The events of one Server-Sent Events response, from `HTTPClient.events(_:terminator:)`,
/// and the two settings the stream carries for reconnecting.
///
/// Iterate it once, like any `AsyncThrowingStream`. When iteration ends — the server closed
/// the stream, or the terminator arrived — `lastEventID` and `reconnectionTime` say how to
/// come back: send the id as `Last-Event-ID`, after waiting that long. They are kept here
/// because the blocks that set them may dispatch no event: a server can end with
/// `retry: 60000` and no data. `HTTPClient` doesn't reconnect by itself.
public struct ServerSentEventStream: AsyncSequence, Sendable {
    public typealias Element = ServerSentEvent
    public typealias AsyncIterator = AsyncThrowingStream<ServerSentEvent, any Error>.Iterator

    struct Settings: Sendable {
        var lastEventID: String?
        var reconnectionTime: Int?
    }

    private let events: AsyncThrowingStream<ServerSentEvent, any Error>
    private let settings: OSAllocatedUnfairLock<Settings>

    init(events: AsyncThrowingStream<ServerSentEvent, any Error>, settings: OSAllocatedUnfairLock<Settings>) {
        self.events = events
        self.settings = settings
    }

    /// The last `id:` the stream set, as of the latest line read. "" means none, as the spec
    /// says: don't send `Last-Event-ID` then.
    public var lastEventID: String? {
        settings.withLock { $0.lastEventID }
    }

    /// The reconnection time in milliseconds the stream set with `retry:`, as of the latest
    /// line read; nil if it never did, and the client picks its own.
    public var reconnectionTime: Int? {
        settings.withLock { $0.reconnectionTime }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        events.makeAsyncIterator()
    }
}
