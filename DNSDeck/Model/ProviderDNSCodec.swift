import Foundation

enum ProviderJSONValue: Codable, Hashable {
    case array([Self])
    case bool(Bool)
    case null
    case number(Double)
    case object([String: Self])
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([Self].self) { self = .array(value) }
        else { self = try .object(container.decode([String: Self].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .array(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        case let .number(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        }
    }

    var displayString: String {
        switch self {
        case let .bool(value): String(value)
        case let .number(value): value.rounded() == value ? String(Int(value)) : String(value)
        case let .string(value): value
        case .null: ""
        case let .array(value): value.map(\.displayString).joined(separator: " ")
        case .object: ""
        }
    }
}

enum ProviderDNSName {
    nonisolated static func relativeAt(_ name: String, zoneName: String) -> String {
        relative(name, to: zoneName, apex: "@")
    }

    nonisolated static func relativeAtCaseInsensitive(_ name: String, zoneName: String) -> String {
        relative(name, to: zoneName, apex: "@", caseInsensitive: true, emptyIsApex: true)
    }

    nonisolated static func relativeEmpty(_ name: String, zoneName: String) -> String {
        relative(name, to: zoneName, apex: "")
    }

    nonisolated static func relativeEmptyCaseInsensitive(_ name: String, zoneName: String) -> String {
        relative(name, to: zoneName, apex: "", caseInsensitive: true, emptyIsApex: true)
    }

    nonisolated static func relative(
        _ name: String,
        to zoneName: String,
        apex: String,
        caseInsensitive: Bool = false,
        emptyIsApex: Bool = false
    ) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let zone = zoneName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let equalsZone = caseInsensitive
            ? value.caseInsensitiveCompare(zone) == .orderedSame
            : value == zone
        if value == "@" || equalsZone || (emptyIsApex && value.isEmpty) {
            return apex
        }
        let suffix = ".\(zone)"
        let hasZoneSuffix = caseInsensitive
            ? value.lowercased().hasSuffix(suffix.lowercased())
            : value.hasSuffix(suffix)
        return hasZoneSuffix ? String(value.dropLast(suffix.count)) : value
    }

    nonisolated static func absolute(
        _ name: String,
        in zoneName: String,
        trailingDot: Bool = false,
        caseInsensitive: Bool = false
    ) -> String {
        let zone = zoneName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let relativeName = relative(
            name,
            to: zone,
            apex: "",
            caseInsensitive: caseInsensitive,
            emptyIsApex: true
        )
        let absoluteName = relativeName.isEmpty ? zone : "\(relativeName).\(zone)"
        return trailingDot ? "\(absoluteName)." : absoluteName
    }
}

enum ProviderRecordValue {
    struct PriorityFields {
        let content: String
        let priority: Int?
    }

    nonisolated static func commonPriority(_ values: [String]) -> Int? {
        let priorities = Set(values.compactMap(priority))
        return priorities.count == 1 ? priorities.first : nil
    }

    nonisolated static func dateWithSQLFallback(_ value: String) -> Date? {
        date(value, fallbackFormat: "yyyy-MM-dd HH:mm:ss")
    }

    nonisolated static func priority(_ value: String) -> Int? {
        value.split(whereSeparator: \Character.isWhitespace).first.flatMap { Int($0) }
    }

    nonisolated static func removingPriority(_ value: String) -> String {
        let parts = value.split(whereSeparator: \Character.isWhitespace)
        guard parts.first.flatMap({ Int($0) }) != nil else { return value }
        return parts.dropFirst().joined(separator: " ")
    }

    static func separatingPriority(
        provider: DNSProvider,
        type: String,
        content: String,
        priority: Int?,
        recordData: RecordData?,
        acceptsUnprefixedSRV: Bool = false,
        validatesSRVRange: Bool = false,
        allowsEmptySRVTarget: Bool = false,
        preservesOtherPriority: Bool = false
    ) throws -> PriorityFields {
        switch type {
        case "MX":
            if let recordData {
                return PriorityFields(
                    content: recordData.target ?? recordData.value ?? content,
                    priority: recordData.priority ?? priority ?? 0
                )
            }
            let parts = content.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
            return parts.count == 2 && Int(parts[0]) != nil
                ? PriorityFields(content: String(parts[1]), priority: Int(parts[0]))
                : PriorityFields(content: content, priority: priority ?? 0)
        case "SRV":
            let parts = content.split(whereSeparator: \Character.isWhitespace)
            let values: (priority: Int, weight: Int, port: Int, target: String)? = if let recordData,
                                                                                      let weight = recordData.weight,
                                                                                      let port = recordData.port,
                                                                                      allowsEmptySRVTarget || recordData
                                                                                      .target?.isEmpty == false
            {
                (
                    recordData.priority ?? priority ?? 0,
                    weight,
                    port,
                    recordData.target ?? ""
                )
            } else if parts.count >= 4,
                      let resolvedPriority = Int(parts[0]),
                      let weight = Int(parts[1]),
                      let port = Int(parts[2])
            {
                (resolvedPriority, weight, port, parts.dropFirst(3).joined(separator: " "))
            } else if acceptsUnprefixedSRV,
                      parts.count >= 3,
                      let weight = Int(parts[0]),
                      let port = Int(parts[1])
            {
                (priority ?? 0, weight, port, parts.dropFirst(2).joined(separator: " "))
            } else {
                nil
            }
            guard let values else {
                let suffix = acceptsUnprefixedSRV
                    ? ", or a separate priority with weight, port, and target"
                    : ""
                throw ProviderAPIError.invalidRecordContent(
                    provider: provider,
                    type: type,
                    message: "expected priority, weight, port, and target\(suffix)"
                )
            }
            guard !validatesSRVRange ||
                ((0 ... 65535).contains(values.weight) && (1 ... 65535).contains(values.port))
            else {
                throw ProviderAPIError.invalidRecordContent(
                    provider: provider,
                    type: type,
                    message: "weight must be 0 through 65535 and port must be 1 through 65535"
                )
            }
            return PriorityFields(
                content: "\(values.weight) \(values.port) \(values.target)",
                priority: values.priority
            )
        default:
            return PriorityFields(content: content, priority: preservesOtherPriority ? priority : nil)
        }
    }

    nonisolated static func parseQuotedTXT(_ value: String) -> String {
        parseQuotedTXT(value, allowEmpty: false)
    }

    nonisolated static func parseQuotedTXT(_ value: String, allowEmpty: Bool) -> String {
        guard value.contains("\"") else { return value }
        var result = ""
        var isQuoted = false
        var isEscaped = false
        for character in value {
            if isEscaped {
                result.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isQuoted.toggle()
            } else if isQuoted {
                result.append(character)
            }
        }
        return result.isEmpty && !(allowEmpty && value == "\"\"") ? value : result
    }

    nonisolated static func quotedTXT(
        _ value: String,
        maximumChunkBytes: Int? = nil,
        preserveQuotedValue: Bool = true
    ) -> String {
        if preserveQuotedValue, value.hasPrefix("\""), value.hasSuffix("\"") {
            return value
        }
        guard let maximumChunkBytes else {
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }

        var chunks: [String] = []
        var current = ""
        var byteCount = 0
        for character in value {
            let fragment = switch character {
            case "\\": "\\\\"
            case "\"": "\\\""
            default: String(character)
            }
            if byteCount + fragment.utf8.count > maximumChunkBytes, !current.isEmpty {
                chunks.append(current)
                current = ""
                byteCount = 0
            }
            current.append(fragment)
            byteCount += fragment.utf8.count
        }
        if !current.isEmpty || chunks.isEmpty { chunks.append(current) }
        return chunks.map { "\"\($0)\"" }.joined(separator: " ")
    }

    static func writePresentation(
        type: String,
        value: String,
        priority: Int?,
        recordData: RecordData?,
        provider: DNSProvider,
        preserveNativeValue: Bool = false,
        formatTXT: (String) -> String
    ) throws -> String {
        if preserveNativeValue { return value }
        switch type {
        case "MX":
            guard Self.priority(value) == nil else { return value }
            return "\(recordData?.priority ?? priority ?? 10) \(recordData?.target ?? value)"
        case "SRV":
            if let flat = recordData?.flatContent { return flat }
            let parts = value.split(whereSeparator: \Character.isWhitespace)
            guard parts.count >= 4, parts.prefix(3).allSatisfy({ Int($0) != nil }) else {
                throw ProviderAPIError.invalidRecordContent(
                    provider: provider,
                    type: type,
                    message: "expected priority, weight, port, and target"
                )
            }
            return value
        case "TXT":
            return formatTXT(value)
        default:
            return value
        }
    }

    nonisolated static func date(_ value: String) -> Date? {
        date(value, fallbackFormat: nil)
    }

    nonisolated static func date(
        _ value: String,
        fallbackFormat: String?
    ) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
            return date
        }
        guard let fallbackFormat else { return nil }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = fallbackFormat
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        return fallback.date(from: value)
    }
}

extension CreateProviderRecordRequest {
    var normalizedType: String {
        type.uppercased()
    }

    var mutationValues: [String] {
        values ?? [recordData?.flatContent ?? content]
    }
}

extension UpdateProviderRecordRequest {
    var hasValueEdits: Bool {
        values != nil || recordData != nil || content != nil
    }

    func normalizedType(or existingType: String) -> String {
        (type ?? existingType).uppercased()
    }

    func mutationValues(or existingValues: [String]) -> [String] {
        values ?? recordData?.flatContent.map { [$0] } ?? content.map { [$0] } ?? existingValues
    }
}

extension DNSProvider {
    func validateEditableRecordType(_ type: String) throws {
        guard definition.capabilities.canEdit(recordType: type) else {
            throw ProviderAPIError.invalidRecordContent(
                provider: self,
                type: type,
                message: "the record type is provider-managed or unsupported"
            )
        }
    }
}
