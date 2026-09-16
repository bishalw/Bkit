# Bkit

Bkit is a Swift package that provides a comprehensive networking layer, a flexible logging system, and robust data parsing capabilities. It simplifies the process of making HTTP requests, logging application events, and decoding JSON data, making it easier to build and maintain your iOS and macOS applications.

## Features

- Provides a robust networking layer with support for both standard and streaming requests.
- Includes a flexible logging system.
- Supports custom data parsing with error handling.

## Requirements

- iOS 16.0+ / macOS 13.0+
- Xcode 12.0+
- Swift 5.3+

## Installation

### Swift Package Manager

You can install Bkit using the Swift Package Manager:

1. In Xcode, open your project and navigate to `File → Swift Packages → Add Package Dependency...`
2. Paste the repository URL: 
3. Click on `Next` and select the version you want to use.


### Networking

To use the networking features, create an instance of `NetworkServiceImpl` and call the desired methods:

### Navigation

`BkitNavigation` models navigation *state*. It gives a feature value types for
the three surfaces SwiftUI presents — `StackState`, `SheetState`,
`FullScreenState`, bundled as `FlowState` — plus the bindings that hand those
values to `NavigationStack`, `.sheet` and `.fullScreenCover`.

It is not a router. It has no opinion about how one module reaches a screen
that lives in another, and adding one would mean knowing about modules it
cannot see.

#### Keeping features independent

The tempting shape is a single app-wide `Route` enum with a case per screen.
It works until the second module needs it: now every feature imports a type
that names every other feature's screens, the enum cannot change without
recompiling all of them, and a module can no longer be built or tested on its
own.

Instead, let each feature module own its own flow, over routes only it knows
about:

```swift
// In the Trips feature module.
public enum TripsRoute: Hashable {
    case tripDetail(id: String)
    case itinerary(tripID: String)
}

public enum TripsSheet: Identifiable, Equatable {
    case newTrip

    public var id: String { "newTrip" }
}
```

A feature with no modal surfaces says so with `StackFlowState<TripsRoute>`,
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
final class TripsRouter {
    var flow = FlowState<TripsRoute, TripsSheet, NoPresentation>()

    func showTrip(id: String) {
        flow.stack.push(.tripDetail(id: id))
    }

    func composeTrip() {
        flow.sheet.present(.newTrip)
    }
}
```

#### Using it in a view

```swift
struct TripsView: View {
    @State private var router = TripsRouter()

    var body: some View {
        NavigationStack(path: $router.flow.stack.path) {
            TripsListView(onSelect: router.showTrip(id:))
                .navigationDestination(for: TripsRoute.self) { route in
                    switch route {
                    case .tripDetail(let id):
                        TripDetailView(id: id)
                    case .itinerary(let tripID):
                        ItineraryView(tripID: tripID)
                    }
                }
        }
        .sheet(item: $router.flow.sheet.item) { sheet in
            switch sheet {
            case .newTrip:
                NewTripView()
            }
        }
    }
}
```

`$router.flow.stack.path` and `$router.flow.sheet.item` are the bindings this
module adds. Both write back through `replace(with:)`, so a swipe-back gesture
or a sheet dismissal updates the same state a deep link would set, and there is
one place to look when navigation changes on its own.
