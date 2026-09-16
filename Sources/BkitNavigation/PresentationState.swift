import Foundation

/// Whether a modal surface that carries no content of its own is up.
///
/// ``SheetState`` and ``FullScreenCoverState`` model *what* is being shown,
/// which is the better default: the content and the visibility cannot
/// disagree. Some surfaces have nothing to model, though — a map the app
/// either shows or does not, an alert with fixed text, an inspector — and
/// SwiftUI presents those through an `isPresented:` binding rather than an
/// `item:` one.
///
/// This is the state behind those, with the same named transitions as its
/// siblings. Without it the only option is a bare `Bool` on the app's own
/// state, which any code can flip and no test can distinguish from every other
/// flag beside it.
public struct PresentationState: Equatable, Sendable {
    /// Whether the surface is up.
    ///
    /// The setter is private for the same reason as ``SheetState/item``: it
    /// stops `Binding`'s dynamic member lookup from handing SwiftUI a writable
    /// binding to the stored property, so every interactive dismissal arrives
    /// through ``replace(with:)``.
    public private(set) var isPresented: Bool

    /// Creates a presentation state, optionally already showing.
    public init(isPresented: Bool = false) {
        self.isPresented = isPresented
    }

    /// Brings the surface up.
    public mutating func present() {
        isPresented = true
    }

    /// Takes the surface down.
    public mutating func dismiss() {
        isPresented = false
    }

    /// Sets presentation directly.
    ///
    /// This is the method SwiftUI reaches when someone dismisses the surface
    /// with a gesture: the binding in `SwiftUIBindings.swift` writes `false`
    /// back through it. ``present()`` and ``dismiss()`` stay the clearer
    /// spellings wherever the caller knows which one it means.
    public mutating func replace(with isPresented: Bool) {
        self.isPresented = isPresented
    }
}
