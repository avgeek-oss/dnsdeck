import AvgeekNetworking
import Foundation

final class HetznerService {
    private let client: ProviderHTTPClient
    private let sleep: ProviderHTTPClient.Sleep
    private let encoder = JSONEncoder()

    init(
        tokenProvider: @escaping () -> String?,
        baseURL: URL = URL(string: Configuration.API.hetznerBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        self.sleep = sleep
        client = ProviderHTTPClient(
            provider: .hetzner,
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: {
                guard let token = tokenProvider()?.trimmed, !token.isEmpty else {
                    throw ProviderAPIError.missingCredential(provider: .hetzner, field: "API token")
                }
                return ["Authorization": "Bearer \(token)"]
            },
            sleep: sleep
        )
    }

    func listZones() async throws -> [HetznerZone] {
        var zones: [HetznerZone] = []
        var page = 1
        var visitedPages: Set<Int> = []

        while page > 0 {
            guard visitedPages.insert(page).inserted, visitedPages.count <= 1000 else {
                throw ProviderAPIError.invalidURL(provider: .hetzner)
            }
            let response = try await client.send(
                method: "GET",
                pathComponents: ["zones"],
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "per_page", value: "50"),
                ],
                retryPolicy: .transientRead()
            )
            let envelope = try client.decode(HetznerZonesEnvelope.self, from: response)
            zones.append(contentsOf: envelope.zones)
            page = envelope.meta?.pagination?.nextPage ?? 0
        }

