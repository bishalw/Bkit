

//
//  NetworkService.swift
//  OwnGpt
//

//

import Foundation
import os

public protocol NetworkService {
    func sendRequest<T: Decodable>(request: any HTTPRequest, responseModel: T.Type) async throws -> T
}

public protocol NetworkStreamingService {
    
    func makeStreamingRequest<T: Decodable, U>(
        request: any HTTPRequest,
        responseModel: T.Type,
        dataPrefix: String?,
        transform: @escaping (T) -> U?
    ) async throws -> AsyncThrowingStream<U, Error>
}



