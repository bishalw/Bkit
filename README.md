# Bkit

Bkit is a small set of Swift packages for iOS and macOS apps: an HTTP client
(`BkitNetworking`), logging (`BkitLogging`) and navigation state
(`BkitNavigation`). Each is its own library product, so an app links only what
it uses.

## Requirements

- iOS 16+ and macOS 13+ (the only platforms the package declares)
- Swift 6 (swift-tools-version 6.0; every target builds in the Swift 6 language
  mode with strict concurrency checking)
- Xcode 16+

## Installation

### Swift Package Manager

Add the package in Xcode (`File → Add Package Dependencies…`, with
`https://github.com/bishalw/Bkit.git`) or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/bishalw/Bkit.git", from: "0.3.0"),
],
```

then depend on the products you need:

```swift
.product(name: "BkitNetworking", package: "Bkit")
```

Until 1.0, a minor release may break the API; `CHANGELOG.md` lists every
change with a migration table.

### Networking

`BkitNetworking` sends requests described as values. An `Endpoint` says what to
send; an `HTTPClient` sends it, checks the status, retries what's safe to retry,
decodes, and throws only `NetworkError`.

```swift
import BkitNetworking

struct Note: Decodable, Sendable {
    let id: Int
    let title: String
}

let client = HTTPClient(retry: RetryPolicy(maxAttempts: 2))

let endpoint = Endpoint(
    .get,
    baseURL: URL(string: "https://api.example.com")!,
    path: "/v1/notes",                                   // joined with exactly one "/"
    query: [URLQueryItem(name: "folder", value: "inbox")] // percent-encoded, "+" included
)

do {
    let notes = try await client.send(endpoint, as: [Note].self)
} catch .http(let status, let headers, let body, _) {
    // Any non-2xx answer, with the response's headers and what the server said.
} catch .offline {
    // No connection: show it, don't retry in a loop.
} catch {
    // .timedOut, .cancelled, .decoding(type:underlying:), .transport(URLError), .invalidURL
}
```

`send` uses typed throws (`throws(NetworkError)`), so the `catch` clauses above
match cases directly. `error.header("Retry-After")` looks up a header of an
`.http` error in any case, and `error.status` and `error.bodyText` read the
rest. `send(_:)` without a type returns the raw
`(Data, HTTPURLResponse)` of a 2xx response.

**Bodies** set their own `Content-Type`: `.json(data)`,
`try .json(encoding: value)`, `.form(["name": "value"])` and
`.raw(data, contentType:)`. An explicit `Content-Type` header wins.

**Retries.** `RetryPolicy` retries 429, 502, 503 and 504 and transient
connection failures, with exponential backoff and jitter, and waits for a
server's `Retry-After` (up to `maxRetryAfter`). Only idempotent methods (GET,
HEAD, PUT, DELETE) are retried unless `retriesNonIdempotent` is set. Cancelling
the task stops it at once, mid-wait included. `RetryPolicy.none` sends once.

**Interceptors** adapt every request, in order, on every attempt — the place
for an `Authorization` header or an App Attest assertion:

```swift
struct BearerToken: RequestInterceptor {
    let token: @Sendable () async throws -> String

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        return request
    }
}
```

**Streams.** `lines(_:)` yields the body line by line as it arrives;
`events(_:)` parses Server-Sent Events as the HTML standard specifies
(multi-line `data:`, `event:`, `id:`, `retry:`, comments, a leading byte order
mark) and by default ends at `data: [DONE]`. Decode an event with
`event.decode(MyDelta.self)`. A non-2xx stream throws `.http` with the start of
its body. Streams aren't retried. The stream's last event id and reconnection
time ride on every event (`id`, `retry`); a client that reconnects after the
stream ends feeds `lines(_:)` to its own `ServerSentEventParser` and reads
`lastEventID` and `reconnectionTime` from it, since a `retry:` can arrive in a
block with no data, which dispatches no event.

**Logging** is off unless you pass `HTTPLogger()`, which writes to the unified
log through `OSLogSink` (`os.Logger`, debug level, marked public so it reads on
a device — it is redacted before it gets there). `Authorization`,
`Proxy-Authorization`, `Cookie` and `Set-Cookie` values are always redacted,
and so is every query value unless its name is in `unredactedQueryItems`
(`?api_key=<redacted>&page=2`); bodies are logged only with
`includesBodies: true`, and then as they are, so keep that to debug builds.

**Testing.** Everything network-facing goes through `HTTPTransport`, so tests
hand the client a fake and check both the requests it made and how it handled
each answer — no network, no `URLProtocol`:

```swift
struct CannedTransport: HTTPTransport {
    let status: Int
    let body: Data

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, any Error>, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        return (AsyncThrowingStream { continuation in
            data.forEach { continuation.yield($0) }
            continuation.finish()
        }, response)
    }
}

