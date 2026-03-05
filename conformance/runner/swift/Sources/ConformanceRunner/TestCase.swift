import Foundation

/// A single conformance test case, decoded from JSON.
struct TestCase: Codable {
    let name: String
    let description: String?
    let operation: String
    let method: String?
    let path: String?
    let pathParams: [String: JSONValue]?
    let queryParams: [String: JSONValue]?
    let requestBody: [String: JSONValue]?
    let mockResponses: [MockResponse]?
    let assertions: [Assertion]?
    let tags: [String]?
    let configOverrides: ConfigOverrides?
}

struct ConfigOverrides: Codable {
    let baseUrl: String?
}

struct MockResponse: Codable {
    let status: Int
    let headers: [String: String]?
    let body: JSONValue?
    let delay: Int?
}

struct Assertion: Codable {
    let type: String
    let expected: JSONValue?
    let min: Double?
    let max: Double?
    let path: String?
}

// MARK: - JSONValue

/// Heterogeneous JSON value for Codable round-tripping.
enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        if case .double(let v) = self, v == Double(Int(v)) { return Int(v) }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    /// Serializes this value to JSON Data.
    func toJSONData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
