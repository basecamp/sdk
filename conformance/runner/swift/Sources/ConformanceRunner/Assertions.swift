import Foundation
import Basecamp

/// Checks a single assertion. Returns a failure message if the assertion fails, or nil on pass.
func checkAssertion(
    tc: TestCase,
    assertion: Assertion,
    opResult: OpResult,
    transport: MockTransport
) -> String? {
    let sdkErr = opResult.error
    let requests = transport.requests
    let requestCount = transport.requestCount

    // Detect if any mock response includes a Link header with rel="next"
    let hasLinkNextHeader = tc.mockResponses?.contains { resp in
        resp.headers?["Link"]?.contains("rel=\"next\"") == true
    } ?? false

    switch assertion.type {
    case "noError":
        if let err = sdkErr {
            return "Expected no error, got: \(err)"
        }

    case "errorType":
        if sdkErr == nil {
            return "Expected error type \(assertion.expected?.stringValue ?? "?"), but got no error"
        }

    case "errorCode":
        guard let expected = assertion.expected?.stringValue else {
            return "errorCode assertion missing expected string"
        }
        guard let err = sdkErr else {
            return "Expected error code \"\(expected)\", but got no error"
        }
        guard let bcErr = err as? BasecampError else {
            return "Expected error code \"\(expected)\", but error is not BasecampError: \(err)"
        }
        let actual = canonicalErrorCode(bcErr)
        if actual != expected {
            return "Expected error code \"\(expected)\", got \"\(actual)\""
        }

    case "errorMessage":
        guard let expected = assertion.expected?.stringValue else {
            return "errorMessage assertion missing expected string"
        }
        guard let err = sdkErr else {
            return "Expected error message containing \"\(expected)\", but got no error"
        }
        let msg = "\(err)"
        if !msg.contains(expected) {
            return "Expected error message containing \"\(expected)\", got \"\(msg)\""
        }

    case "errorField":
        guard let fieldPath = assertion.path else {
            return "errorField assertion missing path"
        }
        guard let err = sdkErr else {
            return "Expected error field \(fieldPath), but got no error"
        }
        guard let bcErr = err as? BasecampError else {
            return "Expected error field \(fieldPath), but error is not BasecampError: \(err)"
        }
        let actual = errorFieldValue(bcErr, field: fieldPath)
        if let actual {
            return compareValues(label: "error.\(fieldPath)", expected: assertion.expected, actual: actual)
        } else {
            return "Unknown error field: \(fieldPath)"
        }

    case "statusCode":
        guard let expected = assertion.expected?.intValue else {
            return "statusCode assertion missing expected int"
        }
        if let err = sdkErr {
            if let bcErr = err as? BasecampError {
                if let status = bcErr.httpStatusCode, status != expected {
                    return "Expected status code \(expected), got \(status)"
                }
            }
        } else if expected >= 400 {
            return "Expected error with status \(expected), but operation succeeded"
        }

    case "responseStatus":
        guard let expected = assertion.expected?.intValue else {
            return "responseStatus assertion missing expected int"
        }
        if let err = sdkErr {
            if let bcErr = err as? BasecampError {
                if let status = bcErr.httpStatusCode, status != expected {
                    return "Expected response status \(expected), got \(status)"
                }
            }
        } else if expected >= 400 {
            return "Expected error with status \(expected), but operation succeeded"
        }

    case "responseBody":
        // Reserved assertion type — no conformance tests use it yet.
        break

    case "requestCount":
        guard let expected = assertion.expected?.intValue else {
            return "requestCount assertion missing expected int"
        }
        if hasLinkNextHeader {
            if requestCount < expected {
                return "Expected >= \(expected) requests (SDK auto-paginates), got \(requestCount)"
            }
        } else if requestCount != expected {
            return "Expected \(expected) requests, got \(requestCount)"
        }

    case "delayBetweenRequests":
        if requests.count >= 2 {
            let delay = requests[1].timestamp.timeIntervalSince(requests[0].timestamp)
            let minDelay = (assertion.min ?? 0) / 1000.0
            if delay < minDelay {
                return "Expected delay >= \(minDelay)s, got \(delay)s"
            }
        }

    case "requestPath":
        guard let expected = assertion.expected?.stringValue else {
            return "requestPath assertion missing expected string"
        }
        if requests.isEmpty {
            return "Expected a request to be made, but no requests were recorded"
        }
        let actual = requests[0].request.url?.path ?? ""
        if actual != expected {
            return "Expected request path \"\(expected)\", got \"\(actual)\""
        }

    case "headerPresent":
        guard let headerName = assertion.path else {
            return "headerPresent assertion missing path"
        }
        if requests.isEmpty {
            return "Expected header \(headerName) to be present, but no requests were recorded"
        }
        let actual = requests[0].request.value(forHTTPHeaderField: headerName) ?? ""
        if actual.isEmpty {
            return "Expected header \(headerName) to be present, but it was empty or missing"
        }

    case "headerInjected":
        guard let headerName = assertion.path else {
            return "headerInjected assertion missing path"
        }
        guard let expected = assertion.expected?.stringValue else {
            return "headerInjected assertion missing expected string"
        }
        if requests.isEmpty {
            return "Expected header \(headerName)=\"\(expected)\", but no requests were recorded"
        }
        let actual = requests[0].request.value(forHTTPHeaderField: headerName) ?? ""
        if actual != expected {
            return "Expected header \(headerName)=\"\(expected)\", got \"\(actual)\""
        }

    case "headerValue":
        guard let headerName = assertion.path else {
            return "headerValue assertion missing path"
        }
        guard let expected = assertion.expected?.stringValue else {
            return "headerValue assertion missing expected string"
        }
        guard let mockResponses = tc.mockResponses, !mockResponses.isEmpty else {
            return "Expected response header \(headerName)=\"\(expected)\", but no mock responses defined"
        }
        let actual = mockResponses[0].headers?[headerName] ?? ""
        if actual != expected {
            return "Expected response header \(headerName)=\"\(expected)\", got \"\(actual)\""
        }

    case "responseMeta":
        guard let fieldPath = assertion.path else {
            return "responseMeta assertion missing path"
        }
        guard let meta = opResult.meta else {
            return "Expected response meta \(fieldPath), but no metadata returned"
        }
        guard let actual = meta[fieldPath] else {
            return "Expected response meta \(fieldPath), but field not present in metadata"
        }
        return compareValues(label: "meta.\(fieldPath)", expected: assertion.expected, actual: actual)

    case "requestScheme":
        if let expected = assertion.expected?.stringValue, expected == "https" {
            if sdkErr == nil {
                return "Expected HTTPS enforcement error, but request succeeded over HTTP"
            }
        }

    case "urlOrigin":
        if let expected = assertion.expected?.stringValue, expected == "rejected" {
            if requestCount > 1 {
                return "Expected cross-origin URL rejection (1 request), but \(requestCount) requests were made"
            }
        }

    default:
        return "Unknown assertion type: \(assertion.type)"
    }

    return nil
}

