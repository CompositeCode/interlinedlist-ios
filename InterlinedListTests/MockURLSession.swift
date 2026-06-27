import Foundation
@testable import InterlinedList

/// Drop-in URLSession replacement for unit tests.
/// Uses URLSessionProtocol so we avoid subclassing URLSession (whose async data(for:)
/// is defined in a Swift extension and cannot be overridden).
final class MockURLSession: URLSessionProtocol {
    private var stubbedData: Data = Data()
    private var stubbedStatusCode: Int = 200
    private var stubQueue: [(Data, Int)] = []

    private(set) var lastRequest: URLRequest?
    private(set) var requestHistory: [URLRequest] = []

    func stub(data: Data, statusCode: Int = 200) {
        stubbedData = data
        stubbedStatusCode = statusCode
    }

    func stub(json: String, statusCode: Int = 200) {
        stubbedData = Data(json.utf8)
        stubbedStatusCode = statusCode
    }

    func enqueue(json: String, statusCode: Int = 200) {
        stubQueue.append((Data(json.utf8), statusCode))
    }

    func enqueue(data: Data, statusCode: Int = 200) {
        stubQueue.append((data, statusCode))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        requestHistory.append(request)
        let url = request.url ?? URL(string: "https://interlinedlist.com")!
        let (body, status): (Data, Int)
        if !stubQueue.isEmpty {
            (body, status) = stubQueue.removeFirst()
        } else {
            (body, status) = (stubbedData, stubbedStatusCode)
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
