import Foundation
import Basecamp

/// A mock Transport that serves pre-configured responses in sequence
/// and records all requests for assertion checking.
final class MockTransport: Transport, @unchecked Sendable {
    struct RecordedRequest {
        let request: URLRequest
        let timestamp: Date
    }

    private let lock = NSLock()
    private var _requests: [RecordedRequest] = []
    private var _responseIndex = 0
    private let responses: [MockResponse]
    private let autoPaginates: Bool

    var requests: [RecordedRequest] {
        lock.withLock { _requests }
    }

    var requestCount: Int {
        lock.withLock { _requests.count }
    }

    init(responses: [MockResponse], autoPaginates: Bool) {
        self.responses = responses
        self.autoPaginates = autoPaginates
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let now = Date()

        let idx: Int = lock.withLock {
            _requests.append(RecordedRequest(request: request, timestamp: now))
            let i = _responseIndex
            _responseIndex += 1
            return i
        }

        // Beyond defined responses
        if idx >= responses.count {
            let url = request.url ?? URL(string: "http://localhost")!
            if autoPaginates {
                // Empty 200 terminates pagination
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (Data("[]".utf8), response)
            } else {
                // Non-paginated overflow: 500
                let response = HTTPURLResponse(
                    url: url, statusCode: 500, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (Data("{\"error\": \"No more mock responses\"}".utf8), response)
            }
        }

        let mockResp = responses[idx]

        // Apply delay if specified
        if let delay = mockResp.delay, delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
        }

        // Build headers
        var headerFields: [String: String] = ["Content-Type": "application/json"]
        if let headers = mockResp.headers {
            for (k, v) in headers {
                headerFields[k] = v
            }
        }

        let url = request.url ?? URL(string: "http://localhost")!
        let response = HTTPURLResponse(
            url: url, statusCode: mockResp.status, httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!

        // Serialize body
        var bodyData = Data()
        if let body = mockResp.body {
            // If body is an object with a single array property, unwrap it.
            // The Swift SDK expects raw arrays for list endpoints.
            var bodyToWrite = body
            if let obj = body.objectValue, obj.count == 1 {
                for (_, v) in obj {
                    if v.arrayValue != nil {
                        bodyToWrite = v
                    }
                }
            }
            bodyData = (try? bodyToWrite.toJSONData()) ?? Data()
        }

        return (bodyData, response)
    }
}
