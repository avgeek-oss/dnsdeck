import Foundation

class BINDParser {
    static func parse(from url: URL, zoneName: String) throws -> CSVParseResult {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content: content, zoneName: zoneName)
    }

    static func parse(content: String, zoneName: String) -> CSVParseResult {
        let lines = content.components(separatedBy: .newlines)
        var records: [CSVRecord] = []
        var errors: [CSVParseError] = []

        let zoneSuffix = zoneName.hasSuffix(".") ? zoneName : "\(zoneName)."

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {
                continue
            }

            // Skip $ORIGIN, $TTL, and other directives
            if line.hasPrefix("$") {
                continue
            }

            guard let record = parseLine(
                line,
                lineNumber: lineNumber,
                zoneSuffix: zoneSuffix,
                zoneName: zoneName,
                errors: &errors
            ) else {
                continue
            }

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

    private static func parseLine(
        _ line: String,
        lineNumber: Int,
        zoneSuffix: String,
        zoneName: String,
        errors: inout [CSVParseError]
    ) -> CSVRecord? {
        // Tokenize respecting quoted strings (for TXT records)
        var tokens = tokenize(line)

        // Strip inline comments (e.g., "; web server" at end of line)
        if let semiIndex = tokens.firstIndex(where: { $0.hasPrefix(";") }) {
            tokens = Array(tokens[..<semiIndex])
        }

        guard tokens.count >= 4 else {
            errors.append(CSVParseError(
                line: lineNumber,
                message: "Invalid format — expected at least 4 fields (name, TTL, class, type, value)",
                severity: .error
            ))
            return nil
        }

        // Find the IN class marker to anchor field positions
        // Format: name [TTL] IN type data...
        guard let inIndex = tokens.firstIndex(where: { $0.uppercased() == "IN" }) else {
            errors.append(CSVParseError(
                line: lineNumber,
                message: "Missing IN class marker",
                severity: .error
            ))
            return nil
        }

        guard inIndex > 0, tokens.count > inIndex + 2 else {
            errors.append(CSVParseError(
                line: lineNumber,
                message: "Invalid format — insufficient fields around IN marker",
                severity: .error
            ))
            return nil
        }

        // Parse name (everything before TTL/IN)
        let rawName = tokens[0]
        var ttl: Int?

        if inIndex >= 2 {
            // name TTL IN type data...
            if let parsedTTL = Int(tokens[inIndex - 1]) {
                ttl = parsedTTL
            }
        } else {
            // name IN type data... (no TTL)
            ttl = nil
        }

        // Parse type and data
        let type = tokens[inIndex + 1].uppercased()
        let dataTokens = Array(tokens[(inIndex + 2)...])

        guard !dataTokens.isEmpty else {
            errors.append(CSVParseError(
                line: lineNumber,
                message: "Missing record data after type \(type)",
                severity: .error
            ))
            return nil
        }

        // Validate record type
        let validTypes = Constants.DNSRecordTypes.supportedTypes
        if !validTypes.contains(type) {
            errors.append(CSVParseError(
                line: lineNumber,
                message: "Unsupported record type: \(type)",
                severity: .warning
            ))
            return nil
        }

        // Strip trailing dots and zone suffix from name
        let name = stripZone(from: rawName, zoneSuffix: zoneSuffix, zoneName: zoneName)

        // Parse type-specific data
        var content: String
        var priority: Int?

        switch type {
        case "MX":
            guard dataTokens.count >= 2, let parsedPriority = Int(dataTokens[0]) else {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Invalid MX format — expected priority and mail server",
                    severity: .error
                ))
                return nil
            }
            priority = parsedPriority
            content = stripTrailingDot(dataTokens[1])

        case "SRV":
            guard dataTokens.count >= 4,
                  let parsedPriority = Int(dataTokens[0]),
                  Int(dataTokens[1]) != nil,
                  Int(dataTokens[2]) != nil
            else {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Invalid SRV format — expected priority weight port target",
                    severity: .error
                ))
                return nil
            }
            priority = parsedPriority
            let weight = dataTokens[1]
            let port = dataTokens[2]
            let target = stripTrailingDot(dataTokens[3])
            content = "\(weight) \(port) \(target)"

        case "CAA":
            // CAA: flags tag value
            guard dataTokens.count >= 3 else {
                errors.append(CSVParseError(
                    line: lineNumber,
                    message: "Invalid CAA format — expected flags tag value",
                    severity: .error
                ))
                return nil
            }
            content = dataTokens.joined(separator: " ")

        case "TXT":
            // Reassemble TXT content preserving quotes
            content = dataTokens.joined(separator: " ")
            // Ensure quoted
            if !content.hasPrefix("\"") || !content.hasSuffix("\"") {
                content = "\"\(content)\""
            }

        default:
            // A, AAAA, CNAME, NS, PTR — simple value
            content = stripTrailingDot(dataTokens[0])
        }

        return CSVRecord(
            type: type,
            name: name,
            value: content,
            ttl: ttl,
            priority: priority,
            proxied: nil,
            comment: nil
        )
    }

    /// Tokenize a BIND line, keeping quoted strings as single tokens.
    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
                current.append(char)
            } else if char.isWhitespace, !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    /// Strip trailing dot from FQDN.
    private static func stripTrailingDot(_ value: String) -> String {
        if value.hasSuffix(".") {
            return String(value.dropLast())
        }
        return value
    }

    /// Strip zone suffix from a record name.
    /// e.g., "key1._domainkey.avgeek.io." -> "key1._domainkey" when zone is "avgeek.io"
    private static func stripZone(from rawName: String, zoneSuffix: String, zoneName: String) -> String {
        var name = rawName

        // Handle @ as zone root
        if name == "@" {
            return zoneName
        }

        // Strip trailing dot
        name = stripTrailingDot(name)

        // Strip zone suffix
        let zoneWithoutDot = stripTrailingDot(zoneSuffix)
        if name.lowercased() == zoneWithoutDot.lowercased() {
            return zoneName
        }
        if name.lowercased().hasSuffix(".\(zoneWithoutDot.lowercased())") {
            name = String(name.dropLast(zoneWithoutDot.count + 1))
        }

        return name
    }
}
