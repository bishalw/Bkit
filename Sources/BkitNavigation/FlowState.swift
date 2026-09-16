import Foundation

public struct FlowState<Route, Sheet, FullScreen>: Equatable
where Route: Hashable, Sheet: Identifiable & Equatable, FullScreen: Identifiable & Equatable {
    public var stack: StackState<Route>
    public var sheet: SheetState<Sheet>
    public var fullScreen: FullScreenState<FullScreen>

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
