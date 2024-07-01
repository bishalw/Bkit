//
//  NetworkServiceImpl.swift
//  OwnGpt
//
//

import Foundation

public class NetworkServiceImpl: NetworkStreamingService, NetworkService {
    let logger = LoggerManager(subsystem: "Networking", category: "general")
    private let urlSession: URLSession
    private let dataParser: DataParser
    
    public init(
        urlSession: URLSession = .shared,
        dataParser: DataParser = DataParserImpl()
    )
    {
        self.urlSession = urlSession
        self.dataParser = dataParser
    }
    public func sendRequest<T: Decodable>(
        request: any HTTPRequest,
        responseModel: T.Type
    ) async throws -> T {
        
        let urlRequest = try createURLRequest(from: request)
        let (data,_) = try await urlSession.data(for: urlRequest)
        return try dataParser.decode(T.self, from: data)
    }
    
    public func makeStreamingRequest<T: Decodable, U>(
        request: any HTTPRequest,
        responseModel: T.Type,
        dataPrefix: String?,
        transform: @escaping (T) -> U?
    ) async throws -> AsyncThrowingStream<U, Error> {
        
        let urlRequest = try createURLRequest(from: request)
        let (bytes, response) = try await self.urlSession.bytes(for: urlRequest)
        try validateHTTPResponse(response, urlRequest: urlRequest)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw NetworkError.cancelled }
                        
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if let jsonString = extractJSON(from: trimmedLine, prefix: dataPrefix),
                           let data = jsonString.data(using: .utf8) {
                            do {
                                // Decode the JSON data into T
                                let decodedObject: T = try self.dataParser.decode(T.self, from: data)
                                if let transformedObject: U = transform(decodedObject) {
                                    // Transform T into U (String)
                                    continuation.yield(transformedObject)
                                }
                            } catch {
                                logger.info("Error decoding JSON: \(error)")
                                logger.info("Problematic JSON string: \(jsonString)")
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

extension NetworkServiceImpl {
    
    private func extractJSON(from line: String, prefix: String?) -> String? {
        var processedLine = line
        // Remove prefix if it exists
        if let prefix = prefix, processedLine.hasPrefix(prefix) {
            processedLine = String(processedLine.dropFirst(prefix.count))
        }
        // check for if string is valid JSON
        processedLine = processedLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard processedLine.first == "{" && processedLine.last == "}" else {
            return nil
        }
        
        return processedLine
    }
    private func createURLRequest(from request: HTTPRequest) throws -> URLRequest {
        let url = try createURL(from: request)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        request.headers?.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        urlRequest.httpBody = request.body
        return urlRequest
    }
    
    private func createURL(from request: HTTPRequest) throws -> URL {
        var urlComponents = URLComponents()
        urlComponents.scheme = request.scheme
        urlComponents.host = request.host
        urlComponents.path = request.path
        
        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }
        return url
    }
    
    private func validateHTTPResponse(_ response: URLResponse, urlRequest: URLRequest) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(url: urlRequest)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.badResponse(
                url: urlRequest.url,
                statusCode: httpResponse.statusCode
            )
        }
    }
}
