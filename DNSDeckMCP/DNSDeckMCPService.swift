import Foundation

struct DNSDeckMCPService {
    private let environmentStore: DNSDeckMCPEnvironmentStore
    private let cache: DNSDeckMCPCache

    init(
        environmentStore: DNSDeckMCPEnvironmentStore = DNSDeckMCPEnvironmentStore(),
        cache: DNSDeckMCPCache = DNSDeckMCPCache()
    ) {
        self.environmentStore = environmentStore
        self.cache = cache
    }

    func policy() -> [String: Any] {
        [
            "schemaVersion": "dnsdeck.mcp.policy.v1",
            "transport": "stdio",
            "writeToolsEnabled": true,
            "destructiveToolsExposed": true,
            "credentialValuesExposed": false,
            "requiresHostToolApproval": true,
            "notes": [
                "Zone creation, nameserver updates, and record add, edit, and delete tools use DNSDeck's configured providers and stored credentials.",
                "Provider credential values are never returned.",
                "Nameserver updates and delete operations require confirm=true. Every mutation is written to the local redacted MCP audit log.",
            ],
        ]
    }

    func viewEnvironments(includeProviderConnections: Bool) -> [String: Any] {
        let environments = environmentStore.loadEnvironments().map { environment -> [String: Any] in
            var value = environmentJSON(environment)
            if includeProviderConnections {
                value["providers"] = listProviderConnections(environmentId: environment.id).filter {
                    $0["connected"] as? Bool == true
                }
            }
            return value
        }

        return [
            "schemaVersion": "dnsdeck.mcp.environments.v1",
            "environments": environments,
        ]
    }

    func viewDNSZones(arguments: [String: Any]) async -> [String: Any] {
        do {
            let environmentId = try resolveEnvironmentId(arguments: arguments)
            let provider = try providerArgument(arguments: arguments, zoneId: arguments["zoneId"] as? String)

            if let provider,
               !provider.isConnected(environmentId: environmentId)
            {
                return toolError(
                    code: "MISSING_CREDENTIAL",
                    message: "\(provider.displayName) is not connected in this environment.",
                    provider: provider.rawValue,
                    environmentId: environmentId.uuidString
                )
            }

            return await listZones(
                environmentId: environmentId,
                provider: provider,
                forceRefresh: arguments["forceRefresh"] as? Bool ?? false
            )
        } catch let error as DNSDeckMCPToolResponseError {
            return error.response
        } catch {
            return toolError(code: mapErrorCode(error), message: error.localizedDescription)
        }
    }

    func addDNSZone(arguments: [String: Any]) async -> [String: Any] {
        do {
            let environmentId = try resolveEnvironmentId(arguments: arguments)
            let provider = try requiredProviderArgument(arguments: arguments)

            guard provider.isConnected(environmentId: environmentId) else {
                return toolError(
                    code: "MISSING_CREDENTIAL",
                    message: "\(provider.displayName) is not connected in this environment.",
                    provider: provider.rawValue,
                    environmentId: environmentId.uuidString
                )
            }

            guard provider.supportsZoneCreation else {
                return toolError(
                    code: "UNSUPPORTED_OPERATION",
                    message: "\(provider.displayName) does not support zone creation through DNSDeck.",
                    provider: provider.rawValue,
                    environmentId: environmentId.uuidString
                )
            }

            let zoneName = try createZoneName(arguments: arguments)
            let registry = ProviderServiceFactory.makeServices(environmentId: environmentId)
            let service = try registry.service(for: provider)
            let createdZone = try await service.createZone(named: zoneName, environmentId: environmentId)
            await cache.invalidateZones(environmentId: environmentId, provider: provider)

            var zones: [[String: Any]] = []
            var errors: [[String: Any]] = []
            do {
                let refreshedZones = try await cache.zones(
                    environmentId: environmentId,
                    provider: provider,
                    forceRefresh: true
                ) {
                    try await service.listZones(environmentId: environmentId)
                }
                zones = refreshedZones.map(zoneJSON)
            } catch {
                errors.append(providerErrorJSON(provider: provider, operation: "listZones", error: error))
            }

            return [
                "schemaVersion": "dnsdeck.mcp.zoneMutation.v1",
                "operation": "add",
                "environmentId": environmentId.uuidString,
                "provider": provider.rawValue,
                "zone": zoneJSON(createdZone),
                "zones": zones,
                "errors": errors,
            ]
        } catch let error as DNSDeckMCPToolResponseError {
            return error.response
        } catch {
            return toolError(code: mapErrorCode(error), message: error.localizedDescription)
        }
    }

