//
//  HTTPMethod.swift
//  OwnGpt
//

//

import Foundation

public enum HTTPRequestType {
    case get
    case post
    case put
    case delete
    
    var rawValue: String {
        switch self {
        case .get:
            return "GET"
        case .post:
            return "POST"
        case .put:
            return "PUT"
        case .delete:
            return "DELETE"
        }
    }
}
