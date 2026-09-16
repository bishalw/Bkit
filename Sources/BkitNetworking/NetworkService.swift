//
//  NetworkService.swift
//  Bkit
//

import Foundation
import os

public protocol CombinedNetworkService: NetworkStreamingService, NetworkService {}

public protocol NetworkService {
    func sendRequest<T: Decodable>(request: any HTTPRequest, responseModel: T.Type) async throws -> T
}

public protocol NetworkStreamingService {
    func makeStreamingRequest<T: Decodable>(
        request: any HTTPRequest,
        responseModel: T.Type,
        dataPrefix: String?
    ) async throws -> AsyncThrowingStream<T, Error>
}
