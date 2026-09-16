import SwiftUI

public protocol StackBindingState {
    associatedtype Route: Hashable

    var path: [Route] { get }
    mutating func replace(with path: [Route])
}

public protocol ItemPresentationBindingState {
    associatedtype Item: Identifiable & Equatable

    var item: Item? { get }
    mutating func replace(with item: Item?)
}

extension StackState: StackBindingState {}
extension SheetState: ItemPresentationBindingState {}
extension FullScreenState: ItemPresentationBindingState {}

public extension Binding where Value: StackBindingState {
    var path: Binding<[Value.Route]> {
        Binding<[Value.Route]>(
            get: { wrappedValue.path },
            set: { newPath in
                var copy = wrappedValue
                copy.replace(with: newPath)
                wrappedValue = copy
            }
        )
    }
}

public extension Binding where Value: ItemPresentationBindingState {
    var item: Binding<Value.Item?> {
        Binding<Value.Item?>(
            get: { wrappedValue.item },
            set: { newItem in
                var copy = wrappedValue
                copy.replace(with: newItem)
                wrappedValue = copy
            }
        )
    }
}
