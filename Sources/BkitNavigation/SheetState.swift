import Foundation

/// Whichever item a sheet is currently showing, if any, as a value.
///
/// The presented item is modelled instead of a bare `Bool` so the sheet's
/// content and its visibility cannot disagree: there is no state in which a
/// sheet is up but nobody knows what it is showing.
///
/// A screen that can show several sheets makes `Item` one enum of them all,
/// rather than keeping a state or a flag per sheet: only one can be up at a
/// time, and the type says so.
public struct SheetState<Item>: Equatable, Sendable where Item: Identifiable & Equatable & Sendable {
    /// The item being shown, or `nil` when no sheet is up. Read-only from
    /// outside; see `SwiftUIBindings.swift` for why every write arrives
    /// through ``replace(with:)``.
    public private(set) var item: Item?

    /// Creates a sheet state, optionally already presenting an item — how a
    /// deep link opens straight onto a sheet.
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
    /// SwiftUI writes `nil` back here on an interactive dismissal, so this is
    /// the method behind a sheet that closes without `dismiss()` being called.
    /// A deep link uses it to set or clear an item without caring which it is
    /// doing; ``present(_:)`` and ``dismiss()`` are clearer when the caller
    /// knows.
    public mutating func replace(with item: Item?) {
        self.item = item
    }
}
