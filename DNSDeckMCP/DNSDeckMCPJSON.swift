import Foundation

enum DNSDeckMCPJSON {
    static var iso8601: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }

    static func parseObject(_ line: String) throws -> [String: Any] {
        guard let data = line.data(using: .utf8) else {
            throw DNSDeckMCPProtocolError.invalidRequest("Request is not UTF-8.")
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DNSDeckMCPProtocolError.parseError("Parse error.")
        }
        guard let object = value as? [String: Any] else {
            throw DNSDeckMCPProtocolError.invalidRequest("Request must be a JSON object.")
        }
        return object
    }

    static func encodeLine(_ value: Any) throws -> String {
        let cleaned = sanitize(value)
        let data = try JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys])
        guard let line = String(data: data, encoding: .utf8) else {
            throw DNSDeckMCPProtocolError.internalError("Could not encode JSON response.")
        }
        return line
    }

    static func textContent(_ text: String) -> [[String: Any]] {
        [
            [
                "type": "text",
                "text": text,
            ],
        ]
    }

    static func jsonText(_ value: Any) -> String {
        (try? encodeLine(value)) ?? "{}"
    }

    static func optionalPayload(_ value: Any) -> (isOptional: Bool, value: Any?) {
        var current = value
        var didUnwrap = false

        while Mirror(reflecting: current).displayStyle == .optional {
            didUnwrap = true
            guard let child = Mirror(reflecting: current).children.first else {
                return (true, nil)
            }
            current = child.value
        }

        return (didUnwrap, current)
    }

    private static func sanitize(_ value: Any) -> Any {
        let optional = optionalPayload(value)
        if optional.isOptional {
            guard let unwrapped = optional.value else { return NSNull() }
            return sanitize(unwrapped)
        }

        return switch value {
        case let dictionary as [String: Any]:
            dictionary.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = sanitize(entry.value)
            }
        case let array as [Any]:
            array.map(sanitize)
        case let date as Date:
            iso8601.string(from: date)
        case let url as URL:
            url.absoluteString
        case let uuid as UUID:
            uuid.uuidString
        default:
            value
        }
    }
}

enum DNSDeckMCPProtocolError: Error {
    case parseError(String)
    case invalidRequest(String)
    case invalidParams(String)
    case methodNotFound(String)
    case internalError(String)
}

extension DNSDeckMCPProtocolError {
    var code: Int {
        switch self {
        case .parseError: -32700
        case .invalidRequest: -32600
        case .methodNotFound: -32601
        case .invalidParams: -32602
        case .internalError: -32603
        }
    }

    var message: String {
        switch self {
        case let .parseError(message),
             let .invalidRequest(message),
             let .invalidParams(message),
             let .methodNotFound(message),
             let .internalError(message):
            message
        }
    }
}

extension [String: Any] {
    func removingNilValues() -> [String: Any] {
        reduce(into: [String: Any]()) { result, entry in
            let optional = DNSDeckMCPJSON.optionalPayload(entry.value)
            if optional.isOptional {
                guard let value = optional.value else { return }
                result[entry.key] = value
                return
            }
            result[entry.key] = entry.value
        }
    }
}

extension FileHandle {
    func writeLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else { return }
        write(data)
    }
}
