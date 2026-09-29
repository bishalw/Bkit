import SwiftUI

// How the bindings below reach SwiftUI, and what `private(set)` is for.
//
// `$model.stack.path` resolves to the `path` property in the `Binding`
// extension below, not to `Binding`'s dynamic member subscript: Swift finds a
// type's real members, extension members included, before it falls back to
// `@dynamicMemberLookup`. The subscript couldn't reach `path` anyway, since it
// takes a `WritableKeyPath` and a `private(set)` property's key path is
// read-only outside the module.
//
// So the private setter isn't what makes these bindings win. What it buys is
// that code outside the module can't assign `path`, `item` or `isPresented`
// directly: callers change them through the named transitions (`push`,
// `present`, `dismiss`…), and every write from the system arrives through
// `replace(with:)`, which the bindings call. An interactive pop or dismissal
// then lands in one method, the same one a deep link uses, instead of in as
// many places as there are call sites.

/// A stack whose path SwiftUI is allowed to write back.
///
/// The protocol exists so the `Binding` extension below can be written once
/// against any stack-shaped state rather than per concrete type. It asks for a
/// readable path and a single mutating write, which is exactly the contract
/// `NavigationStack(path:)` needs and nothing more.
public protocol NavigationPathState: Sendable {
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
/// matters here, so both conform and share one binding.
public protocol PresentedItemState: Sendable {
    /// The type identifying what is presented.
    associatedtype Item: Identifiable & Equatable & Sendable

    /// The presented item, or `nil` when nothing is presented.
    var item: Item? { get }

    /// Accepts an item from the system, including the `nil` that arrives on an
    /// interactive dismissal. See ``SheetState/replace(with:)`` for why this is
    /// the only write.
    mutating func replace(with item: Item?)
}

/// A presentation whose visibility SwiftUI is allowed to write back.
///
/// The counterpart to ``PresentedItemState`` for the surfaces that carry no
/// item: SwiftUI drives those with an `isPresented:` binding, and needs the
/// same single write path to report an interactive dismissal.
public protocol PresentationFlagState: Sendable {
    /// Whether the surface is up.
    var isPresented: Bool { get }

    /// Accepts visibility from the system, including the `false` that arrives
    /// on an interactive dismissal. See ``PresentationFlag/replace(with:)``
    /// for why this is the only write.
    mutating func replace(with isPresented: Bool)
}

extension StackState: NavigationPathState {}
extension SheetState: PresentedItemState {}
extension FullScreenCoverState: PresentedItemState {}
extension PresentationFlag: PresentationFlagState {}

public extension Binding where Value: NavigationPathState {
    /// A path binding to hand to `NavigationStack(path:)`.
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

public extension Binding where Value: PresentedItemState {
    /// An item binding to hand to `.sheet(item:)` or
    /// `.fullScreenCover(item:)`. Writes, including the `nil` SwiftUI sends on
    /// an interactive dismissal, go through `replace(with:)`.
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

public extension Binding where Value: PresentationFlagState {
    /// A binding for `.sheet(isPresented:)`, `.fullScreenCover(isPresented:)`,
    /// `.alert(_:isPresented:)`, `.popover(isPresented:)` and the rest of the
    /// surfaces SwiftUI toggles rather than fills.
    var isPresented: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.isPresented },
            set: { newValue in
                var copy = wrappedValue
                copy.replace(with: newValue)
                wrappedValue = copy
            }
        )
    }
}
