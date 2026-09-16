import Foundation

public struct FullScreenState<Item>: Equatable where Item: Identifiable & Equatable {
    public private(set) var item: Item?

    public init(item: Item? = nil) {
        self.item = item
    }

    public var isPresented: Bool {
        item != nil
    }

    public mutating func present(_ item: Item) {
        self.item = item
    }

    public mutating func dismiss() {
        item = nil
    }

    public mutating func replace(with item: Item?) {
        self.item = item
    }
}
