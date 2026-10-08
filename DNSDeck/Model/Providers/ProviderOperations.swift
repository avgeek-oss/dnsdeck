import Foundation

enum ProviderOperationError: LocalizedError {
    case invalidZoneData(provider: DNSProvider)
    case invalidRecordData(provider: DNSProvider)
    case missingRecord(recordId: String)
    case missingService(provider: DNSProvider)
    case unsupportedZoneCreation(provider: DNSProvider)
    case unsupportedZoneDeletion(provider: DNSProvider)
    case unsupportedNameserverUpdate(provider: DNSProvider)
    case readOnlyZone(provider: DNSProvider, zoneName: String)
    case readOnlyRecord(provider: DNSProvider, recordId: String)

    var errorDescription: String? {
        switch self {
        case let .invalidZoneData(provider):
            "\(provider.displayName) zone data is invalid."
        case let .invalidRecordData(provider):
            "\(provider.displayName) record data is invalid."
        case let .missingRecord(recordId):
            "Unable to find DNS record with id \(recordId)."
        case let .missingService(provider):
            "\(provider.displayName) is not registered in this DNSDeck build."
        case let .unsupportedZoneCreation(provider):
            "\(provider.displayName) does not support zone creation in DNSDeck yet."
        case let .unsupportedZoneDeletion(provider):
            "\(provider.displayName) does not support zone deletion in DNSDeck yet."
        case let .unsupportedNameserverUpdate(provider):
            "\(provider.displayName) cannot update registrar nameservers through its public API."
        case let .readOnlyZone(provider, zoneName):
            "\(zoneName) is a read-only \(provider.displayName) secondary zone."
        case let .readOnlyRecord(provider, recordId):
            "Record \(recordId) is managed by \(provider.displayName) and cannot be changed directly."
        }
    }
}

extension DNSProvider {
    func listZones(environmentId: UUID, services: ProviderServiceBundle) async throws -> [ProviderZone] {
        try await services.service(for: self).listZones(environmentId: environmentId)
    }

    func createZone(
        named name: String,
        environmentId: UUID,
        services: ProviderServiceBundle
    ) async throws -> ProviderZone {
        try await services.service(for: self).createZone(named: name, environmentId: environmentId)
    }

    func zoneDetails(for zone: ProviderZone, services: ProviderServiceBundle) async throws -> ProviderZone {
        try await services.service(for: self).zoneDetails(for: zone)
    }

    func deleteZone(_ zone: ProviderZone, services: ProviderServiceBundle) async throws {
        try await services.service(for: self).deleteZone(zone)
    }

    func updateNameservers(
        for zone: ProviderZone,
        nameservers: [String],
        services: ProviderServiceBundle
    ) async throws {
        try await services.service(for: self).updateNameservers(for: zone, nameservers: nameservers)
    }

    func records(for zone: ProviderZone, services: ProviderServiceBundle) async throws -> [ProviderRecord] {
        try await services.service(for: self).records(for: zone)
    }

    func createRecord(
        in zone: ProviderZone,
        payload: CreateProviderRecordRequest,
        services: ProviderServiceBundle
    ) async throws {
        try await services.service(for: self).createRecord(in: zone, payload: payload)
    }

    func deleteRecord(
        in zone: ProviderZone,
        recordId: String,
        existingRecords: [ProviderRecord],
        services: ProviderServiceBundle
    ) async throws {
        guard let record = existingRecords.first(where: { $0.id == recordId }) else {
            throw ProviderOperationError.missingRecord(recordId: recordId)
        }
        try await deleteRecord(in: zone, record: record, services: services)
    }

    func deleteRecord(
        in zone: ProviderZone,
        record: ProviderRecord,
        services: ProviderServiceBundle
    ) async throws {
        try await services.service(for: self).deleteRecord(in: zone, record: record)
    }

    func updateRecord(
        in zone: ProviderZone,
        record: ProviderRecord,
        edits: UpdateProviderRecordRequest,
        services: ProviderServiceBundle
    ) async throws {
        try await services.service(for: self).updateRecord(in: zone, record: record, edits: edits)
    }
}
