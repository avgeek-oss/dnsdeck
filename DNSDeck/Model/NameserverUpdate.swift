import Foundation

enum NameserverUpdateError: LocalizedError, Equatable {
    case countOutsideRange(minimum: Int, maximum: Int)
    case duplicate(String)
    case invalidHostname(String)

    var errorDescription: String? {
        switch self {
        case let .countOutsideRange(minimum, maximum):
            String(localized: "Enter between \(minimum) and \(maximum) nameservers.")
        case let .duplicate(hostname):
            String(localized: "Nameserver \"\(hostname)\" is listed more than once.")
        case let .invalidHostname(hostname):
            String(localized: "\"\(hostname)\" is not a valid nameserver hostname.")
        }
    }
}

enum NameserverUpdate {
    static func normalize(
        _ values: [String],
        policy: ProviderNameserverPolicy = .standard
    ) throws -> [String] {
        let nameservers = values.map { value in
            let hostname = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return hostname.hasSuffix(".") ? String(hostname.dropLast()) : hostname
        }

        guard (policy.minimumCount ... policy.maximumCount).contains(nameservers.count) else {
            throw NameserverUpdateError.countOutsideRange(
                minimum: policy.minimumCount,
                maximum: policy.maximumCount
            )
        }

        var seen: Set<String> = []
        for nameserver in nameservers {
            guard isValidHostname(nameserver) else {
                throw NameserverUpdateError.invalidHostname(nameserver)
            }
            guard seen.insert(nameserver).inserted else {
                throw NameserverUpdateError.duplicate(nameserver)
            }
        }

        return nameservers
    }

    private static func isValidHostname(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253, value.contains(".") else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        guard !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return false }

        return labels.allSatisfy { label in
            guard !label.isEmpty, label.count <= 63,
                  label.first != "-", label.last != "-"
            else { return false }
            return label.allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber || character == "-")
            }
        }
    }
}

extension DNSProvider {
    var nameserverPolicy: ProviderNameserverPolicy? {
        guard definition.capabilities.zoneCapabilities.contains(.updateNameservers) else { return nil }
        return .standard
    }

    func supportsNameserverUpdate(for zone: ProviderZone) -> Bool {
        guard zone.provider == self, nameserverPolicy != nil else { return false }
        guard self == .scaleway else { return true }
        let snapshot = zone.zoneData.snapshot
        return snapshot.metadata["domain"]?.caseInsensitiveCompare(snapshot.name) == .orderedSame
    }
}
