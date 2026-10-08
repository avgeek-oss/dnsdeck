import Foundation

struct NamecheapDomain: Codable, Hashable {
    let id: String
    let name: String
    let sld: String
    let tld: String
    let isExpired: Bool
    let isLocked: Bool
    let autoRenew: Bool
    let isOurDNS: Bool
    let created: String?
    let expires: String?
    var nameservers: [String]

    func snapshot() -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: id,
            name: name,
            nameservers: nameservers,
            status: isExpired ? "Expired" : nil,
            metadata: [
                "autoRenew": String(autoRenew),
                "created": created,
                "expires": expires,
                "isLocked": String(isLocked),
                "isOurDNS": String(isOurDNS),
                "sld": sld,
                "tld": tld,
            ].compactMapValues { $0 },
            providerData: providerSnapshotData
        )
    }
}

struct NamecheapHost: Codable, Hashable {
    let hostId: String
    let name: String
    let type: String
    let address: String
    let mxPreference: Int?
    let ttl: Int

    func snapshot(zoneName: String) -> ProviderRecordSnapshot {
        let type = type.uppercased()
        let displayContent = switch type {
        case "CAA": namecheapCAADisplayContent(address)
        case "TXT": ProviderRecordValue.parseQuotedTXT(address, allowEmpty: true)
        default: address
        }
        return ProviderRecordSnapshot(
            id: hostId,
            name: ProviderDNSName.absolute(name, in: zoneName, caseInsensitive: true),
            type: type,
            values: [displayContent],
            displayContent: displayContent,
            ttl: ttl,
            priority: type == "MX" ? mxPreference : nil,
            aliasTarget: type == "ALIAS"
                ? DNSAliasTarget(name: address, zoneId: nil, evaluateTargetHealth: nil)
                : nil,
            metadata: ["nativeName": name],
            providerData: providerSnapshotData
        )
    }

    var isSafelyRoundTrippable: Bool {
        Self.roundTrippableTypes.contains(type.uppercased())
    }

    var verificationKey: NamecheapHostVerificationKey {
        let type = type.uppercased()
        return NamecheapHostVerificationKey(
            name: name.lowercased(),
            type: type,
            address: normalizedAddress(for: type),
            mxPreference: type == "MX" ? mxPreference ?? 10 : nil,
            ttl: ttl
        )
    }

    private func normalizedAddress(for type: String) -> String {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case "AAAA":
            return value.lowercased()
        case "ALIAS", "CNAME", "NS":
            return value.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        case "TXT":
            return ProviderRecordValue.parseQuotedTXT(value, allowEmpty: true)
        default:
            return value
        }
    }

    private static let roundTrippableTypes: Set = [
        "A", "AAAA", "ALIAS", "CAA", "CNAME", "NS", "TXT", "URL", "URL301",
    ]
}

struct NamecheapHostVerificationKey: Hashable {
    let name: String
    let type: String
    let address: String
    let mxPreference: Int?
    let ttl: Int

    var summary: String {
        "\(type) \(name) \(address) priority=\(mxPreference.map(String.init) ?? "-") ttl=\(ttl)"
    }
}

extension CreateProviderRecordRequest {
    func toNamecheapHosts(zoneName: String) throws -> [NamecheapHost] {
        let type = normalizedType
        try DNSProvider.namecheap.validateEditableRecordType(type)
        let name = ProviderDNSName.relativeAtCaseInsensitive(name, zoneName: zoneName)
        let ttl = DNSProvider.namecheap.getEffectiveTTL(ttl) ?? DNSProvider.namecheap.defaultTTL
        return try mutationValues.enumerated().map { index, value in
            let fields = try namecheapFields(
                type: type,
                content: value,
                recordData: recordData,
                preservesNativeContent: false
            )
            return NamecheapHost(
                hostId: "new-\(index)",
                name: name,
                type: type,
                address: fields.address,
                mxPreference: fields.mxPreference,
                ttl: ttl
            )
        }
    }
}

extension UpdateProviderRecordRequest {
    func toNamecheapHost(zoneName: String, existing: NamecheapHost) throws -> NamecheapHost {
        guard values == nil || values?.count == 1 else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .namecheap,
                type: type ?? existing.type,
                message: "an individual Namecheap host edit accepts exactly one value"
            )
        }

        let type = normalizedType(or: existing.type)
        try DNSProvider.namecheap.validateEditableRecordType(type)
        let hasContentEdits = hasValueEdits || type != existing.type.uppercased()
        let content = hasContentEdits ? mutationValues(or: [existing.address])[0] : existing.address
        let fields = try namecheapFields(
            type: type,
            content: content,
            recordData: recordData,
            preservesNativeContent: !hasContentEdits
        )

        return NamecheapHost(
            hostId: existing.hostId,
            name: name.map { ProviderDNSName.relativeAtCaseInsensitive($0, zoneName: zoneName) } ?? existing.name,
            type: type,
            address: fields.address,
            mxPreference: fields.mxPreference,
            ttl: DNSProvider.namecheap.normalizeTTL(ttl ?? existing.ttl) ?? DNSProvider.namecheap.defaultTTL
        )
    }
}

private func namecheapFields(
    type: String,
    content: String,
    recordData: RecordData?,
    preservesNativeContent: Bool
) throws -> (address: String, mxPreference: Int?) {
    guard type == "CAA", !preservesNativeContent else {
        return (content, nil)
    }
    guard let data = recordData ?? UpdateProviderRecordRequest.cloudflareCAAData(content: content),
          let flags = data.flags,
          let tag = data.tag,
          let value = data.value,
          (0 ... 255).contains(flags),
          ["issue", "issuewild", "iodef"].contains(tag)
    else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .namecheap,
            type: type,
            message: "expected flags, issue/issuewild/iodef tag, and value"
        )
    }
    let unquoted = value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2
        ? String(value.dropFirst().dropLast())
        : value
    let escaped = unquoted
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return ("\(flags) \(tag) \"\(escaped)\"", nil)
}

private func namecheapCAADisplayContent(_ address: String) -> String {
    guard let data = UpdateProviderRecordRequest.cloudflareCAAData(content: address),
          let flags = data.flags,
          let tag = data.tag,
          let value = data.value
    else {
        return address
    }
    return "\(flags) \(tag) \(value)"
}
