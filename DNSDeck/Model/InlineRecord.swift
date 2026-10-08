#if os(macOS)
import Foundation

struct InlineRecord: Identifiable {
    var id = UUID()
    var type: String
    var name = ""
    var value = ""
    var ttl = ""
    var proxied = false
    var validationErrors: [String: String] = [:]

    init(type: String = "A") {
        self.type = type
    }

    var hasErrors: Bool {
        !validationErrors.isEmpty
    }

    mutating func runValidation() {
        validationErrors = Self.validate(self)
    }

    static func validate(_ record: InlineRecord) -> [String: String] {
        var errors: [String: String] = [:]
        let name = record.name.trimmed
        if name.isEmpty {
            errors["name"] = "Name is required"
        } else if let message = validateRecordName(name) {
            errors["name"] = message
        }

        validateRequired(record.value, field: "value", label: valueLabel(for: record.type), errors: &errors)
        if errors["value"] == nil {
            switch record.type {
            case "A":
                errors["value"] = InputValidator.validateIPv4Address(record.value).errorMessage
            case "AAAA":
                errors["value"] = InputValidator.validateIPv6Address(record.value).errorMessage
            case "CNAME":
                errors["value"] = validateDomain(record.value)
            case "TXT" where record.value.trimmed.count > 2048:
                errors["value"] = "TXT record exceeds 2048 characters"
            default:
                break
            }
        }

        let ttl = record.ttl.trimmed
        if !ttl.isEmpty {
            errors["ttl"] = Int(ttl).map { InputValidator.validateTTL($0).errorMessage } ??
                "TTL must be a number"
        }
        return errors
    }

    func toCreateProviderRecordRequest(provider: DNSProvider) -> CreateProviderRecordRequest {
        let ttl = ttl.trimmed
        var content = value.trimmed
        if type == "TXT", !content.hasPrefix("\"") || !content.hasSuffix("\"") {
            content = "\"\(content)\""
        }
        return CreateProviderRecordRequest(
            name: name.trimmed,
            type: type,
            content: content,
            ttl: ttl.isEmpty ? (provider.supportsAutoTTL ? Constants.TTL.automatic : nil) : Int(ttl),
            proxied: Constants.DNSRecordTypes.proxyableTypes.contains(type) ? proxied : nil,
            priority: nil,
            comment: nil
        )
    }

    private static func valueLabel(for type: String) -> String {
        switch type {
        case "A", "AAAA": "IP address"
        case "CNAME": "Domain"
        case "TXT": "Text value"
        default: "Value"
        }
    }

    private static func validateRequired(
        _ value: String,
        field: String,
        label: String,
        errors: inout [String: String]
    ) {
        if value.trimmed.isEmpty {
            errors[field] = "\(label) is required"
        }
    }

    private static func validateRecordName(_ name: String) -> String? {
        if name == "@" || name == "*" { return nil }
        if name.count > 253 { return "Name too long (max 253 characters)" }
        let labels = (name.hasSuffix(".") ? name.dropLast() : Substring(name))
            .split(separator: ".", omittingEmptySubsequences: false)
        let predicate = NSPredicate(
            format: "SELF MATCHES %@",
            "^[a-zA-Z0-9_*]([a-zA-Z0-9\\-_]*[a-zA-Z0-9_])?$"
        )
        for label in labels {
            if label.isEmpty { return "Invalid DNS name format" }
            if label.count > 63 { return "Label exceeds 63 characters" }
            if !predicate.evaluate(with: String(label)) { return "Invalid DNS name format" }
        }
        return nil
    }

    private static func validateDomain(_ value: String) -> String? {
        let value = value.trimmed
        let domain = value.hasSuffix(".") ? String(value.dropLast()) : value
        let predicate = NSPredicate(
            format: "SELF MATCHES %@",
            "^([a-zA-Z0-9_]([a-zA-Z0-9\\-_]*[a-zA-Z0-9_])?\\.)+[a-zA-Z]{2,}$"
        )
        return predicate.evaluate(with: domain) ? nil : "Invalid domain format"
    }
}
#endif