    func updateDNSZoneNameservers(arguments: [String: Any]) async -> [String: Any] {
        do {
            guard arguments["confirm"] as? Bool == true else {
                throw DNSDeckMCPToolResponseError(toolError(
                    code: "CONFIRMATION_REQUIRED",
                    message: "Set confirm=true to update registrar nameservers."
                ))
            }

            let environmentId = try resolveEnvironmentId(arguments: arguments)
            let provider = try providerArgument(arguments: arguments, zoneId: arguments["zoneId"] as? String)
            let resolved = try await resolveZone(
                environmentId: environmentId,
                provider: provider,
                zoneId: arguments["zoneId"] as? String,
                zoneName: arguments["zoneName"] as? String,
                forceRefresh: arguments["forceRefresh"] as? Bool ?? false
            )

            guard resolved.provider.supportsNameserverUpdate(for: resolved.zone) else {
                let code = resolved.provider.nameserverPolicy == nil ? "UNSUPPORTED_OPERATION" : "READ_ONLY_ZONE"
                return toolError(
                    code: code,
                    message: "\(resolved.provider.displayName) cannot update registrar nameservers for this zone through DNSDeck.",
                    provider: resolved.provider.rawValue,
                    environmentId: environmentId.uuidString,
                    zoneId: resolved.zone.id
                )
            }

            let nameservers = try nameserverValues(arguments: arguments, provider: resolved.provider)
            try await resolved.service.updateNameservers(for: resolved.zone, nameservers: nameservers)
            await cache.invalidateZones(environmentId: environmentId, provider: resolved.provider)

            var zone = zoneJSON(resolved.zone)
            zone["nameservers"] = nameservers
            var zones: [[String: Any]] = []
            var errors: [[String: Any]] = []

            do {
                let refreshedZones = try await cache.zones(
                    environmentId: environmentId,
                    provider: resolved.provider,
                    forceRefresh: true
                ) {
                    try await resolved.service.listZones(environmentId: environmentId)
                }
                zones = refreshedZones.map(zoneJSON)
                if let refreshedZone = findZone(
                    in: refreshedZones,
                    zoneId: resolved.zone.id,
                    zoneName: resolved.zone.name
                ) {
                    zone = zoneJSON(refreshedZone)
                }
            } catch {
                errors.append(providerErrorJSON(
                    provider: resolved.provider,
                    operation: "listZones",
                    error: error
                ))
            }

            return [
                "schemaVersion": "dnsdeck.mcp.zoneMutation.v1",
                "operation": "updateNameservers",
                "environmentId": environmentId.uuidString,
                "provider": resolved.provider.rawValue,
                "zone": zone,
                "nameservers": nameservers,
                "zones": zones,
                "errors": errors,
            ]
        } catch let error as DNSDeckMCPToolResponseError {
            return error.response
        } catch {
            return toolError(code: mapErrorCode(error), message: error.localizedDescription)
        }
    }

    func readDNSZoneRecords(arguments: [String: Any]) async -> [String: Any] {
        do {
            let environmentId = try resolveEnvironmentId(arguments: arguments)
            let provider = try providerArgument(arguments: arguments, zoneId: arguments["zoneId"] as? String)
            let resolved = try await resolveZone(
                environmentId: environmentId,
                provider: provider,
                zoneId: arguments["zoneId"] as? String,
                zoneName: arguments["zoneName"] as? String,
                forceRefresh: arguments["forceRefresh"] as? Bool ?? false
            )
            let records = try await records(for: resolved, forceRefresh: arguments["forceRefresh"] as? Bool ?? false)

            return [
                "schemaVersion": "dnsdeck.mcp.records.v1",
                "environmentId": environmentId.uuidString,
                "provider": resolved.provider.rawValue,
                "zone": zoneJSON(resolved.zone),
                "records": records.map(recordJSON),
            ]
        } catch let error as DNSDeckMCPToolResponseError {
            return error.response
        } catch {
            return toolError(code: mapErrorCode(error), message: error.localizedDescription)
        }
    }

    func addDNSZoneRecord(arguments: [String: Any]) async -> [String: Any] {
        do {
            let environmentId = try resolveEnvironmentId(arguments: arguments)
            let provider = try providerArgument(arguments: arguments, zoneId: arguments["zoneId"] as? String)
            let resolved = try await resolveZone(
                environmentId: environmentId,
                provider: provider,
                zoneId: arguments["zoneId"] as? String,
                zoneName: arguments["zoneName"] as? String,
                forceRefresh: arguments["forceRefresh"] as? Bool ?? false
            )
            let payload = try createRecordPayload(arguments: arguments, provider: resolved.provider)

            try await resolved.service.createRecord(in: resolved.zone, payload: payload)
            await cache.invalidateRecords(environmentId: environmentId, zone: resolved.zone)

            return try await mutationResult(
                operation: "add",
                environmentId: environmentId,
                resolved: resolved
            )
        } catch let error as DNSDeckMCPToolResponseError {
            return error.response
        } catch {
            return toolError(code: mapErrorCode(error), message: error.localizedDescription)
        }
    }

    func editDNSZoneRecord(arguments: [String: Any]) async -> [String: Any] {
        do {
            let environmentId = try resolveEnvironmentId(arguments: arguments)
            let provider = try providerArgument(arguments: arguments, zoneId: arguments["zoneId"] as? String)
            let resolved = try await resolveZone(
                environmentId: environmentId,
                provider: provider,
                zoneId: arguments["zoneId"] as? String,
                zoneName: arguments["zoneName"] as? String,
                forceRefresh: arguments["forceRefresh"] as? Bool ?? false
            )
            let records = try await records(for: resolved, forceRefresh: arguments["forceRefresh"] as? Bool ?? false)
            let record = try resolveRecord(
                in: records,
                environmentId: environmentId,
                provider: resolved.provider,
                zone: resolved.zone,
                recordId: arguments["recordId"] as? String,
                recordName: arguments["recordName"] as? String,
                recordType: arguments["recordType"] as? String
            )

            guard record.isEditable else {
                throw DNSDeckMCPToolResponseError(toolError(
                    code: "READ_ONLY_RECORD",
                    message: "This provider record is not editable through DNSDeck.",
                    provider: resolved.provider.rawValue,
                    environmentId: environmentId.uuidString,
                    zoneId: resolved.zone.id,
                    recordId: record.id
                ))
            }

            let edits = try updateRecordPayload(arguments: arguments, provider: resolved.provider, record: record)
            try await resolved.service.updateRecord(in: resolved.zone, record: record, edits: edits)
            await cache.invalidateRecords(environmentId: environmentId, zone: resolved.zone)

            return try await mutationResult(
                operation: "edit",
                environmentId: environmentId,
                resolved: resolved
            )
        } catch let error as DNSDeckMCPToolResponseError {
            return error.response
        } catch {
            return toolError(code: mapErrorCode(error), message: error.localizedDescription)
        }
    }

