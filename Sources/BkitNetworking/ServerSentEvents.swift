import Foundation

/// One Server-Sent Event (the `text/event-stream` format, HTML Living Standard §9.2).
public struct ServerSentEvent: Sendable, Equatable {
    /// The `event:` field; nil for the default "message", which an empty `event:` also means.
    public var event: String?
    /// Every `data:` line of the event, joined with "\n".
    public var data: String
    /// The last `id:` seen, which carries over to later events as the spec says.
    public var id: String?
    /// The stream's reconnection time in milliseconds as of this event: the latest valid
    /// `retry:` the server sent, in this event or any before it. Like `id`, it carries over,
    /// because it's a setting of the stream rather than part of one event.
    public var retry: Int?

    public init(event: String? = nil, data: String, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }

    /// The `data: [DONE]` sentinel several streaming APIs end with.
    public var isDone: Bool { data == "[DONE]" }

    /// The data decoded as JSON.
    public func decode<T: Decodable>(_ type: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) throws(NetworkError) -> T {
        do {
            return try decoder.decode(T.self, from: Data(data.utf8))
        } catch {
            throw .decoding(type: String(describing: T.self), underlying: String(describing: error))
        }
    }
}

/// Turns lines of an event stream into events. Feed it lines as they arrive; an empty line
/// ends an event. An event still open when the stream ends is dropped, as the spec says.
///
/// Besides events, a stream carries two settings a client needs to reconnect: the last event
/// id (sent back as `Last-Event-ID`) and the reconnection time. Both are kept here as they
/// arrive, and every event carries them too. A `retry:` takes effect even in a block with no
/// `data:` — which dispatches no event — so a client that reconnects after the stream ends
/// reads `reconnectionTime` from its own parser, fed from `HTTPClient.lines(_:)`.
public struct ServerSentEventParser: Sendable {
    /// The last `id:` seen, if any. An empty `id:` sets it to "", which means none.
    public private(set) var lastEventID: String?
    /// The latest valid `retry:` in milliseconds, set as soon as the field arrives.
    public private(set) var reconnectionTime: Int?

    private var data: [String] = []
    private var event: String?
    private var hasData = false
    private var isAtStreamStart = true

    public init() {}

    /// The event this line completes, if it's the blank line after one.
    public mutating func consume(line: String) -> ServerSentEvent? {
        let line = strippingByteOrderMark(line)
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }  // a comment, often a keep-alive
        let field: Substring, value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            let rest = line[line.index(after: colon)...]
            value = rest.hasPrefix(" ") ? rest.dropFirst() : rest
        } else {
            field = line[...]
            value = ""
        }
        switch field {
        case "data":
            data.append(String(value))
            hasData = true
        case "event": event = value.isEmpty ? nil : String(value)
        case "id" where !value.contains("\0"): lastEventID = String(value)
        case "retry":
            // Only ASCII digits count: "-1", "+5" and "5s" are ignored, as the spec says.
            if !value.isEmpty, value.allSatisfy({ ("0"..."9").contains($0) }), let milliseconds = Int(value) {
                reconnectionTime = milliseconds
            }
        default: break
        }
        return nil
    }

    /// The stream's first line without the one UTF-8 byte order mark the spec allows before it.
    private mutating func strippingByteOrderMark(_ line: String) -> String {
        guard isAtStreamStart else { return line }
        isAtStreamStart = false
        guard line.unicodeScalars.first == "\u{FEFF}" else { return line }
        return String(line.unicodeScalars.dropFirst())
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            data = []
            event = nil
            hasData = false
        }
        guard hasData else { return nil }
        return ServerSentEvent(event: event, data: data.joined(separator: "\n"), id: lastEventID, retry: reconnectionTime)
    }
}

/// Splits bytes into lines at LF, CRLF or a lone CR, without the terminator. Bytes are only
/// decoded as UTF-8 once a line is whole, so a character split across chunks survives.
struct LineSplitter: Sendable {
    private var buffer: [UInt8] = []
    private var lastWasCR = false

    mutating func consume(_ byte: UInt8) -> String? {
        switch byte {
        case 0x0A:
            if lastWasCR {
                lastWasCR = false
                return nil
            }
            return flush()
        case 0x0D:
            lastWasCR = true
            return flush()
        default:
            lastWasCR = false
            buffer.append(byte)
            return nil
        }
    }

    /// What's left when the stream ends, if anything.
    mutating func finish() -> String? {
        buffer.isEmpty ? nil : flush()
    }

    private mutating func flush() -> String {
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(decoding: buffer, as: UTF8.self)
    }
}
