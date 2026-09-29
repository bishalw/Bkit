# Changelog

All notable changes to Bkit. Versions follow [Semantic Versioning](https://semver.org);
before 1.0, a minor release may break the API, and every break is listed here with
what to write instead.

## 0.3.0

A breaking release: `BkitNetworking` is rebuilt, names across the package follow the
Swift API Design Guidelines, and `BkitStorage` is gone. The package now needs Swift 6
(swift-tools-version 6.0) and supports iOS 16+ and macOS 13+ only.

### Breaking changes

#### Networking

`BkitNetworking` is rebuilt on `Endpoint` (a request as a value) and `HTTPClient`
(sends it, checks the status, retries, decodes, throws only `NetworkError`). The 0.2.0
client never checked the status of a plain request, dropped
`HTTPRequest.parameters`, and chose a snake_case decoder by the suffix of a type's name,
so it is replaced rather than renamed.

| 0.2.0 | 0.3.0 |
| --- | --- |
| `NetworkService`, `NetworkStreamingService`, `CombinedNetworkService` | `HTTPClient` (a final class; fake the network with `HTTPTransport` instead of mocking the client) |
| `NetworkServiceImpl(urlSession:dataParser:)` | `HTTPClient(transport: URLSessionTransport(session:), decoder:, interceptors:, retry:, logger:)` |
| `sendRequest(request:responseModel:)` | `send(_:as:)`, or `send(_:)` for the raw `(Data, HTTPURLResponse)` |
| `makeStreamingRequest(request:responseModel:dataPrefix:)` | `events(_:terminator:)` then `event.decode(_:)`, or `lines(_:)` |
| `HTTPRequest` protocol (`scheme`, `host`, `path`, `method`, `headers`, `body`, `parameters`) | `Endpoint` struct (`method`, `baseURL`, `path`, `query`, `headers`, `body`, `timeout`, `cachePolicy`) |
| `HTTPRequest.parameters: [String: String]?` | `Endpoint.query: [URLQueryItem]` |
| `HTTPRequest.body: Data?` | `Endpoint.body: Endpoint.Body?` (`.json`, `.json(encoding:)`, `.form`, `.raw`) |
| `HTTPRequestType` (`.get`, `.post`, `.put`, `.delete`) | `HTTPMethod` (same names, plus `.patch`, `.head`, and `HTTPMethod(rawValue:)` for any other) |
| `DataParser`, `DataParserImpl` (snake_case for types named `…DTO`) | `HTTPClient(decoder:)` with the `JSONDecoder` you configure |
| `BkitNetworking.DecodingError.failedToDecode(_:underlyingError:)` | `NetworkError.decoding(type:underlying:)` |
| `NetworkError.badResponse(url:statusCode:)` | `NetworkError.http(status:headers:body:url:)` |
| `NetworkError.badStreamResponse(url:statusCode:body:)` | `NetworkError.http(status:headers:body:url:)` (body capped at `HTTPClient.streamErrorBodyLimit`) |
| `NetworkError.invalidResponse(url:)` | `NetworkError.transport(URLError(.badServerResponse))` |
| `NetworkError.other(url:underlyingError:)` | `.offline`, `.timedOut`, or `.transport(URLError)` |
| `NetworkError.streamError(url:body:)` | the stream finishes throwing a `NetworkError` |
| `NetworkError.cancelled`, `.invalidURL` | unchanged |
| — | `RetryPolicy`, `RequestInterceptor`, `HTTPLogger`, `ServerSentEvent`, `ServerSentEventParser` are new |

If you built against `main` between 0.2.0 and 0.3.0, these changed again before the
release:

| Before 0.3.0 | 0.3.0 |
| --- | --- |
| `case .http(let status, let body, let url)` | `case .http(let status, _, let body, let url)` — the case gained `headers`, which defaults to `[:]`, so `.http(status:body:url:)` still constructs one |
| `BkitLoggingSink(subsystem:category:)` | `OSLogSink(subsystem:category:level:)` or `OSLogSink(logger:level:)` |
| `event.isDone` | `event.data == "[DONE]"`, or end the stream there with `events(_:terminator:)` |
| `ServerSentEvent.retry` only on the event whose block held `retry:` | carries over to every later event, like `id`; `ServerSentEventParser.reconnectionTime` has it as soon as it arrives |
| `events(_:terminator:) -> AsyncThrowingStream<ServerSentEvent, any Error>` | `events(_:terminator:) -> ServerSentEventStream`, an `AsyncSequence` of the same events; `for try await` is unchanged, and once it ends the stream's `lastEventID` and `reconnectionTime` say how to reconnect |

`BkitNetworking` no longer depends on `BkitLogging`.

#### Navigation

| 0.2.0 | 0.3.0 |
| --- | --- |
| `StackState.popTo(_:)` | `StackState.pop(to:)` |
| `StackState.depth` | `StackState.path.count` |
| `PresentationState` | `PresentationFlag` (it still conforms to `PresentationFlagState`) |

#### Logging

| 0.2.0 | 0.3.0 |
| --- | --- |
| `LoggerManager(subsystem:category:)` | `OSLogger(subsystem:category:privacy:)` or `OSLogger(logger:privacy:)`, a `Sendable` struct; `privacy` is `.private` (the default) or `.public` |
| a three-line `[ File.swift] \| Line [n]` / `Function:` / `Log:` message | the message, then `[File.swift:n function]` on the same line |
| `warn(_:file:function:line:)` | `warning(_:file:function:line:)` |
| a conformer implements `debug`, `info`, `error`, `fault`, `warn` | a conformer implements `log(_:_:file:function:line:)`; the level methods come from a protocol extension |
| `Logging` (any type) | `Logging: Sendable` |
| `file: String = #file` | `file: String = #fileID` |

#### Storage

| 0.2.0 | 0.3.0 |
| --- | --- |
| `BkitStorage` product, `PublishedAppStorage`, `PublishedUserDefaults` | removed; use `@AppStorage` or `UserDefaults` |

### Fixes

- `HTTPLogger` no longer writes credentials in the URL: a `user:password@` (or a bare
  `user@`, which can be a token) is logged as `<redacted>@`, every query value is
  `<redacted>` unless its name is in `unredactedQueryItems`, and the fragment is left
  out.
- `HTTPLogger`'s lines read on a device: `OSLogSink` logs them with `privacy: .public`
  (they are redacted first) instead of `<private>`, without a file/function/line
  banner.
- `ServerSentEventParser` follows the HTML standard: a UTF-8 byte order mark at the
  start of the stream is stripped; `retry:` sets the reconnection time even in a block
  with no `data:`; an empty `event:` means the default event type; a `retry:` that is
  not only ASCII digits is ignored.
- `events(_:terminator:)` no longer loses a trailing `retry:` or `id:`: a block without
  `data:` dispatches no event, so a server that ends with `retry: 60000` had no way to
  reach a caller of `events`. The returned `ServerSentEventStream` keeps both settings
  for a client that reconnects, without dropping to `lines(_:)` and a parser of its
  own — which would also mean redoing the `Accept` header and the terminator.
- `NetworkError.http` carries the response headers, with `header(_:)` to look one up in
  any case.
- Logging's level methods default `#fileID`, `#function` and `#line` through
  `any Logging`.
- `OSLogger` can log public messages (`privacy: .public`) that read on a device; the
  default stays private. The caller's location is a one-line, always-public suffix
  instead of a three-line banner inside the private message.

### Documentation

- The README's examples use app-neutral names and compile as written: a
  `ReadmeSnippetTests` target compiles every ` ```swift ` block (and runs the one that is
  a test), and fails when the README and its copy drift apart. The `Package.swift`
  fragments, fenced ` ```swift manifest `, are checked against the package's products and
  this file's latest version.
- The comment on why the SwiftUI binding extensions win over `Binding`'s dynamic member
  lookup now gives the real reason.
