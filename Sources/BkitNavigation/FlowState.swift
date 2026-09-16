import Foundation

/// Everything one feature can currently be showing: a stack, a sheet and a
/// full screen cover, held together as a single value.
///
/// The three surfaces are separate types because SwiftUI drives them through
/// separate APIs, but they belong to one feature and change together, so
/// keeping them in one value gives a feature a single thing to own, to hand to
/// a deep link, and to compare in a test. A flow that does not present
/// everything can say so: see ``StackFlowState``.
public struct FlowState<Route, Sheet, FullScreen>: Equatable
where Route: Hashable, Sheet: Identifiable & Equatable, FullScreen: Identifiable & Equatable {
    /// The routes pushed within this feature.
    public var stack: StackState<Route>

    /// The sheet this feature is presenting, if any.
    public var sheet: SheetState<Sheet>

    /// The full screen cover this feature is presenting, if any.
    public var fullScreen: FullScreenState<FullScreen>

    /// Creates a flow, by default showing nothing but its root screen.
    ///
    /// Each surface defaults to empty so a feature can write `FlowState()` for
    /// the ordinary case, and pass only the surface it cares about when
    /// restoring state or answering a deep link.
    public init(
        stack: StackState<Route> = .init(),
        sheet: SheetState<Sheet> = .init(),
        fullScreen: FullScreenState<FullScreen> = .init()
    ) {
        self.stack = stack
        self.sheet = sheet
        self.fullScreen = fullScreen
    }
}