    func deleteDNSZoneRecord(arguments: [String: Any]) async -> [String: Any] {
        do {
            guard arguments["confirm"] as? Bool == true else {
                throw DNSDeckMCPToolResponseError(toolError(
                    code: "CONFIRMATION_REQUIRED",
                    message: "Set confirm=true to delete a DNS record."
                ))
            }

            let environmentId = try resolveEnvironmentId(arguments: arguments)
            let provider = try providerArgument(arguments: arguments, zoneId: arguments["zoneId"] as? String)
            let resolved = try await resolveZone(
                environmentId: environmentId,
                provider: provider,
                zoneId: arguments["zoneId"] as? String,
                zoneName: arguments["zoneName"] as? String,
                forceRefresh: arguments["forceRefresh"] as? Bool ?? false
            )
            let records = try await records(for: resolved, forceRefresh: arguments["forceRefresh"] as? Bool ?? false)
            let record = try resolveRecord(
                in: records,
                environmentId: environmentId,
                provider: resolved.provider,
                zone: resolved.zone,
                recordId: arguments["recordId"] as? String,
                recordName: arguments["recordName"] as? String,
                recordType: arguments["recordType"] as? String
            )

            guard record.isEditable else {
                throw DNSDeckMCPToolResponseError(toolError(
                    code: "READ_ONLY_RECORD",
                    message: "This provider record is not editable through DNSDeck.",
                    provider: resolved.provider.rawValue,
                    environmentId: environmentId.uuidString,
                    zoneId: resolved.zone.id,
                    recordId: record.id
                ))
            }

            try await resolved.service.deleteRecord(in: resolved.zone, record: record)
            await cache.invalidateRecords(environmentId: environmentId, zone: resolved.zone)

            return try await mutationResult(
                operation: "delete",
                environmentId: environmentId,
                resolved: resolved
            )
        } catch let error as DNSDeckMCPToolResponseError {
            return error.response
        } catch {
            return toolError(code: mapErrorCode(error), message: error.localizedDescription)
        }
    }

    func listProviders() -> [[String: Any]] {
        DNSProvider.allCases.map(providerJSON)
    }

    func getProvider(_ provider: DNSProvider) -> [String: Any] {
        providerJSON(provider)
    }

    func listEnvironments() -> [[String: Any]] {
        environmentStore.loadEnvironments().map(environmentJSON)
    }

