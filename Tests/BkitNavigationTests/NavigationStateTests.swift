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

    func testFullScreenStatePresentDismissAndReplace() {
        var state = FullScreenState(item: TestModal.settings)

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
