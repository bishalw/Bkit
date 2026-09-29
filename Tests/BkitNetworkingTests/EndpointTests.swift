import Foundation
import Testing
@testable import BkitNetworking

@Suite("Endpoint")
struct EndpointTests {
    @Test("base and path join with exactly one slash", arguments: [
        ("https://api.example.com", "/v2/rates", "https://api.example.com/v2/rates"),
        ("https://api.example.com/", "v2/rates", "https://api.example.com/v2/rates"),
        ("https://api.example.com/v1/", "/rates", "https://api.example.com/v1/rates"),
        ("https://api.example.com/v1", "rates/", "https://api.example.com/v1/rates/"),
        ("https://api.example.com/v1", "", "https://api.example.com/v1"),
        ("https://api.example.com", "//double", "https://api.example.com/double"),
    ])
    func joining(base: String, path: String, expected: String) throws {
        #expect(try Endpoint(baseURL: URL(string: base)!, path: path).url().absoluteString == expected)
    }

    @Test func queryIsPercentEncodedPlusIncluded() throws {
        let endpoint = Endpoint(
            baseURL: api, path: "search",
            query: [
                URLQueryItem(name: "q", value: "São Paulo & more"),
                URLQueryItem(name: "tag", value: "a+b=c"),
                URLQueryItem(name: "emoji", value: "🇳🇵"),
                URLQueryItem(name: "flag", value: nil),
            ])
        #expect(
            try endpoint.url().absoluteString
                == "https://api.example.com/search?q=S%C3%A3o%20Paulo%20%26%20more&tag=a%2Bb%3Dc&emoji=%F0%9F%87%B3%F0%9F%87%B5&flag")
    }

    @Test func theBaseURLsPortAndQueryStay() throws {
        let base = URL(string: "http://localhost:8080/api?key=abc")!
        let url = try Endpoint(baseURL: base, path: "/rates", query: [URLQueryItem(name: "base", value: "USD")]).url()
        #expect(url.absoluteString == "http://localhost:8080/api/rates?key=abc&base=USD")
        #expect(url.port == 8080)
    }

    @Test func aPathWithSpacesIsEncoded() throws {
        #expect(try Endpoint(baseURL: api, path: "/trips/São Paulo").url().absoluteString == "https://api.example.com/trips/S%C3%A3o%20Paulo")
    }

    @Test func aURLWithoutAHostIsInvalid() {
        #expect(throws: NetworkError.invalidURL) { try Endpoint(baseURL: URL(string: "file:///tmp")!).url() }
        #expect(throws: NetworkError.invalidURL) { try Endpoint(baseURL: URL(string: "relative/path")!).urlRequest() }
    }

    @Test func eachBodySetsItsContentType() throws {
        struct Trip: Encodable { let name: String }
        let json = try Endpoint(.post, baseURL: api, body: .json(encoding: Trip(name: "Nepal"))).urlRequest()
        #expect(json.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(json.httpBody == Data(#"{"name":"Nepal"}"#.utf8))
        #expect(json.httpMethod == "POST")

        let form = try Endpoint(.post, baseURL: api, body: .form(["b": "x y", "a": "1+1"])).urlRequest()
        #expect(form.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8")
        #expect(form.httpBody == Data("a=1%2B1&b=x%20y".utf8))

        let raw = try Endpoint(.put, baseURL: api, body: .raw(Data([1, 2]), contentType: "application/octet-stream")).urlRequest()
        #expect(raw.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(raw.httpBody == Data([1, 2]))
    }

    @Test func anExplicitContentTypeWins() throws {
        let request = try Endpoint(.post, baseURL: api, headers: ["content-type": "application/vnd.api+json"], body: .json(Data("{}".utf8)))
            .urlRequest()
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
    }

    @Test func headersTimeoutAndCachePolicyReachTheRequest() throws {
        let request = try Endpoint(
            baseURL: api, headers: ["Accept": "application/json", "X-Request-ID": "42"], timeout: 7, cachePolicy: .reloadIgnoringLocalCacheData
        ).urlRequest()
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Request-ID") == "42")
        #expect(request.timeoutInterval == 7)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.httpMethod == "GET")
    }

    @Test func methods() {
        #expect(HTTPMethod.get.isIdempotent && HTTPMethod.put.isIdempotent && HTTPMethod.delete.isIdempotent && HTTPMethod.head.isIdempotent)
        #expect(!HTTPMethod.post.isIdempotent && !HTTPMethod.patch.isIdempotent)
        #expect(HTTPMethod(rawValue: "options") == HTTPMethod(rawValue: "OPTIONS"))
    }
}
