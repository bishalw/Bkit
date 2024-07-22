//
//  DataParser.swift
//  OwnGpt
//

//

import Foundation


public protocol DataParser {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

public struct DataParserImpl: DataParser {
    let regularDecoder: JSONDecoder
    let snakeCaseDecoder: JSONDecoder
    
    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.regularDecoder = decoder
        self.snakeCaseDecoder = JSONDecoder()
        self.snakeCaseDecoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if String(describing: type).hasSuffix("DTO") {
            // For DTOs, try snake case first, then fall back to regular decoding
            do {
                return try snakeCaseDecoder.decode(T.self, from: data)
            } catch {
                // If snake case decoding fails, try regular decoding
                do {
                    return try regularDecoder.decode(T.self, from: data)
                } catch {
                    throw DecodingError.failedToDecode(String(describing: T.self), underlyingError: error)
                }
            }
        } else {
            // For non-DTOs, use regular decoding
            do {
                return try regularDecoder.decode(T.self, from: data)
            } catch {
                throw DecodingError.failedToDecode(String(describing: T.self), underlyingError: error)
            }
        }
    }
}

// Custom DecodingError
public enum DecodingError: Error {
    case failedToDecode(String, underlyingError: Error)
}
