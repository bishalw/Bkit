import Foundation

/// A stand-in item type for a flow that presents nothing modally.
///
/// The enumeration has no cases, so no value of it can ever exist. That is the
/// point: a flow parameterised by `NoPresentation` cannot present a sheet or a
/// full screen cover even by mistake, and the impossibility is checked by the
/// compiler rather than by convention. Because it is uninhabited, `id` can
/// return `Never` and satisfy `Identifiable` without inventing an identifier
/// that would never be read.
public enum NoPresentation: Identifiable, Equatable {
    public var id: Never {
        switch self {}
    }
}

/// A flow that only ever pushes routes onto a navigation stack.
///
/// `FlowState` takes a type for each of its three presentation surfaces, which
/// forces a stack-only feature to declare sheet and full screen cover types it
/// never uses. Naming those unused parameters `NoPresentation` says the feature
/// has no modal surfaces, instead of leaving a reader to check whether some
/// distant call site presents them.
public typealias StackFlowState<Route: Hashable> = FlowState<Route, NoPresentation, NoPresentation>