    func listProviderConnections(environmentId: UUID) -> [[String: Any]] {
        DNSProvider.allCases.map { provider in
            let credentials = provider.storedCredentials(environmentId: environmentId)
            let fields = provider.credentialFields.map { field -> [String: Any] in
                let value = credentials[field.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return [
                    "id": field.id,
                    "label": localized(field.label),
                    "kind": credentialKind(field.kind),
                    "isRequired": field.isRequired,
                    "present": !value.isEmpty,
                ]
            }

            return [
                "provider": provider.rawValue,
                "displayName": provider.displayName,
                "connected": provider.isConnected(environmentId: environmentId),
                "credentialFields": fields,
            ]
        }
    }

    func listZones(
        environmentId: UUID,
        provider requestedProvider: DNSProvider?,
        forceRefresh: Bool
    ) async -> [String: Any] {
        let providers = requestedProvider.map { [$0] } ?? DNSProvider.allCases
        let registry = ProviderServiceFactory.makeServices(environmentId: environmentId)
        var zones: [[String: Any]] = []
        var errors: [[String: Any]] = []

        for provider in providers {
            guard provider.isConnected(environmentId: environmentId) else {
                continue
            }

            do {
                let service = try registry.service(for: provider)
                let providerZones = try await cache.zones(
                    environmentId: environmentId,
                    provider: provider,
                    forceRefresh: forceRefresh
                ) {
                    try await service.listZones(environmentId: environmentId)
                }
                zones.append(contentsOf: providerZones.map(zoneJSON))
            } catch {
                errors.append(providerErrorJSON(provider: provider, operation: "listZones", error: error))
            }
        }

        return [
            "schemaVersion": "dnsdeck.mcp.zones.v1",
            "environmentId": environmentId.uuidString,
            "zones": zones,
            "errors": errors,
        ]
    }

    func listRecords(
        environmentId: UUID,
        provider: DNSProvider,
        zoneId: String?,
        zoneName: String?,
        forceRefresh: Bool
    ) async -> [String: Any] {
        guard provider.isConnected(environmentId: environmentId) else {
            return toolError(
                code: "MISSING_CREDENTIAL",
                message: "\(provider.displayName) is not connected in this environment.",
                provider: provider.rawValue,
                environmentId: environmentId.uuidString
            )
        }

        do {
            let registry = ProviderServiceFactory.makeServices(environmentId: environmentId)
            let service = try registry.service(for: provider)
            let zones = try await cache.zones(
                environmentId: environmentId,
                provider: provider,
                forceRefresh: forceRefresh
            ) {
                try await service.listZones(environmentId: environmentId)
            }

            guard let zone = findZone(in: zones, zoneId: zoneId, zoneName: zoneName) else {
                return toolError(
                    code: "ZONE_NOT_FOUND",
                    message: "No matching zone was found for \(provider.displayName).",
                    provider: provider.rawValue,
                    environmentId: environmentId.uuidString,
                    zoneId: zoneId
                )
            }

            let records = try await cache.records(
                environmentId: environmentId,
                zone: zone,
                forceRefresh: forceRefresh
            ) {
                try await service.records(for: zone)
            }

            return [
                "schemaVersion": "dnsdeck.mcp.records.v1",
                "environmentId": environmentId.uuidString,
                "provider": provider.rawValue,
                "zone": zoneJSON(zone),
                "records": records.map(recordJSON),
            ]
        } catch {
            return toolError(
                code: mapErrorCode(error),
                message: error.localizedDescription,
                provider: provider.rawValue,
                environmentId: environmentId.uuidString,
                zoneId: zoneId
            )
        }
    }

    func getRecord(
        environmentId: UUID,
        provider: DNSProvider,
        zoneId: String?,
        zoneName: String?,
        recordId: String?,
        recordName: String?,
        recordType: String?,
        forceRefresh: Bool
    ) async -> [String: Any] {
        let result = await listRecords(
            environmentId: environmentId,
            provider: provider,
            zoneId: zoneId,
            zoneName: zoneName,
            forceRefresh: forceRefresh
        )

        guard result["isError"] as? Bool != true,
              let records = result["records"] as? [[String: Any]]
        else {
            return result
        }

        let match = records.first { record in
            recordMatchesLookup(
                record,
                recordId: recordId,
                recordName: recordName,
                recordType: recordType
            )
        }

        guard let match else {
            return toolError(
                code: "RECORD_NOT_FOUND",
                message: "No matching record was found.",
                provider: provider.rawValue,
                environmentId: environmentId.uuidString,
                zoneId: zoneId,
                recordId: recordId
            )
        }

        return [
            "schemaVersion": "dnsdeck.mcp.record.v1",
            "environmentId": environmentId.uuidString,
            "provider": provider.rawValue,
            "zone": result["zone"] as Any,
            "record": match,
        ].removingNilValues()
    }

    func recordMatchesLookup(
        _ record: [String: Any],
        recordId: String?,
        recordName: String?,
        recordType: String?
    ) -> Bool {
        if let recordId, record["id"] as? String == recordId {
            return true
        }
        if let recordName,
           let candidateName = record["name"] as? String,
           candidateName.caseInsensitiveCompare(recordName) == .orderedSame
        {
            guard let recordType else { return true }
            return (record["type"] as? String)?.caseInsensitiveCompare(recordType) == .orderedSame
        }
        return false
    }

    func validateRecord(arguments: [String: Any]) -> [String: Any] {
        var errors: [[String: Any]] = []
        var warnings: [[String: Any]] = []

        guard let provider = provider(from: arguments["provider"]) else {
            return toolError(code: "INVALID_PROVIDER", message: "A valid provider is required.")
        }

        let name = arguments["name"] as? String ?? ""
        let type = (arguments["type"] as? String ?? "").uppercased()
        let content = arguments["content"] as? String
        let values = arguments["values"] as? [String] ?? content.map { [$0] } ?? []
        let ttl = arguments["ttl"] as? Int

        if let error = DNSRecordValidator.validateRecordName(name, allowEmpty: false) {
            errors.append(fieldError("name", error))
        }

        if type.isEmpty {
            errors.append(fieldError("type", "Type is required."))
        } else if !provider.capabilities.editableRecordTypes.contains(type) {
            errors.append(fieldError("type", "\(provider.displayName) does not support editing \(type) records."))
        }

        if values.isEmpty {
            errors.append(fieldError("content", "At least one record value is required."))
        } else {
            for value in values {
                if let error = DNSRecordValidator.validateRecordValue(type: type, rawValue: value) {
                    errors.append(fieldError("content", error))
                }
            }
        }

        let normalizedTTL = provider.normalizeTTL(ttl)
        if let ttl,
           normalizedTTL != ttl
        {
            warnings.append(fieldError("ttl", "TTL will be normalized to \(normalizedTTL ?? provider.defaultTTL)."))
        }

        return [
            "schemaVersion": "dnsdeck.mcp.validation.v1",
            "provider": provider.rawValue,
            "valid": errors.isEmpty,
            "normalizedTTL": normalizedTTL as Any,
            "errors": errors,
            "warnings": warnings,
        ].removingNilValues()
    }

    func provider(from value: Any?) -> DNSProvider? {
        guard let rawValue = value as? String else { return nil }
        return DNSProvider(rawValue: rawValue)
    }

    private func resolveEnvironmentId(arguments: [String: Any]) throws -> UUID {
        if let rawValue = trimmedString(arguments["environmentId"]) {
            guard let environmentId = UUID(uuidString: rawValue) else {
                throw DNSDeckMCPToolResponseError(toolError(
                    code: "INVALID_ENVIRONMENT",
                    message: "environmentId must be a valid DNSDeck environment UUID."
                ))
            }
            return environmentId
        }

        let environments = environmentStore.loadEnvironments()
        if environments.count == 1,
           let environment = environments.first
        {
            return environment.id
        }

        if environments.isEmpty {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "ENVIRONMENT_NOT_CONFIGURED",
                message: "No DNSDeck environments are configured."
            ))
        }

