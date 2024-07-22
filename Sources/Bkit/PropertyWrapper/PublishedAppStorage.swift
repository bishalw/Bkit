//
//  File.swift
//  
//
//  Created by Bishalw on 7/21/24.
//

import Foundation
import SwiftUI
import Combine

@propertyWrapper
public struct PublishedAppStorage<Value> {
    @AppStorage private var storedValue: Value
    private let subject: CurrentValueSubject<Value, Never>
    
    public var wrappedValue: Value {
        get {
            storedValue
        }
        set {
            storedValue = newValue
            subject.send(newValue)
        }
    }
    
    public var projectedValue: AnyPublisher<Value, Never> {
        subject.eraseToAnyPublisher()
    }
    public var binding: Binding<Value> {
        $storedValue.projectedValue
    }
    
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == String {
        let storageValue = AppStorage(wrappedValue: wrappedValue, key, store: store)
        self._storedValue = storageValue
        self.subject = .init(storageValue.wrappedValue)
    }
    public init(wrappedValue: Bool, _ key: String , store: UserDefaults? = nil) where Value == Bool {
        let storageValue = AppStorage(wrappedValue: wrappedValue, key, store: store)
        self._storedValue = storageValue
        self.subject = .init(storageValue.wrappedValue)
    }
    
    public init(wrappedValue: Int, _ key: String, store: UserDefaults? = nil) where Value == Int {
        let storageValue = AppStorage(wrappedValue: wrappedValue, key, store: store)
        self._storedValue = storageValue
        self.subject = .init(storageValue.wrappedValue)
    }
    
    public init(wrappedValue: String, _ key: String, store: UserDefaults? = nil) where Value == String {
        let storageValue = AppStorage(wrappedValue: wrappedValue, key, store: store)
        self._storedValue = storageValue
        self.subject = .init(storageValue.wrappedValue)
    }
    
    public init(wrappedValue: URL, _ key: String, store: UserDefaults? = nil) where Value == URL {
        let storageValue = AppStorage(wrappedValue: wrappedValue, key, store: store)
        self._storedValue = storageValue
        self.subject = .init(storageValue.wrappedValue)
    }
    
    public init(wrappedValue: Data, _ key: String, store: UserDefaults? = nil) where Value == Data {
        let storageValue = AppStorage(wrappedValue: wrappedValue, key, store: store)
        self._storedValue = storageValue
        self.subject = .init(storageValue.wrappedValue)
    }
    
}
