import Foundation

struct CSVRecord: Identifiable {
    let id = UUID()
    let type: String
    let name: String
    let value: String
    let ttl: Int?
    let priority: Int?
    let proxied: Bool?
    let comment: String?

    init(
        type: String,
        name: String,
        value: String,
        ttl: Int? = nil,
        priority: Int? = nil,
        proxied: Bool? = nil,
        comment: String? = nil
    ) {
        self.type = type.uppercased()
        self.name = name
        self.value = value
        self.ttl = ttl
        self.priority = priority
        self.proxied = proxied
        self.comment = comment
    }
}

struct CSVParseResult {
    let records: [CSVRecord]
    let errors: [CSVParseError]
    let totalLines: Int

    var hasErrors: Bool {
        errors.contains { $0.severity == .error }
    }

    var isValid: Bool {
        !hasErrors && !records.isEmpty
    }

    var hasWarnings: Bool {
        !errors.filter { $0.severity == .warning }.isEmpty
    }
}

struct CSVParseError: Error, Identifiable {
    let id = UUID()
    let line: Int
    let message: String
    let severity: Severity

    enum Severity {
        case error
        case warning
    }
}

class CSVParser {
    static func parse(from url: URL) throws -> CSVParseResult {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content: content)
    }

    static func parse(content: String) -> CSVParseResult {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return CSVParseResult(
                records: [],
                errors: [CSVParseError(line: 0, message: "CSV file is empty", severity: .error)],
                totalLines: 0
            )
        }

        var records: [CSVRecord] = []
        var errors: [CSVParseError] = []

        let headerLine = lines[0]
        let headers = parseCSVLine(headerLine).map { $0.lowercased() }

        let requiredHeaders = ["type", "name", "value"]
        let missingHeaders = requiredHeaders.filter { !headers.contains($0) }

        guard let typeIndex = headers.firstIndex(of: "type"),
              let nameIndex = headers.firstIndex(of: "name"),
              let valueIndex = headers.firstIndex(of: "value")
        else {
            let message = if !missingHeaders.isEmpty {
                "Missing required headers: \(missingHeaders.joined(separator: ", "))"
            } else {
                "Could not locate required columns"
            }

            errors.append(CSVParseError(
                line: 1,
                message: message,
                severity: .error
            ))
            return CSVParseResult(records: [], errors: errors, totalLines: lines.count)
        }

        let ttlIndex = headers.firstIndex(of: "ttl")
        let priorityIndex = headers.firstIndex(of: "priority")
        let proxiedIndex = headers.firstIndex(of: "proxied")
        let commentIndex = headers.firstIndex(of: "comment")

        for (index, line) in lines.dropFirst().enumerated() {
            let lineNumber = index + 2
            let fields = parseCSVLine(line)

            if fields.count < headers.count {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Insufficient fields in row (expected \(headers.count), got \(fields.count))",
                    severity: .error
                ))
                continue
            }

            let type = fields[typeIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = fields[nameIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = fields[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)

            if type.isEmpty {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Type field is empty",
                    severity: .error
                ))
                continue
            }

            if name.isEmpty {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Name field is empty",
                    severity: .error
                ))
                continue
            }

            if value.isEmpty {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Value/content field is empty",
                    severity: .error
                ))
                continue
            }

            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Value/content field contains only whitespace",
                    severity: .error
                ))
                continue
            }

            let validTypes = Constants.DNSRecordTypes.supportedTypes
            if !validTypes.contains(type.uppercased()) {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Invalid DNS record type: \(type)",
                    severity: .warning
                ))
            }

            if let validationError = validateRecordContent(type: type.uppercased(), content: value) {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: validationError,
                    severity: .warning
                ))
            }

            var ttl: Int?
            if let ttlIndex, ttlIndex < fields.count {
                let ttlString = fields[ttlIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if !ttlString.isEmpty {
                    if let parsedTTL = Int(ttlString), parsedTTL > 0 {
                        ttl = parsedTTL
                    } else {
                        errors.append(CSVParseError(
                            line: lineNumber,
                            message: "Invalid TTL value: \(ttlString)",
                            severity: .warning
                        ))
                    }
                }
            }

            var priority: Int?
            if let priorityIndex, priorityIndex < fields.count {
                let priorityString = fields[priorityIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if !priorityString.isEmpty {
                    if let parsedPriority = Int(priorityString), parsedPriority >= 0 {
                        priority = parsedPriority
                    } else {
                        errors.append(CSVParseError(
                            line: lineNumber,
                            message: "Invalid priority value: \(priorityString)",
                            severity: .warning
                        ))
                    }
                }
            }

            var proxied: Bool?
            if let proxiedIndex, proxiedIndex < fields.count {
                let proxiedString = fields[proxiedIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if !proxiedString.isEmpty {
                    switch proxiedString.lowercased() {
                    case "true", "1", "yes", "on":
                        proxied = true
                    case "false", "0", "no", "off":
                        proxied = false
                    default:
                        errors.append(CSVParseError(
                            line: lineNumber,
                            message: "Invalid proxied value: \(proxiedString) (use true/false)",
                            severity: .warning
                        ))
                    }
                }
            }

            var comment: String?
            if let commentIndex, commentIndex < fields.count {
                let commentString = fields[commentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if !commentString.isEmpty {
                    comment = commentString
                }
            }

            var finalValue = value
            var finalPriority = priority

            if type.uppercased() == "MX", priority == nil {
                let parts = value.split(separator: " ", maxSplits: 1)
                if parts.count == 2, let extractedPriority = Int(parts[0]) {
                    finalPriority = extractedPriority
                    finalValue = String(parts[1])
                }
            }

            if type.uppercased() == "TXT", !finalValue.hasPrefix("\"") || !finalValue.hasSuffix("\"") {
                finalValue = "\"\(finalValue)\""
            }

            if finalValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Value/content is empty after processing",
                    severity: .error
                ))
                continue
            }

            let record = CSVRecord(
                type: type,
                name: name,
                value: finalValue,
                ttl: ttl,
                priority: finalPriority,
                proxied: proxied,
                comment: comment
            )

            records.append(record)
        }

        if records.count > 1000 {
            errors.append(CSVParseError(
                line: 0,
                message: "Too many records (\(records.count)). Maximum allowed is 1000.",
                severity: .error
            ))
        }

        return CSVParseResult(records: records, errors: errors, totalLines: lines.count)
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let char = line[i]

            if char == "\"" {
                if inQuotes {
                    let nextIndex = line.index(after: i)
                    if nextIndex < line.endIndex, line[nextIndex] == "\"" {
                        currentField += "\""
                        i = nextIndex
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if char == ",", !inQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField += String(char)
            }

            i = line.index(after: i)
        }

        fields.append(currentField)
        return fields
    }

    private static func validateRecordContent(type: String, content: String) -> String? {
        DNSRecordValidator.validateRecordValue(type: type, rawValue: content)
    }
}

extension CSVRecord {
    func toCreateProviderRecordRequest() -> CreateProviderRecordRequest {
        CreateProviderRecordRequest(
            name: name,
            type: type,
            content: value,
            ttl: ttl,
            proxied: proxied,
            priority: priority,
            comment: comment
        )
    }
}