// MARK: - Error Mapping

/// Maps a BasecampError case to its canonical error code string.
func canonicalErrorCode(_ error: BasecampError) -> String {
    switch error {
    case .auth: return "auth_required"
    case .forbidden: return "forbidden"
    case .notFound: return "not_found"
    case .rateLimit: return "rate_limit"
    case .validation: return "validation"
    case .api: return "api_error"
    case .network: return "network"
    case .usage: return "usage"
    case .ambiguous: return "ambiguous"
    }
}

/// Extracts a specific field from a BasecampError for assertion comparison.
func errorFieldValue(_ error: BasecampError, field: String) -> Any? {
    switch field {
    case "httpStatus":
        return error.httpStatusCode
    case "retryable":
        return error.isRetryable
    case "code":
        return canonicalErrorCode(error)
    case "message":
        return error.message
    case "requestId":
        return error.requestId
    default:
        return nil
    }
}

// MARK: - Value Comparison

/// Compares an expected JSONValue against an actual Swift value.
/// Returns nil on match, or a failure message string.
func compareValues(label: String, expected: JSONValue?, actual: Any) -> String? {
    guard let expected else { return nil }

    switch expected {
    case .int(let exp):
        if let act = actual as? Int {
            if act != exp { return "Expected \(label) = \(exp), got \(act)" }
        } else if let act = actual as? Optional<Int>, let unwrapped = act {
            if unwrapped != exp { return "Expected \(label) = \(exp), got \(unwrapped)" }
        } else {
            return "Expected \(label) = \(exp), got \(actual)"
        }
    case .double(let exp):
        let expInt = Int(exp)
        if let act = actual as? Int {
            if act != expInt { return "Expected \(label) = \(expInt), got \(act)" }
        } else {
            return "Expected \(label) = \(exp), got \(actual)"
        }
    case .bool(let exp):
        if let act = actual as? Bool {
            if act != exp { return "Expected \(label) = \(exp), got \(act)" }
        } else {
            return "Expected \(label) = \(exp), got \(actual)"
        }
    case .string(let exp):
        let actStr = "\(actual)"
        if actStr != exp { return "Expected \(label) = \"\(exp)\", got \"\(actStr)\"" }
    case .null:
        // Null expected — actual should be nil or Optional.none
        let mirror = Mirror(reflecting: actual)
        if mirror.displayStyle == .optional {
            if mirror.children.count > 0 {
                return "Expected \(label) = null, got \(actual)"
            }
        }
    default:
        break
    }

    return nil
}
