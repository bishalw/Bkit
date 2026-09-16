import Foundation

/// Whichever item a full screen cover is currently showing, if any, as a value.
///
/// A cover hides the screen underneath it entirely, so the item it is showing
/// is the only description of what the user is looking at. Modelling that item
/// rather than a `Bool` keeps the description and the visibility in step.
public struct FullScreenCoverState<Item>: Equatable, Sendable where Item: Identifiable & Equatable & Sendable {
    /// The item being shown, or `nil` when no cover is up.
    ///
    /// The setter is private so that `Binding`'s dynamic member lookup cannot
    /// hand SwiftUI a writable binding straight to the stored property.
    /// Otherwise `$state.item` would resolve to it and the system could assign
    /// through; as written, the binding in `SwiftUIBindings.swift` is the only
    /// `item` a caller can reach, so every dismissal arrives through
    /// `replace(with:)`. That single write path is the point of the
    /// restriction, not a side effect of it.
    public private(set) var item: Item?

    /// Creates a cover state, optionally already presenting an item.
    ///
    /// Starting with an item is how a deep link opens straight onto a cover,
    /// such as an onboarding or paywall flow, without first rendering the
    /// screen it covers.
    public init(item: Item? = nil) {
        self.item = item
    }

    /// Whether a cover is currently up.
    public var isPresented: Bool {
        item != nil
    }

    /// Shows the given item, replacing whatever the cover was showing before.
    public mutating func present(_ item: Item) {
        self.item = item
    }

    /// Takes the cover down.
    public mutating func dismiss() {
        item = nil
    }

    /// Sets the presented item directly, including to `nil`.
    ///
    /// This is public because two very different callers need it. SwiftUI is
    /// the first: a cover dismissed from inside its own content, through
    /// `dismiss` in the environment, writes `nil` back through the `Binding`
    /// extension in `SwiftUIBindings.swift`, which calls this method. That
    /// makes this the method behind every such dismissal, and the place to
    /// look when a cover closes without any feature code calling `dismiss()`.
    ///
    /// A deep link is the second: it can hand over the item to present, or
    /// `nil` to clear a stale presentation, without caring which of the two it
    /// is doing. `present(_:)` and `dismiss()` remain the clearer choices when
    /// the caller does know.
    public mutating func replace(with item: Item?) {
        self.item = item
    }
}
