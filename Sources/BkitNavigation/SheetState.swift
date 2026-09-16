import Foundation

/// Whichever item a sheet is currently showing, if any, as a value.
///
/// The presented item is modelled instead of a bare `Bool` so the sheet's
/// content and its visibility cannot disagree: there is no state in which a
/// sheet is up but nobody knows what it is showing.
public struct SheetState<Item>: Equatable, Sendable where Item: Identifiable & Equatable & Sendable {
    /// The item being shown, or `nil` when no sheet is up.
    ///
    /// The setter is private so that `Binding`'s dynamic member lookup cannot
    /// hand SwiftUI a writable binding straight to the stored property.
    /// Otherwise `$state.item` would resolve to it and the system could assign
    /// through; as written, the binding in `SwiftUIBindings.swift` is the only
    /// `item` a caller can reach, so every dismissal arrives through
    /// `replace(with:)`. That single write path is the point of the
    /// restriction, not a side effect of it.
    public private(set) var item: Item?

    /// Creates a sheet state, optionally already presenting an item.
    ///
    /// Starting with an item is how a deep link opens straight onto a sheet
    /// rather than showing the screen beneath it first.
    public init(item: Item? = nil) {
        self.item = item
    }

    /// Whether a sheet is currently up.
    public var isPresented: Bool {
        item != nil
    }

    /// Whether this exact item is the one currently presented.
    ///
    /// Saves every call site the `state.item == .editor` comparison, and reads
    /// as the question being asked rather than as an equality check against an
    /// optional that may hold something else entirely.
    public func isPresenting(_ item: Item) -> Bool {
        self.item == item
    }

    /// Shows the given item, replacing whatever the sheet was showing before.
    public mutating func present(_ item: Item) {
        self.item = item
    }

    /// Takes the sheet down.
    public mutating func dismiss() {
        item = nil
    }

    /// Sets the presented item directly, including to `nil`.
    ///
    /// This is public because two very different callers need it. SwiftUI is
    /// the first: it owns dismissal gestures, so when someone swipes the sheet
    /// away the system writes `nil` back through the `Binding` extension in
    /// `SwiftUIBindings.swift`, which calls this method. That makes this the
    /// method behind every interactive dismissal, and the place to look when a
    /// sheet closes without any feature code calling `dismiss()`.
    ///
    /// A deep link is the second: it can hand over the item to present, or
    /// `nil` to clear a stale presentation, without caring which of the two it
    /// is doing. `present(_:)` and `dismiss()` remain the clearer choices when
    /// the caller does know.
    public mutating func replace(with item: Item?) {
        self.item = item
    }
}
