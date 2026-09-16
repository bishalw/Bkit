//
//  HTTPRequest.swift
//  OwnGpt
//

//

import Foundation

public protocol HTTPRequest {
    
    var scheme: String { get }
    var host: String { get }
    var path: String { get }
    var method: HTTPRequestType { get }
    var headers: [String: String]? { get }
    var body: Data? { get }
    var parameters: [String: String]? { get }
    
}
