import SwiftUI
import XCTest
@testable import BkitNavigation

final class NavigationStateTests: XCTestCase {
    func testStackStatePushPopAndReplace() {
        var state = StackState(path: [TestRoute.home])

        state.push(.detail(id: "note-1"))
        XCTAssertEqual(state.path, [.home, .detail(id: "note-1")])

        let popped = state.pop()
        XCTAssertEqual(popped, .detail(id: "note-1"))
        XCTAssertEqual(state.path, [.home])

        state.replace(with: [.home, .detail(id: "note-2")])
        XCTAssertEqual(state.path, [.home, .detail(id: "note-2")])

        state.popToRoot()
        XCTAssertTrue(state.isEmpty)
    }

    func testSheetStatePresentDismissAndReplace() {
        var state = SheetState(item: TestModal.settings)

        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.item, .settings)

        state.present(.composer)
        XCTAssertEqual(state.item, .composer)

        state.dismiss()
        XCTAssertNil(state.item)

        state.replace(with: .settings)
        XCTAssertEqual(state.item, .settings)
    }

    func testFullScreenCoverStatePresentDismissAndReplace() {
        var state = FullScreenCoverState(item: TestModal.settings)

        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.item, .settings)

        state.present(.composer)
        XCTAssertEqual(state.item, .composer)

        state.dismiss()
        XCTAssertNil(state.item)

        state.replace(with: .settings)
        XCTAssertEqual(state.item, .settings)
    }

    func testFlowStateDefaultsToEmptyNavigation() {
        let state = FlowState<TestRoute, TestModal, TestModal>()

        XCTAssertTrue(state.stack.isEmpty)
        XCTAssertNil(state.sheet.item)
        XCTAssertNil(state.fullScreen.item)
    }

    func testStackFlowStateDefaultsToEmptyStackAndNoPresentation() {
        let state = StackFlowState<TestRoute>()

        XCTAssertTrue(state.stack.isEmpty)
        XCTAssertNil(state.sheet.item)
        XCTAssertNil(state.fullScreen.item)
    }

    func testStackBindingMutatesUnderlyingState() {
        let state = Box(StackState<TestRoute>(path: [.home]))
        let binding = Binding<StackState<TestRoute>>(
            get: { state.value },
            set: { newValue in state.value = newValue }
        )

        binding.path.wrappedValue = [.home, .detail(id: "note-2")]

        XCTAssertEqual(state.value.path, [.home, .detail(id: "note-2")])
    }

    func testPresentationBindingMutatesUnderlyingState() {
        let sheet = Box(SheetState<TestModal>())
        let binding = Binding<SheetState<TestModal>>(
            get: { sheet.value },
            set: { newValue in sheet.value = newValue }
        )

        binding.item.wrappedValue = .settings
        XCTAssertEqual(sheet.value.item, .settings)

        binding.item.wrappedValue = nil
        XCTAssertNil(sheet.value.item)
    }
    /// What `$model.flow.stack.path` and `$model.flow.sheet.item` do in a view: the
    /// bindings reach through the flow's stored properties, and a swipe back or a sheet
    /// dismissal writes the whole flow back with only that surface changed.
    func testFlowBindingsWriteBackThroughTheFlow() {
        let flow = Box(FlowState<TestRoute, TestModal, TestModal>(stack: StackState(path: [.home, .detail(id: "a")])))
        let binding = Binding<FlowState<TestRoute, TestModal, TestModal>>(
            get: { flow.value },
            set: { newValue in flow.value = newValue }
        )
        flow.value.sheet.present(.composer)

        binding.stack.path.wrappedValue = [.home]  // a swipe back
        XCTAssertEqual(flow.value.stack.path, [.home])
        XCTAssertEqual(flow.value.sheet.item, .composer)

        binding.sheet.item.wrappedValue = nil  // a swipe down
        XCTAssertNil(flow.value.sheet.item)
        XCTAssertEqual(flow.value.stack.path, [.home])

        binding.fullScreen.item.wrappedValue = .settings
        XCTAssertEqual(flow.value, FlowState(stack: StackState(path: [.home]), fullScreen: FullScreenCoverState(item: .settings)))
    }

    /// The `nil` SwiftUI writes back on an interactive dismissal.
    func testReplacingWithNilAfterPresentingDismisses() {
        var sheet = SheetState<TestModal>()
        sheet.present(.composer)
        sheet.replace(with: nil)
        XCTAssertNil(sheet.item)
        XCTAssertFalse(sheet.isPresented)
        XCTAssertEqual(sheet, SheetState())

        var cover = FullScreenCoverState<TestModal>()
        cover.present(.settings)
        cover.replace(with: nil)
        XCTAssertNil(cover.item)
        XCTAssertFalse(cover.isPresented)
    }

    func testIsPresentingMatchesOnlyThePresentedItem() {
        var sheet = SheetState<TestModal>()
        XCTAssertFalse(sheet.isPresenting(.settings))

        sheet.present(.settings)
        XCTAssertTrue(sheet.isPresenting(.settings))
        XCTAssertFalse(sheet.isPresenting(.composer))

        sheet.dismiss()
        XCTAssertFalse(sheet.isPresenting(.settings))
    }
    func testPopToReturnsToAnEarlierRoute() {
        var state = StackState<TestRoute>(path: [.home, .detail(id: "a"), .detail(id: "b")])

        XCTAssertTrue(state.pop(to: .home))
        XCTAssertEqual(state.path, [.home])
    }

    func testPopToARepeatedRouteStopsAtItsLastOccurrence() {
        var state = StackState<TestRoute>(path: [.home, .detail(id: "a"), .home, .detail(id: "b")])

        XCTAssertTrue(state.pop(to: .home))
        XCTAssertEqual(state.path, [.home, .detail(id: "a"), .home])
    }

    func testPopToLeavesAnUnknownOrTopmostRouteAlone() {
        var state = StackState<TestRoute>(path: [.home, .detail(id: "a")])

        // Never visited: the caller is wrong, and emptying the stack would hide it.
        XCTAssertFalse(state.pop(to: .detail(id: "z")))
        XCTAssertEqual(state.path, [.home, .detail(id: "a")])

        // Already on top: nothing to pop.
        XCTAssertFalse(state.pop(to: .detail(id: "a")))
        XCTAssertEqual(state.path, [.home, .detail(id: "a")])
    }
    func testPresentationFlagTransitions() {
        var state = PresentationFlag()
        XCTAssertFalse(state.isPresented)

        state.present()
        XCTAssertTrue(state.isPresented)

        state.dismiss()
        XCTAssertFalse(state.isPresented)
    }

    func testPresentationFlagBindingMutatesUnderlyingState() {
        let state = Box(PresentationFlag())
        let binding = Binding<PresentationFlag>(
            get: { state.value },
            set: { newValue in state.value = newValue }
        )

        binding.isPresented.wrappedValue = true
        XCTAssertTrue(state.value.isPresented)

        binding.isPresented.wrappedValue = false
        XCTAssertFalse(state.value.isPresented)
    }
}

/// What a `Binding` reads and writes in these tests. A reference, because `Binding`'s closures
/// are `@Sendable` and can't capture a local `var`.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

private enum TestRoute: Hashable, Sendable {
    case home
    case detail(id: String)
}

private enum TestModal: String, Equatable, Identifiable, Sendable {
    case settings
    case composer

    var id: String { rawValue }
}
