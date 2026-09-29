import Foundation

/// The routes a navigation stack has pushed, as a value.
///
/// Keeping the stack in a value type means a feature can decide where to go
/// without holding a view, and a test can assert on the resulting path without
/// running one.
public struct StackState<Route: Hashable & Sendable>: Equatable, Sendable {
    /// The pushed routes, root first. Read-only from outside, so it
    /// changes only through the methods below; see `SwiftUIBindings.swift`
    /// for why.
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

    /// Pops back to the most recent occurrence of `route`, leaving it on top.
    ///
    /// When the route is on the stack more than once, the topmost copy is the
    /// one kept: going back stops at the nearest screen showing it.
    ///
    /// Does nothing if the route is not on the stack. A caller asking to return
    /// somewhere it has never been is a bug in the caller, and quietly emptying
    /// the stack would hide that behind a screen that looks plausible.
    ///
    /// - Returns: Whether the path changed.
    @discardableResult
    public mutating func pop(to route: Route) -> Bool {
        guard let index = path.lastIndex(of: route), index < path.count - 1 else {
            return false
        }
        path.removeSubrange((index + 1)...)
        return true
    }

    /// Returns to the root, discarding the rest of the path.
    public mutating func popToRoot() {
        path.removeAll()
    }

    /// Replaces the whole path in one step.
    ///
    /// Two callers need it: SwiftUI writes a shortened path back here on every
    /// interactive pop, and a deep link hands over a finished path to land
    /// somewhere in one move. So this is the method to look at when the path
    /// changes and no feature code asked for it.
    public mutating func replace(with path: [Route]) {
        self.path = path
    }
}
