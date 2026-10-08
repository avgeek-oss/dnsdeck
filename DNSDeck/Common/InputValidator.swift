import Foundation

enum InputValidator {
    private static func validate(
        _ value: String,
        emptyMessage: String.LocalizationValue,
        rule: (String) -> String.LocalizationValue?
    ) -> ValidationResult {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .invalid(AppLocalization.string(emptyMessage)) }
        return rule(value).map { .invalid(AppLocalization.string($0)) } ?? .valid
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: value)
    }

    private static func validate(
        _ value: Int,
        in range: ClosedRange<Int>,
        message: String.LocalizationValue
    ) -> ValidationResult {
        range.contains(value) ? .valid : .invalid(AppLocalization.string(message))
    }

    // MARK: - DNS Record Validation

    static func validateDNSName(_ name: String) -> ValidationResult {
        validate(name, emptyMessage: "DNS name cannot be empty") {
            if $0 == "@" { return nil }
            if $0.count > 253 { return "DNS name too long (max 253 characters)" }
            return matches($0, "^[a-zA-Z0-9]([a-zA-Z0-9\\-_]*[a-zA-Z0-9])?$")
                ? nil : "Invalid DNS name format"
        }
    }

    static func validateIPv4Address(_ ip: String) -> ValidationResult {
        validate(ip, emptyMessage: "IP address cannot be empty") {
            matches(
                $0,
                "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
            ) ? nil : "Invalid IPv4 address format"
        }
    }

    static func validateIPv6Address(_ ip: String) -> ValidationResult {
        validate(ip, emptyMessage: "IP address cannot be empty") {
            let expanded = "^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::1$|^::$"
            let compressed = "^([0-9a-fA-F]{1,4}:)*::([0-9a-fA-F]{1,4}:)*[0-9a-fA-F]{1,4}$"
            return matches($0, expanded) || matches($0, compressed) ? nil : "Invalid IPv6 address format"
        }
    }

    static func validateTTL(_ ttl: Int) -> ValidationResult {
        validate(
            ttl,
            in: Constants.TTL.minimum ... Constants.TTL.maximum,
            message:
            "TTL must be between \(Constants.TTL.minimum) and \(Constants.TTL.maximum) seconds"
        )
    }

    static func validateMXPriority(_ priority: Int) -> ValidationResult {
        validate(priority, in: 0 ... 65535, message: "MX priority must be between 0 and 65535")
    }

    static func validateSRVPort(_ port: Int) -> ValidationResult {
        validate(port, in: 1 ... 65535, message: "Port must be between 1 and 65535")
    }

    // MARK: - Credential Validation

    static func validateCloudflareToken(_ token: String) -> ValidationResult {
        validate(token, emptyMessage: "API token cannot be empty") {
            if $0.count < 20 { return "API token appears to be too short" }
            return matches($0, "^[a-zA-Z0-9_-]+$") ? nil : "API token contains invalid characters"
        }
    }

    static func validateAWSAccessKey(_ accessKey: String) -> ValidationResult {
        validate(accessKey, emptyMessage: "Access key cannot be empty") {
            matches($0, "^AKIA[0-9A-Z]{16}$") ? nil : "Invalid AWS access key format"
        }
    }

    static func validateAWSSecretKey(_ secretKey: String) -> ValidationResult {
        validate(secretKey, emptyMessage: "Secret key cannot be empty") {
            $0.count == 40 ? nil : "Invalid AWS secret key length"
        }
    }
}

enum ValidationResult {
    case valid
    case invalid(String)

    var isValid: Bool {
        switch self {
        case .valid: true
        case .invalid: false
        }
    }

    var errorMessage: String? {
        switch self {
        case .valid: nil
        case let .invalid(message): message
        }
    }
}
