//
//  NetworkError.swift
//  OwnGpt
//

//

import Foundation

public enum NetworkError: Error {
    case invalidURL
    case invalidResponse(url: URLRequest?)
    case badResponse(url: URL?, statusCode: Int)
    case other(url: URL?, underlyingError: Error)
    case cancelled
    case badStreamResponse(url: URL?, statusCode: Int, body: String)
    case streamError(url: URL?, body: String)
}

