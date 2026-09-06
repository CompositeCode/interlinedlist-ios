import Foundation
@testable import InterlinedList

/// Drop-in URLSession replacement for unit tests.
/// Uses URLSessionProtocol so we avoid subclassing URLSession (whose async data(for:)
/// is defined in a Swift extension and cannot be overridden).
final class MockURLSession: URLSessionProtocol {
    private var stubbedData: Data = Data()
    private var stubbedStatusCode: Int = 200
    private var stubbedHeaders: [String: String]?
    private var stubQueue: [(Data, Int, [String: String]?)] = []

    private(set) var lastRequest: URLRequest?
    private(set) var requestHistory: [URLRequest] = []

    func stub(data: Data, statusCode: Int = 200, headers: [String: String]? = nil) {
        stubbedData = data
        stubbedStatusCode = statusCode
        stubbedHeaders = headers
    }

    func stub(json: String, statusCode: Int = 200, headers: [String: String]? = nil) {
        stub(data: Data(json.utf8), statusCode: statusCode, headers: headers)
    }

    func enqueue(json: String, statusCode: Int = 200, headers: [String: String]? = nil) {
        stubQueue.append((Data(json.utf8), statusCode, headers))
    }

    func enqueue(data: Data, statusCode: Int = 200, headers: [String: String]? = nil) {
        stubQueue.append((data, statusCode, headers))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        requestHistory.append(request)
        let url = request.url ?? URL(string: "https://interlinedlist.com")!
        let (body, status, headers): (Data, Int, [String: String]?)
        if !stubQueue.isEmpty {
            (body, status, headers) = stubQueue.removeFirst()
        } else {
            (body, status, headers) = (stubbedData, stubbedStatusCode, stubbedHeaders)
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        return (body, response)
    }
}