let client = HTTPClient(
    transport: CannedTransport(status: 503, body: Data()),
    retry: RetryPolicy(maxAttempts: 3, sleeper: .init { _ in })  // no real waiting
)
```

### Logging

`BkitLogging` is a `Logging` protocol and `OSLogger`, which writes to the
unified log. The level methods fill in the file, function and line of the
call, through `any Logging` too, so a type can take its logger as a protocol:

```swift
import BkitLogging

let log: any Logging = OSLogger(subsystem: "com.example.notes", category: "sync")
log.info("Sync started")
log.warning("Upload is being retried")
```

A logger of your own implements one method,
`log(_:_:file:function:line:)`; the five level methods come with the protocol.

### Navigation

`BkitNavigation` models navigation *state*. It gives a feature value types for
the surfaces SwiftUI presents — `StackState`, `SheetState`,
`FullScreenCoverState`, and `PresentationFlag` for the ones driven by a flag
rather than an item — plus the bindings that hand those values to
`NavigationStack`, `.sheet`, `.fullScreenCover` and friends.

Every transition is a named method (`push`, `pop(to:)`, `present`, `dismiss`),
the stored path and item are read-only from outside, and the bindings are the
only way the system can write back. So navigation is testable without a view,
and a screen that appears has exactly one method that could have caused it.

It is not a router. It has no opinion about how one module reaches a screen
that lives in another, and adding one would mean knowing about modules it
cannot see.

#### Build the flow your feature actually has

`FlowState` bundles a stack, a sheet and a cover for features that use all
three. Most don't. Compose the pieces you need instead — they are independent
values, and an app-specific flow reads better than a bundle with unused
parameters:

```swift
struct LibraryNavigation: Equatable, Sendable {
    var stack = StackState<LibraryRoute>()
    var sheet = SheetState<LibrarySheet>()
}

struct NoteNavigation: Equatable, Sendable {
    var sheet = SheetState<LibrarySheet>()
    var inspector = PresentationFlag()
}
```

Reading state stays direct, without reaching for equality on an optional:

```swift
if navigation.sheet.isPresenting(.newNote) { … }
navigation.stack.pop(to: .folder(id: inboxID))
```

#### Keeping features independent

The tempting shape is a single app-wide `Route` enum with a case per screen.
It works until the second module needs it: now every feature imports a type
that names every other feature's screens, the enum cannot change without
recompiling all of them, and a module can no longer be built or tested on its
own.

Instead, let each feature module own its own flow, over routes only it knows
about:

```swift
// In the Library feature module.
public enum LibraryRoute: Hashable, Sendable {
    case folder(id: UUID)
    case note(id: UUID)
    case editor(noteID: UUID)
}

public enum LibrarySheet: Identifiable, Equatable, Sendable {
    case newNote
    case share(noteID: UUID)

    public var id: String {
        switch self {
        case .newNote: "newNote"
        case .share(let noteID): "share-\(noteID)"
        }
    }
}
```

Routes, sheets and covers must be `Sendable`, like the states that hold them.
A feature with no modal surfaces says so with `StackFlowState<LibraryRoute>`,
rather than naming sheet and cover types it never presents.

When a feature needs to send the user somewhere it cannot reach — settings,
another tab, a screen in a sibling module — it declares what it needs and lets
someone else supply it:

```swift
public protocol SettingsNavigating {
    func openSettings()
}
```

The feature depends on that protocol, not on the settings module. The app
implements it in its composition root, where every module is already visible,
and that is the only place that has to know how the pieces fit together.
Features stay buildable and testable alone, and a test can pass a stub that
records the call.

#### Why there is no `Router` type here

The owner of the state is deliberately left to the app. A shipped `Router`
would have to pick an observation mechanism (`@Observable`, `ObservableObject`,
something else) and a concurrency stance (`@MainActor` or not), and every
consumer would inherit both choices whether or not they suit the app. Those
choices also move with the language faster than a small package should drag
its dependents along. Writing the owner takes a few lines (`@Observable`
needs iOS 17; on iOS 16 an `ObservableObject` with `@Published var flow` works
the same way):

```swift
import BkitNavigation
import SwiftUI

