import Foundation

/// The routes a navigation stack has pushed, as a value.
///
/// Keeping the stack in a value type means a feature can decide where to go
/// without holding a view, and a test can assert on the resulting path without
/// running one.
public struct StackState<Route: Hashable & Sendable>: Equatable, Sendable {
    /// The pushed routes, root first.
    ///
    /// The setter is private so that `Binding`'s dynamic member lookup cannot
    /// hand SwiftUI a writable binding straight to the array. Without that
    /// restriction `$state.path` would resolve to the stored property and let
    /// the system assign to it directly; with it, the binding in
    /// `SwiftUIBindings.swift` is the only `path` a caller can find, and every
    /// system write is funnelled through `replace(with:)`. This is deliberate,
    /// not an oversight: one write path is far easier to reason about and to
    /// hook than an arbitrary number of them.
    public private(set) var path: [Route]

    /// Creates a stack, optionally already showing a path.
    ///
    /// Passing a path is how a deep link starts a feature partway in rather
    /// than pushing its way there one route at a time.
    public init(path: [Route] = []) {
        self.path = path
    }

    /// Whether the stack is showing its root and nothing else.
    public var isEmpty: Bool {
        path.isEmpty
    }

    /// Pushes a route on top of whatever is already showing.
    public mutating func push(_ route: Route) {
        path.append(route)
    }

    /// Removes the topmost route and returns it, or returns `nil` at the root.
    ///
    /// The result is discardable because callers usually pop to go back and do
    /// not care what they left behind.
    @discardableResult
    public mutating func pop() -> Route? {
        path.popLast()
    }

    /// Returns to the root, discarding the rest of the path.
    public mutating func popToRoot() {
        path.removeAll()
    }

    /// Replaces the whole path in one step.
    ///
    /// This serves two callers at once, which is why it is public rather than
    /// an implementation detail. SwiftUI is the first: it owns the stack's
    /// interactive behaviour, so when someone swipes back or taps a back
    /// button the system hands back a shortened path, and the `Binding`
    /// extension in `SwiftUIBindings.swift` writes it here. That makes this the
    /// method the system calls on every pop, and the place to look when the
    /// path changes without any feature code asking for it.
    ///
    /// A deep link is the second: handing over a finished path lands the user
    /// at a destination in one move, without animating through the routes in
    /// between or briefly rendering screens nobody asked for.
    public mutating func replace(with path: [Route]) {
        self.path = path
    }
}