        return zones
    }

    func getZone(idOrName: String) async throws -> HetznerZone {
        let response = try await client.send(
            method: "GET",
            pathComponents: ["zones", idOrName],
            retryPolicy: .transientRead()
        )
        return try client.decode(HetznerZoneEnvelope.self, from: response).zone
    }

    func createZone(name: String) async throws -> HetznerZone {
        let body = try encoder.encode(
            HetznerCreateZoneRequest(name: name, mode: "primary", ttl: DNSProvider.hetzner.defaultTTL)
        )
        let response = try await client.send(method: "POST", pathComponents: ["zones"], body: body)
        let envelope = try client.decode(HetznerZoneCreateEnvelope.self, from: response)
        try await waitForAction(envelope.action)
        return try await getZone(idOrName: String(envelope.zone.id))
    }

    func deleteZone(idOrName: String) async throws {
        let response = try await client.send(
            method: "DELETE",
            pathComponents: ["zones", idOrName]
        )
        let envelope = try client.decode(HetznerActionEnvelope.self, from: response)
        try await waitForAction(envelope.action)
    }

    func listRRSets(zoneIdOrName: String) async throws -> [HetznerRRSet] {
        var rrsets: [HetznerRRSet] = []
        var page = 1
        var visitedPages: Set<Int> = []

        while page > 0 {
            guard visitedPages.insert(page).inserted, visitedPages.count <= 1000 else {
                throw ProviderAPIError.invalidURL(provider: .hetzner)
            }
            let response = try await client.send(
                method: "GET",
                pathComponents: ["zones", zoneIdOrName, "rrsets"],
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "per_page", value: "50"),
                ],
                retryPolicy: .transientRead()
            )
            let envelope = try client.decode(HetznerRRSetsEnvelope.self, from: response)
            rrsets.append(contentsOf: envelope.rrsets)
            page = envelope.meta?.pagination?.nextPage ?? 0
        }

        return rrsets
    }

    func createRRSet(
        zoneIdOrName: String,
        request: HetznerCreateRRSetRequest
    ) async throws -> HetznerRRSet {
        let response = try await client.send(
            method: "POST",
            pathComponents: ["zones", zoneIdOrName, "rrsets"],
            body: encoder.encode(request)
        )
        let envelope = try client.decode(HetznerRRSetCreateEnvelope.self, from: response)
        try await waitForAction(envelope.action)
        return envelope.rrset
    }

    func deleteRRSet(zoneIdOrName: String, rrset: HetznerRRSet) async throws {
        let response = try await client.send(
            method: "DELETE",
            pathComponents: ["zones", zoneIdOrName, "rrsets", rrset.name, rrset.type]
        )
        let envelope = try client.decode(HetznerActionEnvelope.self, from: response)
        try await waitForAction(envelope.action)
        try await waitForRRSet(
            zoneIdOrName: zoneIdOrName,
            name: rrset.name,
            type: rrset.type,
            operation: "record deletion"
        ) { $0 == nil }
    }

    func updateRRSet(
        zoneIdOrName: String,
        existing: HetznerRRSet,
        desired: HetznerRRSetDesiredState
    ) async throws {
        if desired.identityChanged {
            let replacement = HetznerCreateRRSetRequest(
                name: desired.name,
                type: desired.type,
                ttl: desired.ttl,
                labels: desired.labels,
                records: desired.records
            )
            _ = try await createRRSet(zoneIdOrName: zoneIdOrName, request: replacement)
            try await deleteRRSet(zoneIdOrName: zoneIdOrName, rrset: existing)
            return
        }

        if desired.recordsChanged {
            let response = try await client.send(
                method: "POST",
                pathComponents: [
                    "zones", zoneIdOrName, "rrsets", existing.name, existing.type, "actions", "set_records",
                ],
                body: encoder.encode(HetznerSetRecordsRequest(records: desired.records))
            )
            try await waitForAction(client.decode(HetznerActionEnvelope.self, from: response).action)
        }

        if desired.ttlChanged {
            let response = try await client.send(
                method: "POST",
                pathComponents: [
                    "zones", zoneIdOrName, "rrsets", existing.name, existing.type, "actions", "change_ttl",
                ],
                body: encoder.encode(HetznerChangeTTLRequest(ttl: desired.ttl))
            )
            try await waitForAction(client.decode(HetznerActionEnvelope.self, from: response).action)
        }

        if desired.recordsChanged || desired.ttlChanged {
            try await waitForRRSet(
                zoneIdOrName: zoneIdOrName,
                name: desired.name,
                type: desired.type,
                operation: "record update"
            ) { rrset in
                guard let rrset else { return false }
                if desired.recordsChanged,
                   Self.comparableRecords(rrset.records) != Self.comparableRecords(desired.records)
                {
                    return false
                }
                return !desired.ttlChanged || rrset.ttl == desired.ttl
            }
        }
    }

    private func waitForRRSet(
        zoneIdOrName: String,
        name: String,
        type: String,
        operation: String,
        matches: (HetznerRRSet?) -> Bool
    ) async throws {
        var consecutiveMatches = 0
        for poll in 0 ..< 60 {
            let rrset = try await listRRSets(zoneIdOrName: zoneIdOrName).first {
                $0.name.caseInsensitiveCompare(name) == .orderedSame &&
                    $0.type.caseInsensitiveCompare(type) == .orderedSame
            }
            if matches(rrset) {
                consecutiveMatches += 1
                if consecutiveMatches == 3 {
                    return
                }
            } else {
                consecutiveMatches = 0
            }
            guard poll < 59 else { break }
            try await sleep(0.5)
        }

        throw ProviderAPIError.operationTimedOut(provider: .hetzner, operation: operation)
    }

    private static func comparableRecords(_ records: [HetznerRRSetRecord]) -> [String] {
        records.map {
            "\($0.value)\u{0}\(($0.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines))"
        }.sorted()
    }

    private func waitForAction(_ initialAction: HetznerAction) async throws {
        var action = initialAction

        for poll in 0 ..< 60 {
            switch action.status {
            case "success":
                return
            case "error":
                throw ProviderAPIError.actionFailed(
                    provider: .hetzner,
                    actionId: action.id,
                    code: action.error?.code,
                    message: action.error?.message
                )
            default:
                break
            }

            if poll > 0 || action.status != nil {
                try await sleep(0.5)
            }
            let response = try await client.send(
                method: "GET",
                pathComponents: ["actions", String(action.id)],
                retryPolicy: .transientRead()
            )
            action = try client.decode(HetznerActionEnvelope.self, from: response).action
        }

        throw ProviderAPIError.actionTimedOut(provider: .hetzner, actionId: action.id)
    }
}
