//
//  File.swift
//  
//
//  Created by Bishalw on 7/25/24.
//

import Foundation
import Combine
@propertyWrapper
public struct PublishedUserDefaults<T> {
    
    private let subject: CurrentValueSubject<T, Never>
    private var storedValue: T
    
    public var wrappedValue: T {
        get {
            storedValue
        }
        set {
            storedValue = newValue
            subject.send(newValue)
        }
    }
    
    
}