@Observable
@MainActor
final class LibraryRouter {
    var flow = FlowState<LibraryRoute, LibrarySheet, NoPresentation>()

    func showNote(id: UUID) {
        flow.stack.push(.note(id: id))
    }

    func composeNote() {
        flow.sheet.present(.newNote)
    }
}
```

#### Using it in a view

```swift
struct LibraryView: View {
    @State private var router = LibraryRouter()

    var body: some View {
        NavigationStack(path: $router.flow.stack.path) {
            NoteListView(onSelect: router.showNote(id:))
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case .folder(let id):
                        FolderView(id: id)
                    case .note(let id):
                        NoteView(id: id)
                    case .editor(let noteID):
                        NoteEditor(noteID: noteID)
                    }
                }
        }
        .sheet(item: $router.flow.sheet.item) { sheet in
            switch sheet {
            case .newNote:
                NewNoteView()
            case .share(let noteID):
                ShareNoteView(noteID: noteID)
            }
        }
    }
}
```

`$router.flow.stack.path` and `$router.flow.sheet.item` are the bindings this
module adds. Both write back through `replace(with:)`, so a swipe-back gesture
or a sheet dismissal updates the same state a deep link would set, and there is
one place to look when navigation changes on its own.

The states are plain values — `Equatable`, `Sendable`, bound to no actor — so
they sit wherever the app keeps state and the bindings reach them through any
number of properties: `$model.nav.stack.path` on an `@Observable` model, or
`$stack.path` on a `@State private var stack = StackState<Route>()` in a screen
too small to have one.

#### Patterns

**One sheet enum per screen.** Give a screen's sheets one `Identifiable` enum
and one `SheetState`, not a `Bool` each: two flags can both be `true`, one
optional item cannot hold two sheets. Cases carry ids rather than copies of
models, so the sheet reads current data and the enum stays cheap to compare —
`LibrarySheet` above is the shape:

```swift
nav.sheet.present(.share(noteID: note.id))  // replaces whatever was up
```

**Work after a dismissal.** The states say where the user is, not what happens
next. Work that has to wait until a sheet has finished animating away — pushing
the note it just created, say — goes in SwiftUI's `onDismiss`, forwarded to the
owner, rather than in a "then push X" field on the state. `onDismiss` runs
however the sheet went: the owner calling `dismiss()`, or a swipe down or the
environment's `dismiss` action, which both arrive as `replace(with: nil)`.

```swift
.sheet(item: $model.nav.sheet.item, onDismiss: model.sheetDidDismiss) { … }

// In the model:
func sheetDidDismiss() {
    guard let id = createdNoteID else { return }
    createdNoteID = nil
    nav.stack.push(.note(id: id))
}
```

**A presented screen owns its own state.** Nothing here nests, by design. A
sheet with its own `NavigationStack` keeps a `StackState` in that screen's
model; it is not a child of the presenter's `FlowState`, and it goes away with
the sheet. Make that model where a body re-evaluation cannot replace it — in the
owner, when it presents the item — not inside the `.sheet` closure, which runs
again every time the presenter's body does:

```swift
func compose() {
    composer = ComposerModel()  // stored on the owner
    nav.sheet.present(.newNote)
}

// In the view:
case .newNote:
    if let composer = model.composer { ComposerView(model: composer) }
```

**Surfaces that are always up.** A persistent sheet or panel the user cannot
dismiss is not presentation state: nothing ever presents or dismisses it. Give
it `.constant(true)` or make it part of the view's structure. These types model
what can come and go.

**Asking the path.** `path` is a readable array, so questions about the stack
are `Array` calls, and the library deliberately does not wrap them:

```swift
let isEditing = model.nav.stack.path.contains(.editor(noteID: id))
let top = model.nav.stack.path.last
```
