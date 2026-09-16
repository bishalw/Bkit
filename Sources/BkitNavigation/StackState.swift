import Foundation

public struct StackState<Route: Hashable>: Equatable {
    public private(set) var path: [Route]

    public init(path: [Route] = []) {
        self.path = path
    }

    public var isEmpty: Bool {
        path.isEmpty
    }

    public mutating func push(_ route: Route) {
        path.append(route)
    }

    @discardableResult
    public mutating func pop() -> Route? {
        path.popLast()
    }

    public mutating func popToRoot() {
        path.removeAll()
    }

    public mutating func replace(with path: [Route]) {
        self.path = path
    }
}
