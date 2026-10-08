
import Foundation

/// Helper utilities for DNS record operations
enum DNSRecordHelpers {
    /// Returns the appropriate placeholder text for the DNS record name field based on record type
    /// - Parameter recordType: The DNS record type (e.g., "A", "CNAME", "SRV")
    /// - Returns: A user-friendly placeholder string with example input
    static func namePlaceholder(for recordType: String) -> String {
        switch recordType {
        case "SRV":
            AppLocalization.string("Record name (e.g. _sip._tcp)")
        default:
            AppLocalization.string("Record name (e.g. @ or www)")
        }
    }

    /// Returns a human-readable label for a DNS record type
    /// - Parameter recordType: The DNS record type code (e.g., "A", "CNAME", "SRV")
    /// - Returns: A formatted label with description (e.g., "A — IPv4")
    static func typeLabel(for recordType: String) -> String {
        switch recordType {
        case "A":
            "A — IPv4"
        case "AAAA":
            "AAAA — IPv6"
        case "CNAME":
            "CNAME — Alias"
        case "MX":
            "MX — Mail exchange"
        case "TXT":
            "TXT — Text record"
        case "NS":
            "NS — Nameserver"
        case "SRV":
            "SRV — Service locator"
        case "PTR":
            "PTR — Reverse pointer"
        case "CAA":
            "CAA — Certificate authority"
        default:
            recordType.uppercased()
        }
    }

    /// Validates form data for a DNS record
    /// - Parameters:
    ///   - type: The DNS record type
    ///   - name: The record name (should already be trimmed)
    ///   - contentValue: The content value (can be nil for complex types)
    ///   - recordData: The structured record data for complex types (SRV, CAA)
    /// - Returns: Whether the form data is valid
    static func isFormValid(type: String, name: String, contentValue: String?, recordData: RecordData?) -> Bool {
        guard !name.isEmpty else { return false }

        switch type {
        case "SRV":
            return recordData != nil
        case "PTR":
            return contentValue != nil
        case "CAA":
            return recordData != nil
        default:
            return contentValue != nil
        }
    }

    /// Computes the content value for a DNS record based on its type
    /// - Parameters:
    ///   - type: The DNS record type
    ///   - content: The raw content string
    ///   - ptrHostname: The PTR hostname (for PTR records)
    /// - Returns: The computed content value, or nil if empty
    static func contentValue(for type: String, content: String, ptrHostname: String) -> String? {
        switch type {
        case "SRV":
            return nil
        case "PTR":
            let trimmed = ptrHostname.trimmed
            return trimmed.isEmpty ? nil : trimmed
        case "CAA":
            return nil
        default:
            let trimmed = content.trimmed
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Builds structured record data for complex DNS record types (SRV, CAA)
    /// - Parameters:
    ///   - type: The DNS record type
    ///   - srvService: SRV service name
    ///   - srvProto: SRV protocol
    ///   - srvDomain: SRV domain name
    ///   - srvPriority: SRV priority
    ///   - srvWeight: SRV weight
    ///   - srvPort: SRV port
    ///   - srvTarget: SRV target
    ///   - caaFlags: CAA flags
    ///   - caaTag: CAA tag
    ///   - caaValue: CAA value
    /// - Returns: RecordData if valid, nil otherwise
    static func recordData(
        for type: String,
        srvService: String,
        srvProto: String,
        srvDomain: String,
        srvPriority: Int,
        srvWeight: Int,
        srvPort: Int,
        srvTarget: String,
        caaFlags: Int,
        caaTag: String,
        caaValue: String
    ) -> RecordData? {
        switch type {
        case "SRV":
            let service = srvService.trimmed
            let domain = srvDomain.trimmed
            let target = srvTarget.trimmed
            guard service.isNotEmpty, domain.isNotEmpty, target.isNotEmpty else { return nil }
            return RecordData(
                service: service,
                proto: srvProto,
                name: domain,
                priority: srvPriority,
                weight: srvWeight,
                port: srvPort,
                target: target,
                flags: nil,
                tag: nil,
                value: nil
            )
        case "CAA":
            let value = caaValue.trimmed
            guard value.isNotEmpty else { return nil }
            return RecordData(
                service: nil,
                proto: nil,
                name: nil,
                priority: nil,
                weight: nil,
                port: nil,
                target: nil,
                flags: caaFlags,
                tag: caaTag,
                value: value
            )
        default:
            return nil
        }
    }
}