        throw DNSDeckMCPToolResponseError(toolError(
            code: "ENVIRONMENT_REQUIRED",
            message: "More than one DNSDeck environment is configured. Pass environmentId from dnsdeck_view_environments.",
            extra: ["environments": environments.map(environmentJSON)]
        ))
    }

    private func providerArgument(arguments: [String: Any], zoneId: String?) throws -> DNSProvider? {
        if let rawValue = trimmedString(arguments["provider"]) {
            guard let provider = DNSProvider(rawValue: rawValue) else {
                throw DNSDeckMCPToolResponseError(toolError(
                    code: "INVALID_PROVIDER",
                    message: "Unknown DNSDeck provider: \(rawValue)."
                ))
            }
            return provider
        }

        guard let zoneId,
              let providerPrefix = zoneId.split(separator: "|").first,
              providerPrefix.count < zoneId.count
        else {
            return nil
        }

        return DNSProvider(rawValue: String(providerPrefix))
    }

    private func requiredProviderArgument(arguments: [String: Any]) throws -> DNSProvider {
        guard let provider = try providerArgument(arguments: arguments, zoneId: nil) else {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "PROVIDER_REQUIRED",
                message: "Pass provider to create a DNS zone."
            ))
        }
        return provider
    }

    private func createZoneName(arguments: [String: Any]) throws -> String {
        guard let zoneName = trimmedString(arguments["zoneName"]) else {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "ZONE_NAME_REQUIRED",
                message: "Pass zoneName to create a DNS zone."
            ))
        }

        if let error = DNSRecordValidator.validateDomain(zoneName) {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "INVALID_ZONE_NAME",
                message: "The DNS zone name is invalid.",
                extra: ["errors": [fieldError("zoneName", error)]]
            ))
        }

        return zoneName
    }

    private func resolveZone(
        environmentId: UUID,
        provider requestedProvider: DNSProvider?,
        zoneId: String?,
        zoneName: String?,
        forceRefresh: Bool
    ) async throws -> DNSDeckMCPResolvedZone {
        guard zoneId != nil || zoneName != nil else {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "ZONE_REQUIRED",
                message: "Pass zoneId or zoneName."
            ))
        }

        let providers = try connectedProviders(environmentId: environmentId, requestedProvider: requestedProvider)
        let registry = ProviderServiceFactory.makeServices(environmentId: environmentId)
        var matches: [DNSDeckMCPResolvedZone] = []
        var providerErrors: [[String: Any]] = []

        for provider in providers {
            do {
                let service = try registry.service(for: provider)
                let zones = try await cache.zones(
                    environmentId: environmentId,
                    provider: provider,
                    forceRefresh: forceRefresh
                ) {
                    try await service.listZones(environmentId: environmentId)
                }
                if let zone = findZone(in: zones, zoneId: zoneId, zoneName: zoneName) {
                    matches.append(DNSDeckMCPResolvedZone(provider: provider, zone: zone, service: service))
                }
            } catch {
                providerErrors.append(providerErrorJSON(provider: provider, operation: "resolveZone", error: error))
            }
        }

        if matches.count == 1,
           let match = matches.first
        {
            return match
        }

        if matches.count > 1 {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "AMBIGUOUS_ZONE",
                message: "More than one connected provider matched the requested zone. Pass provider or a full zoneId.",
                environmentId: environmentId.uuidString,
                zoneId: zoneId,
                extra: ["matches": matches.map { zoneJSON($0.zone) }]
            ))
        }

        throw DNSDeckMCPToolResponseError(toolError(
            code: "ZONE_NOT_FOUND",
            message: "No matching DNSDeck zone was found.",
            environmentId: environmentId.uuidString,
            zoneId: zoneId,
            extra: providerErrors.isEmpty ? [:] : ["errors": providerErrors]
        ))
    }

    private func connectedProviders(
        environmentId: UUID,
        requestedProvider: DNSProvider?
    ) throws -> [DNSProvider] {
        if let requestedProvider {
            guard requestedProvider.isConnected(environmentId: environmentId) else {
                throw DNSDeckMCPToolResponseError(toolError(
                    code: "MISSING_CREDENTIAL",
                    message: "\(requestedProvider.displayName) is not connected in this environment.",
                    provider: requestedProvider.rawValue,
                    environmentId: environmentId.uuidString
                ))
            }
            return [requestedProvider]
        }

        let providers = DNSProvider.allCases.filter { $0.isConnected(environmentId: environmentId) }
        guard !providers.isEmpty else {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "PROVIDER_NOT_CONFIGURED",
                message: "No DNS providers are connected in this environment.",
                environmentId: environmentId.uuidString
            ))
        }
        return providers
    }

    private func records(
        for resolved: DNSDeckMCPResolvedZone,
        forceRefresh: Bool
    ) async throws -> [ProviderRecord] {
        try await cache.records(
            environmentId: resolved.zone.environmentId,
            zone: resolved.zone,
            forceRefresh: forceRefresh
        ) {
            try await resolved.service.records(for: resolved.zone)
        }
    }

    private func resolveRecord(
        in records: [ProviderRecord],
        environmentId: UUID,
        provider: DNSProvider,
        zone: ProviderZone,
        recordId: String?,
        recordName: String?,
        recordType: String?
    ) throws -> ProviderRecord {
        guard recordId != nil || recordName != nil else {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "RECORD_REQUIRED",
                message: "Pass recordId or recordName.",
                provider: provider.rawValue,
                environmentId: environmentId.uuidString,
                zoneId: zone.id
            ))
        }

        let normalizedRecordType = recordType?.uppercased()
        let matches = records.filter { record in
            if let recordId,
               record.id == recordId || record.recordData.id == recordId
            {
                return true
            }
            if let recordName,
               record.name.caseInsensitiveCompare(recordName) == .orderedSame
            {
                guard let normalizedRecordType else { return true }
                return record.type.uppercased() == normalizedRecordType
            }
            return false
        }

        if matches.count == 1,
           let record = matches.first
        {
            return record
        }

        if matches.count > 1 {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "AMBIGUOUS_RECORD",
                message: "More than one record matched. Pass recordId or recordType.",
                provider: provider.rawValue,
                environmentId: environmentId.uuidString,
                zoneId: zone.id,
                extra: ["matches": matches.map(recordJSON)]
            ))
        }

        throw DNSDeckMCPToolResponseError(toolError(
            code: "RECORD_NOT_FOUND",
            message: "No matching DNS record was found.",
            provider: provider.rawValue,
            environmentId: environmentId.uuidString,
            zoneId: zone.id,
            recordId: recordId
        ))
    }

    private func createRecordPayload(
        arguments: [String: Any],
        provider: DNSProvider
    ) throws -> CreateProviderRecordRequest {
        let name = trimmedString(arguments["name"]) ?? ""
        let type = (trimmedString(arguments["type"]) ?? "").uppercased()
        let values = stringArray(arguments["values"])
        let providedValues = values ?? trimmedString(arguments["content"]).map { [$0] } ?? []
        let content = trimmedString(arguments["content"]) ?? values?.first ?? ""
        let validation = validationResult(
            provider: provider,
            name: name,
            type: type,
            values: providedValues,
            ttl: intValue(arguments["ttl"])
        )

        guard validation["valid"] as? Bool == true else {
            throw DNSDeckMCPToolResponseError(invalidRecordPayload(validation))
        }

        return CreateProviderRecordRequest(
            name: name,
            type: type,
            content: content,
            ttl: intValue(arguments["ttl"]),
            proxied: arguments["proxied"] as? Bool,
            priority: intValue(arguments["priority"]),
            comment: trimmedString(arguments["comment"]),
            values: values,
            aliasTarget: trimmedString(arguments["aliasTarget"])
        )
    }

    private func updateRecordPayload(
        arguments: [String: Any],
        provider: DNSProvider,
        record: ProviderRecord
    ) throws -> UpdateProviderRecordRequest {
        let editKeys = ["name", "type", "content", "values", "ttl", "proxied", "priority", "comment", "aliasTarget"]
        guard editKeys.contains(where: { arguments[$0] != nil }) else {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "NO_CHANGES",
                message: "Pass at least one editable record field."
            ))
        }

        let name = trimmedString(arguments["name"])
        let type = trimmedString(arguments["type"])?.uppercased()
        let content = trimmedString(arguments["content"])
        let values = stringArray(arguments["values"])
        let proposedValues = values ?? content.map { [$0] } ?? record.values
        let validation = validationResult(
            provider: provider,
            name: name ?? record.name,
            type: type ?? record.type,
            values: proposedValues,
            ttl: intValue(arguments["ttl"]) ?? record.ttl
        )

        guard validation["valid"] as? Bool == true else {
            throw DNSDeckMCPToolResponseError(invalidRecordPayload(validation))
        }

        return UpdateProviderRecordRequest(
            name: name,
            type: type,
            content: content,
            ttl: intValue(arguments["ttl"]),
            proxied: arguments["proxied"] as? Bool,
            priority: intValue(arguments["priority"]),
            comment: trimmedString(arguments["comment"]),
            values: values,
            aliasTarget: trimmedString(arguments["aliasTarget"])
        )
    }

    private func mutationResult(
        operation: String,
        environmentId: UUID,
        resolved: DNSDeckMCPResolvedZone
    ) async throws -> [String: Any] {
        let records = try await records(for: resolved, forceRefresh: true)
        return [
            "schemaVersion": "dnsdeck.mcp.recordMutation.v1",
            "operation": operation,
            "environmentId": environmentId.uuidString,
            "provider": resolved.provider.rawValue,
            "zone": zoneJSON(resolved.zone),
            "records": records.map(recordJSON),
        ]
    }

    private func validationResult(
        provider: DNSProvider,
        name: String,
        type: String,
        values: [String],
        ttl: Int?
    ) -> [String: Any] {
        validateRecord(arguments: [
            "provider": provider.rawValue,
            "name": name,
            "type": type,
            "values": values,
            "ttl": ttl as Any,
        ].removingNilValues())
    }

    private func invalidRecordPayload(_ validation: [String: Any]) -> [String: Any] {
        toolError(
            code: "INVALID_RECORD_PAYLOAD",
            message: "The DNS record payload is invalid.",
            provider: validation["provider"] as? String,
            extra: [
                "errors": validation["errors"] as? [[String: Any]] ?? [],
                "warnings": validation["warnings"] as? [[String: Any]] ?? [],
            ]
        )
    }

    private func nameserverValues(arguments: [String: Any], provider: DNSProvider) throws -> [String] {
        guard let values = arguments["nameservers"] as? [String] else {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "NAMESERVERS_REQUIRED",
                message: "Pass nameservers as an array of hostnames.",
                provider: provider.rawValue
            ))
        }

        do {
            return try NameserverUpdate.normalize(
                values,
                policy: provider.nameserverPolicy ?? .standard
            )
        } catch {
            throw DNSDeckMCPToolResponseError(toolError(
                code: "INVALID_NAMESERVERS",
                message: "The nameserver list is invalid.",
                provider: provider.rawValue,
                extra: [
                    "errors": [fieldError("nameservers", error.localizedDescription)],
                ]
            ))
        }
    }

    private func trimmedString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func stringArray(_ value: Any?) -> [String]? {
        guard let strings = value as? [String] else { return nil }
        let values = strings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        return nil
    }

    private func providerJSON(_ provider: DNSProvider) -> [String: Any] {
        let capabilities = provider.capabilities

        return [
            "id": provider.rawValue,
            "displayName": provider.displayName,
            "setupURL": provider.setupLink?.url.absoluteString as Any,
            "credentialFields": provider.credentialFields.map { field in
                [
                    "id": field.id,
                    "label": localized(field.label),
                    "kind": credentialKind(field.kind),
                    "isRequired": field.isRequired,
                ].removingNilValues()
            },
            "capabilities": [
                "zoneCapabilities": capabilities.zoneCapabilities.map(\.rawValue).sorted(),
                "recordMutationMode": capabilities.recordMutationMode.rawValue,
                "editableRecordTypes": capabilities.editableRecordTypes,
                "features": capabilities.features.map(\.rawValue).sorted(),
                "ttl": [
                    "default": capabilities.ttl.defaultValue,
                    "minimum": capabilities.ttl.minimum,
                    "maximum": capabilities.ttl.maximum,
                    "supportsAutomatic": capabilities.ttl.supportsAutomatic,
                    "automaticValue": capabilities.ttl.automaticValue as Any,
                    "usesInheritedTTLForAutomatic": capabilities.ttl.usesInheritedTTLForAutomatic,
                    "allowedValues": capabilities.ttl.allowedValues as Any,
                ].removingNilValues(),
            ],
        ].removingNilValues()
    }

    private func environmentJSON(_ environment: DNSEnvironment) -> [String: Any] {
        [
            "id": environment.id.uuidString,
            "name": environment.name,
            "createdAt": environment.createdAt,
            "isStarred": environment.isStarred,
        ]
    }

    private func zoneJSON(_ zone: ProviderZone) -> [String: Any] {
        [
            "id": zone.id,
            "nativeId": zone.zoneData.id,
            "provider": zone.provider.rawValue,
            "environmentId": zone.environmentId.uuidString,
            "name": zone.name,
            "nameservers": zone.nameservers,
        ]
    }

    private func recordJSON(_ record: ProviderRecord) -> [String: Any] {
        [
            "id": record.id,
            "nativeId": record.recordData.id,
            "provider": record.provider.rawValue,
            "name": record.name,
            "type": record.type,
            "content": record.content,
            "values": record.values,
            "ttl": record.ttl as Any,
            "proxied": record.proxied as Any,
            "priority": record.priority as Any,
            "comment": record.comment as Any,
            "createdOn": record.createdOn as Any,
            "modifiedOn": record.modifiedOn as Any,
            "isEditable": record.isEditable,
            "aliasTarget": aliasTargetJSON(record.aliasTarget) as Any,
            "routingPolicy": routingPolicyJSON(record.routingPolicy) as Any,
        ].removingNilValues()
    }

    private func aliasTargetJSON(_ aliasTarget: DNSAliasTarget?) -> [String: Any]? {
        guard let aliasTarget else { return nil }
        return [
            "name": aliasTarget.name,
            "zoneId": aliasTarget.zoneId as Any,
            "evaluateTargetHealth": aliasTarget.evaluateTargetHealth as Any,
        ].removingNilValues()
    }

    private func routingPolicyJSON(_ policy: DNSRecordRoutingPolicy?) -> [String: Any]? {
        guard let policy else { return nil }
        return [
            "identifier": policy.identifier as Any,
            "weight": policy.weight as Any,
            "region": policy.region as Any,
            "continent": policy.continent as Any,
            "country": policy.country as Any,
            "subdivision": policy.subdivision as Any,
            "failover": policy.failover as Any,
            "multiValueAnswer": policy.multiValueAnswer as Any,
            "healthCheckId": policy.healthCheckId as Any,
        ].removingNilValues()
    }

    private func findZone(in zones: [ProviderZone], zoneId: String?, zoneName: String?) -> ProviderZone? {
        zones.first { zone in
            if let zoneId,
               zone.id == zoneId || zone.zoneData.id == zoneId
            {
                return true
            }
            if let zoneName,
               zone.name.caseInsensitiveCompare(zoneName) == .orderedSame
            {
                return true
            }
            return false
        }
    }

    private func localized(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    private func credentialKind(_ kind: ProviderCredentialFieldKind) -> String {
        switch kind {
        case .text: "text"
        case .secret: "secret"
        case .multilineSecret: "multilineSecret"
        }
    }

    private func providerErrorJSON(provider: DNSProvider, operation: String, error: Error) -> [String: Any] {
        [
            "provider": provider.rawValue,
            "operation": operation,
            "code": mapErrorCode(error),
            "message": error.localizedDescription,
        ]
    }

    private func toolError(
        code: String,
        message: String,
        provider: String? = nil,
        environmentId: String? = nil,
        zoneId: String? = nil,
        recordId: String? = nil,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var value = [
            "isError": true,
            "schemaVersion": "dnsdeck.mcp.error.v1",
            "code": code,
            "message": message,
            "provider": provider as Any,
            "environmentId": environmentId as Any,
            "zoneId": zoneId as Any,
            "recordId": recordId as Any,
        ].removingNilValues()
        for entry in extra {
            value[entry.key] = entry.value
        }
        return value
    }

    private func fieldError(_ field: String, _ message: String) -> [String: Any] {
        [
            "field": field,
            "message": message,
        ]
    }

    private func mapErrorCode(_ error: Error) -> String {
        if let operationError = error as? ProviderOperationError {
            switch operationError {
            case .missingService:
                return "MISSING_SERVICE"
            case .missingRecord:
                return "RECORD_NOT_FOUND"
            case .unsupportedNameserverUpdate, .unsupportedZoneCreation, .unsupportedZoneDeletion:
                return "UNSUPPORTED_OPERATION"
            case .readOnlyRecord:
                return "READ_ONLY_RECORD"
            case .readOnlyZone:
                return "READ_ONLY_ZONE"
            case .invalidRecordData, .invalidZoneData:
                return "INVALID_PROVIDER_DATA"
            }
        }

        if let providerError = error as? ProviderAPIError {
            switch providerError {
            case .missingCredential:
                return "MISSING_CREDENTIAL"
            case .http:
                return "PROVIDER_HTTP_ERROR"
            case .decoding:
                return "PROVIDER_DECODING_ERROR"
            case .invalidURL, .untrustedURL:
                return "PROVIDER_URL_ERROR"
            case .invalidRecordContent:
                return "PROVIDER_INVALID_CONTENT"
            case .operationFailed, .actionFailed:
                return "PROVIDER_OPERATION_FAILED"
            case .operationTimedOut, .actionTimedOut:
                return "PROVIDER_OPERATION_TIMED_OUT"
            case .invalidResponse:
                return "PROVIDER_INVALID_RESPONSE"
            }
        }

        return "INTERNAL_ERROR"
    }
}

