import Foundation

enum DNSRecordValidator {
    static func validateRecordName(_ name: String, allowEmpty: Bool = false) -> String? {
        let trimmed = name.trimmed

        if allowEmpty, trimmed.isEmpty {
            return nil
        }

        if trimmed == "@" || trimmed == "*" {
            return nil
        }

        if trimmed.isEmpty {
            return AppLocalization.string("Name is required")
        }

        if trimmed.count > 253 {
            return AppLocalization.string("Name too long (max 253 characters)")
        }

        let normalizedName = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
        let labels = normalizedName.split(separator: ".", omittingEmptySubsequences: false)
        let labelRegex = "^[a-zA-Z0-9_*]([a-zA-Z0-9\\-_]*[a-zA-Z0-9_])?$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", labelRegex)

        for label in labels {
            let labelString = String(label)
            if labelString.isEmpty {
                return AppLocalization.string("Invalid DNS name format")
            }
            if labelString.count > 63 {
                return AppLocalization.string("Label exceeds 63 characters")
            }
            if !predicate.evaluate(with: labelString) {
                return AppLocalization.string("Invalid DNS name format")
            }
        }

        return nil
    }

    static func validateDomain(_ domain: String) -> String? {
        let trimmed = domain.trimmed
        let normalizedDomain = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed

        guard !normalizedDomain.isEmpty else {
            return AppLocalization.string("Invalid domain format")
        }

        let domainRegex = "^([a-zA-Z0-9_]([a-zA-Z0-9\\-_]*[a-zA-Z0-9_])?\\.)+[a-zA-Z]{2,}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)

        return predicate.evaluate(with: normalizedDomain) ? nil : AppLocalization.string("Invalid domain format")
    }

    static func validateRecordValue(type: String, rawValue: String) -> String? {
        switch type.uppercased() {
        case "A":
            return isValidIPv4(rawValue) ? nil : AppLocalization.string("Invalid IPv4 address: \(rawValue)")
        case "AAAA":
            return isValidIPv6(rawValue) ? nil : AppLocalization.string("Invalid IPv6 address format")
        case "CNAME", "NS", "PTR":
            return validateDomain(rawValue)
        case "MX":
            let parts = rawValue.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                if Int(parts[0]) == nil {
                    return AppLocalization.string("Invalid MX priority: \(String(parts[0]))")
                }
                return validateDomain(String(parts[1]))
                    .map { _ in AppLocalization.string("Invalid MX domain: \(String(parts[1]))") }
            }
            if parts.count == 1 {
                return validateDomain(String(parts[0]))
                    .map { _ in AppLocalization.string("Invalid MX domain: \(String(parts[0]))") }
            }
            return AppLocalization.string("Invalid MX record format. Expected 'priority domain' or 'domain'")
        case "TXT":
            return rawValue.count > 2048 ? AppLocalization.string("TXT record too long (max 2048 characters)") : nil
        case "SRV":
            let parts = rawValue.split(separator: " ")
            if parts.count != 4 {
                return AppLocalization.string("Invalid SRV record format. Expected 'priority weight port target'")
            }
            if Int(parts[0]) == nil {
                return AppLocalization.string("Invalid SRV priority: \(String(parts[0]))")
            }
            if Int(parts[1]) == nil {
                return AppLocalization.string("Invalid SRV weight: \(String(parts[1]))")
            }
            guard let port = Int(parts[2]) else {
                return AppLocalization.string("Invalid SRV port: \(String(parts[2]))")
            }
            if let error = InputValidator.validateSRVPort(port).errorMessage {
                return error
            }
            if validateDomain(String(parts[3])) != nil {
                return AppLocalization.string("Invalid SRV target: \(String(parts[3]))")
            }
            return nil
        case "CAA":
            let parts = rawValue.split(separator: " ", maxSplits: 2)
            guard parts.count == 3 else {
                return AppLocalization.string("Invalid CAA record format. Expected 'flags tag value'")
            }
            guard let flags = Int(parts[0]), flags == 0 || flags == 128 else {
                return AppLocalization.string("Invalid CAA flags: \(String(parts[0]))")
            }
            let tag = String(parts[1])
            if !["issue", "issuewild", "iodef"].contains(tag) {
                return AppLocalization.string("Invalid CAA tag: \(tag)")
            }
            let value = String(parts[2]).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return value.isEmpty ? AppLocalization.string("CAA value is required") : nil
        default:
            return nil
        }
    }

    private static func isValidIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }

        for part in parts {
            guard let num = Int(part), num >= 0, num <= 255 else {
                return false
            }
        }

        return true
    }

    private static func isValidIPv6(_ ip: String) -> Bool {
        guard !ip.isEmpty else { return false }

        let colonCount = ip.filter { $0 == ":" }.count
        let hasDoubleColon = ip.contains("::")

        if hasDoubleColon {
            let doubleColonCount = ip.components(separatedBy: "::").count - 1
            guard doubleColonCount == 1 else { return false }
        }

        if !hasDoubleColon, colonCount != 7 { return false }

        let parts = ip.split(separator: ":", omittingEmptySubsequences: false)

        if hasDoubleColon {
            guard parts.count <= 9 else { return false }

            var nonEmptyCount = 0
            for part in parts {
                if part.isEmpty { continue }
                guard part.count <= 4 else { return false }
                for char in part {
                    guard char.isHexDigit else { return false }
                }
                nonEmptyCount += 1
            }
            guard nonEmptyCount < 8 else { return false }
        } else {
            guard parts.count == 8 else { return false }

            for part in parts {
                guard !part.isEmpty, part.count <= 4 else { return false }
                for char in part {
                    guard char.isHexDigit else { return false }
                }
            }
        }

        return true
    }
}
