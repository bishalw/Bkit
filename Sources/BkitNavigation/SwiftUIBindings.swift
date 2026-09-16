import SwiftUI

/// A stack whose path SwiftUI is allowed to write back.
///
/// The protocol exists so the `Binding` extension below can be written once
/// against any stack-shaped state rather than per concrete type. It asks for a
/// readable path and a single mutating write, which is exactly the contract
/// `NavigationStack(path:)` needs and nothing more.
public protocol StackBindingState {
    /// The element type the stack pushes.
    associatedtype Route: Hashable & Sendable

    /// The pushed routes, root first.
    var path: [Route] { get }

    /// Accepts a whole path from the system, including a shortened one after a
    /// pop. See ``StackState/replace(with:)`` for why this is the only write.
    mutating func replace(with path: [Route])
}

/// A presentation whose item SwiftUI is allowed to write back.
///
/// Sheets and full screen covers differ in how they look and in nothing that
/// matters here, so both conform and share one binding. The name reads a
/// little long for what it describes, which is the cost of covering both
/// presentation styles without naming either.
public protocol ItemPresentationBindingState {
    /// The type identifying what is presented.
    associatedtype Item: Identifiable & Equatable & Sendable

    /// The presented item, or `nil` when nothing is presented.
    var item: Item? { get }

    /// Accepts an item from the system, including the `nil` that arrives on an
    /// interactive dismissal. See ``SheetState/replace(with:)`` for why this is
    /// the only write.
    mutating func replace(with item: Item?)
}

extension StackState: StackBindingState {}
extension SheetState: ItemPresentationBindingState {}
extension FullScreenCoverState: ItemPresentationBindingState {}

public extension Binding where Value: StackBindingState {
    /// A path binding to hand to `NavigationStack(path:)`.
    ///
    /// Reads pass the stored path straight through; writes go through
    /// `replace(with:)` rather than assigning to the array, which is what keeps
    /// a system pop and a deep link on the same code path. Dynamic member
    /// lookup would otherwise offer `$flow.stack.path` as a plain stored
    /// property binding, so the state keeps its setter private and this
    /// property is the only `path` the compiler can find.
    var path: Binding<[Value.Route]> {
        Binding<[Value.Route]>(
            get: { wrappedValue.path },
            set: { newPath in
                var copy = wrappedValue
                copy.replace(with: newPath)
                wrappedValue = copy
            }
        )
    }
}

public extension Binding where Value: ItemPresentationBindingState {
    /// An item binding to hand to `.sheet(item:)` or
    /// `.fullScreenCover(item:)`.
    ///
    /// Reads pass the stored item straight through; writes, including the
    /// `nil` SwiftUI sends when the user swipes a sheet away, go through
    /// `replace(with:)`. As with the path binding, the state keeps its setter
    /// private so dynamic member lookup cannot offer a writable binding that
    /// would bypass that method.
    var item: Binding<Value.Item?> {
        Binding<Value.Item?>(
            get: { wrappedValue.item },
            set: { newItem in
                var copy = wrappedValue
                copy.replace(with: newItem)
                wrappedValue = copy
            }
        )
    }
}