private struct DNSDeckMCPResolvedZone {
    let provider: DNSProvider
    let zone: ProviderZone
    let service: any DNSProviderService
}

private struct DNSDeckMCPToolResponseError: Error {
    let response: [String: Any]

    init(_ response: [String: Any]) {
        self.response = response
    }
}

struct DNSDeckMCPEnvironmentStore {
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let userDefaultsKey = "dnsdeck.environments"

    init(userDefaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    func loadEnvironments() -> [DNSEnvironment] {
        let data = userDefaults.data(forKey: userDefaultsKey)
            ?? userDefaults.persistentDomain(forName: Constants.bundleIdentifier)?[userDefaultsKey] as? Data
            ?? loadSandboxedAppDefaultsData()

        guard let data,
              let decoded = try? JSONDecoder().decode([DNSEnvironment].self, from: data)
        else {
            return []
        }

        return decoded.sorted {
            if $0.isStarred != $1.isStarred {
                return $0.isStarred && !$1.isStarred
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private func loadSandboxedAppDefaultsData() -> Data? {
        let plistURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(Constants.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(Constants.bundleIdentifier).plist")

        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any]
        else {
            return nil
        }

        return dictionary[userDefaultsKey] as? Data
    }
}

actor DNSDeckMCPCache {
    private struct Entry<Value> {
        let value: Value
        let expiresAt: Date
    }

    private var zones: [String: Entry<[ProviderZone]>] = [:]
    private var records: [String: Entry<[ProviderRecord]>] = [:]
    private let zonesTTL: TimeInterval = 30 * 60
    private let recordsTTL: TimeInterval = 5 * 60

    func zones(
        environmentId: UUID,
        provider: DNSProvider,
        forceRefresh: Bool,
        load: () async throws -> [ProviderZone]
    ) async throws -> [ProviderZone] {
        let key = "\(environmentId.uuidString)|\(provider.rawValue)"
        if !forceRefresh,
           let entry = zones[key],
           entry.expiresAt > Date()
        {
            return entry.value
        }

        let value = try await load()
        zones[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(zonesTTL))
        return value
    }

    func records(
        environmentId: UUID,
        zone: ProviderZone,
        forceRefresh: Bool,
        load: () async throws -> [ProviderRecord]
    ) async throws -> [ProviderRecord] {
        let key = "\(environmentId.uuidString)|\(zone.id)"
        if !forceRefresh,
           let entry = records[key],
           entry.expiresAt > Date()
        {
            return entry.value
        }

        let value = try await load()
        records[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(recordsTTL))
        return value
    }

    func invalidateRecords(environmentId: UUID, zone: ProviderZone) {
        let key = "\(environmentId.uuidString)|\(zone.id)"
        records.removeValue(forKey: key)
    }

    func invalidateZones(environmentId: UUID, provider: DNSProvider) {
        let key = "\(environmentId.uuidString)|\(provider.rawValue)"
        zones.removeValue(forKey: key)
    }
}
