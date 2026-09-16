import SwiftUI
import XCTest
@testable import BkitNavigation

final class NavigationStateTests: XCTestCase {
    func testStackStatePushPopAndReplace() {
        var state = StackState(path: [TestRoute.home])

        state.push(.detail(id: "trip-1"))
        XCTAssertEqual(state.path, [.home, .detail(id: "trip-1")])

        let popped = state.pop()
        XCTAssertEqual(popped, .detail(id: "trip-1"))
        XCTAssertEqual(state.path, [.home])

        state.replace(with: [.home, .detail(id: "trip-2")])
        XCTAssertEqual(state.path, [.home, .detail(id: "trip-2")])

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
        var state = StackState<TestRoute>(path: [.home])
        let binding = Binding<StackState<TestRoute>>(
            get: { state },
            set: { newValue in state = newValue }
        )

        binding.path.wrappedValue = [.home, .detail(id: "trip-2")]

        XCTAssertEqual(state.path, [.home, .detail(id: "trip-2")])
    }

    func testPresentationBindingMutatesUnderlyingState() {
        var sheet = SheetState<TestModal>()
        let binding = Binding<SheetState<TestModal>>(
            get: { sheet },
            set: { newValue in sheet = newValue }
        )

        binding.item.wrappedValue = .settings
        XCTAssertEqual(sheet.item, .settings)

        binding.item.wrappedValue = nil
        XCTAssertNil(sheet.item)
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
    func testPopToReturnsToAnEarlierRouteAndReportsDepth() {
        var state = StackState<TestRoute>(path: [.home, .detail(id: "a"), .detail(id: "b")])
        XCTAssertEqual(state.depth, 3)

        XCTAssertTrue(state.popTo(.home))
        XCTAssertEqual(state.path, [.home])
        XCTAssertEqual(state.depth, 1)
    }

    func testPopToLeavesAnUnknownOrTopmostRouteAlone() {
        var state = StackState<TestRoute>(path: [.home, .detail(id: "a")])

        // Never visited: the caller is wrong, and emptying the stack would hide it.
        XCTAssertFalse(state.popTo(.detail(id: "z")))
        XCTAssertEqual(state.path, [.home, .detail(id: "a")])

        // Already on top: nothing to pop.
        XCTAssertFalse(state.popTo(.detail(id: "a")))
        XCTAssertEqual(state.path, [.home, .detail(id: "a")])
    }
    func testPresentationStateTransitions() {
        var state = PresentationState()
        XCTAssertFalse(state.isPresented)

        state.present()
        XCTAssertTrue(state.isPresented)

        state.dismiss()
        XCTAssertFalse(state.isPresented)
    }

    func testPresentationFlagBindingMutatesUnderlyingState() {
        var state = PresentationState()
        let binding = Binding<PresentationState>(
            get: { state },
            set: { newValue in state = newValue }
        )

        binding.isPresented.wrappedValue = true
        XCTAssertTrue(state.isPresented)

        binding.isPresented.wrappedValue = false
        XCTAssertFalse(state.isPresented)
    }
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
