import Foundation

protocol DNSProviderService {
    var provider: DNSProvider { get }

    func listZones(environmentId: UUID) async throws -> [ProviderZone]
    func createZone(named name: String, environmentId: UUID) async throws -> ProviderZone
    func zoneDetails(for zone: ProviderZone) async throws -> ProviderZone
    func deleteZone(_ zone: ProviderZone) async throws
    func updateNameservers(for zone: ProviderZone, nameservers: [String]) async throws
    func records(for zone: ProviderZone) async throws -> [ProviderRecord]
    func createRecord(in zone: ProviderZone, payload: CreateProviderRecordRequest) async throws
    func createRecords(
        in zone: ProviderZone,
        payloads: [CreateProviderRecordRequest]
    ) async -> [Result<Void, Error>]?
    func deleteRecord(in zone: ProviderZone, record: ProviderRecord) async throws
    func updateRecord(
        in zone: ProviderZone,
        record: ProviderRecord,
        edits: UpdateProviderRecordRequest
    ) async throws
}

extension DNSProviderService {
    func createZone(named _: String, environmentId _: UUID) async throws -> ProviderZone {
        throw ProviderOperationError.unsupportedZoneCreation(provider: provider)
    }

    func zoneDetails(for zone: ProviderZone) async throws -> ProviderZone {
        zone
    }

    func deleteZone(_: ProviderZone) async throws {
        throw ProviderOperationError.unsupportedZoneDeletion(provider: provider)
    }

    func updateNameservers(for _: ProviderZone, nameservers _: [String]) async throws {
        throw ProviderOperationError.unsupportedNameserverUpdate(provider: provider)
    }

    func createRecords(
        in _: ProviderZone,
        payloads _: [CreateProviderRecordRequest]
    ) async -> [Result<Void, Error>]? {
        nil
    }

    func nativeZone<Value: Decodable>(_ zone: ProviderZone, as type: Value.Type = Value.self) throws -> Value {
        guard zone.provider == provider, let value = zone.zoneData.decode(type) else {
            throw ProviderOperationError.invalidZoneData(provider: provider)
        }
        return value
    }

    func nativeRecord<Value: Decodable>(
        _ record: ProviderRecord,
        as type: Value.Type = Value.self
    ) throws -> Value {
        guard record.provider == provider, let value = record.recordData.decode(type) else {
            throw ProviderOperationError.invalidRecordData(provider: provider)
        }
        return value
    }
}

struct ProviderServiceRegistry {
    private let services: [DNSProvider: any DNSProviderService]

    init(_ services: [any DNSProviderService]) {
        self.services = Dictionary(uniqueKeysWithValues: services.map { ($0.provider, $0) })
    }

    func service(for provider: DNSProvider) throws -> any DNSProviderService {
        guard let service = services[provider] else {
            throw ProviderOperationError.missingService(provider: provider)
        }
        return service
    }
}

typealias ProviderServiceBundle = ProviderServiceRegistry

private func requireEditable(_ record: ProviderRecord) throws {
    guard record.isEditable else {
        throw ProviderOperationError.readOnlyRecord(provider: record.provider, recordId: record.id)
    }
}

private func requireWritable<Value>(
    _ value: Value,
    in zone: ProviderZone,
    when isWritable: (Value) -> Bool
) throws -> Value {
    guard isWritable(value) else {
        throw ProviderOperationError.readOnlyZone(provider: zone.provider, zoneName: zone.name)
    }
    return value
}

private func requireWritable<Value>(
    _ value: Value,
    for record: ProviderRecord,
    id: String? = nil,
    when isWritable: (Value) -> Bool
) throws -> Value {
    guard isWritable(value) else {
        throw ProviderOperationError.readOnlyRecord(provider: record.provider, recordId: id ?? record.id)
    }
    return value
}

struct ProviderDNSAdapter<Zone: Decodable, Record: Decodable>: DNSProviderService {
    typealias ZoneOperation = (Zone, ProviderZone) async throws -> Void
    typealias RecordOperation = (Zone, ProviderZone, Record, ProviderRecord) async throws -> Void

    let provider: DNSProvider
    private let loadZones: () async throws -> [Zone]
    private let zoneSnapshot: (Zone) -> ProviderZoneSnapshot
    private let createZoneOperation: ((String) async throws -> Zone)?
    private let createZoneSnapshotOperation: ((String) async throws -> ProviderZoneSnapshot)?
    private let zoneDetailsOperation: ((Zone) async throws -> Zone)?
    private let zoneDetailsSnapshotOperation: ((Zone) async throws -> ProviderZoneSnapshot)?
    private let deleteZoneOperation: ZoneOperation?
    private let updateNameserversOperation: ((Zone, ProviderZone, [String]) async throws -> Void)?
    private let loadRecords: (Zone, ProviderZone) async throws -> [Record]
    private let recordSnapshot: (Record, Zone, ProviderZone) -> ProviderRecordSnapshot
    private let createRecordOperation: (Zone, ProviderZone, CreateProviderRecordRequest) async throws -> Void
    private let createRecordsOperation:
        ((Zone, ProviderZone, [CreateProviderRecordRequest]) async -> [Result<Void, Error>])?
    private let deleteRecordOperation: RecordOperation
    private let updateRecordOperation:
        (Zone, ProviderZone, Record, ProviderRecord, UpdateProviderRecordRequest) async throws -> Void

    init(
        provider: DNSProvider,
        loadZones: @escaping () async throws -> [Zone],
        zoneSnapshot: @escaping (Zone) -> ProviderZoneSnapshot,
        createZone: ((String) async throws -> Zone)? = nil,
        createZoneSnapshot: ((String) async throws -> ProviderZoneSnapshot)? = nil,
        zoneDetails: ((Zone) async throws -> Zone)? = nil,
        zoneDetailsSnapshot: ((Zone) async throws -> ProviderZoneSnapshot)? = nil,
        deleteZone: ZoneOperation? = nil,
        updateNameservers: ((Zone, ProviderZone, [String]) async throws -> Void)? = nil,
        loadRecords: @escaping (Zone, ProviderZone) async throws -> [Record],
        recordSnapshot: @escaping (Record, Zone, ProviderZone) -> ProviderRecordSnapshot,
        createRecord: @escaping (Zone, ProviderZone, CreateProviderRecordRequest) async throws -> Void,
        createRecords: ((
            Zone,
            ProviderZone,
            [CreateProviderRecordRequest]
        ) async -> [Result<Void, Error>])? = nil,
        deleteRecord: @escaping RecordOperation,
        updateRecord: @escaping (
            Zone,
            ProviderZone,
            Record,
            ProviderRecord,
            UpdateProviderRecordRequest
        ) async throws -> Void
    ) {
        self.provider = provider
        self.loadZones = loadZones
        self.zoneSnapshot = zoneSnapshot
        createZoneOperation = createZone
        createZoneSnapshotOperation = createZoneSnapshot
        zoneDetailsOperation = zoneDetails
        zoneDetailsSnapshotOperation = zoneDetailsSnapshot
        deleteZoneOperation = deleteZone
        updateNameserversOperation = updateNameservers
        self.loadRecords = loadRecords
        self.recordSnapshot = recordSnapshot
        createRecordOperation = createRecord
        createRecordsOperation = createRecords
        deleteRecordOperation = deleteRecord
        updateRecordOperation = updateRecord
    }

    func listZones(environmentId: UUID) async throws -> [ProviderZone] {
        try await loadZones().map {
            ProviderZone(provider: provider, snapshot: zoneSnapshot($0), environmentId: environmentId)
        }
    }

    func createZone(named name: String, environmentId: UUID) async throws -> ProviderZone {
        if let createZoneSnapshotOperation {
            let snapshot = try await createZoneSnapshotOperation(name)
            return ProviderZone(
                provider: provider,
                snapshot: snapshot,
                environmentId: environmentId
            )
        }
        guard let createZoneOperation else {
            throw ProviderOperationError.unsupportedZoneCreation(provider: provider)
        }
        let nativeZone = try await createZoneOperation(name)
        return ProviderZone(
            provider: provider,
            snapshot: zoneSnapshot(nativeZone),
            environmentId: environmentId
        )
    }

    func zoneDetails(for zone: ProviderZone) async throws -> ProviderZone {
        if let zoneDetailsSnapshotOperation {
            let nativeZone: Zone = try nativeZone(zone)
            let snapshot = try await zoneDetailsSnapshotOperation(nativeZone)
            return ProviderZone(
                provider: provider,
                snapshot: snapshot,
                environmentId: zone.environmentId
            )
        }
        guard let zoneDetailsOperation else { return zone }
        let detailedZone = try await zoneDetailsOperation(nativeZone(zone))
        return ProviderZone(
            provider: provider,
            snapshot: zoneSnapshot(detailedZone),
            environmentId: zone.environmentId
        )
    }

    func deleteZone(_ zone: ProviderZone) async throws {
        guard let deleteZoneOperation else {
            throw ProviderOperationError.unsupportedZoneDeletion(provider: provider)
        }
        try await deleteZoneOperation(nativeZone(zone), zone)
    }

    func updateNameservers(for zone: ProviderZone, nameservers: [String]) async throws {
        guard let updateNameserversOperation else {
            throw ProviderOperationError.unsupportedNameserverUpdate(provider: provider)
        }
        try await updateNameserversOperation(nativeZone(zone), zone, nameservers)
    }

    func records(for zone: ProviderZone) async throws -> [ProviderRecord] {
        let nativeZone: Zone = try nativeZone(zone)
        return try await loadRecords(nativeZone, zone).map {
            ProviderRecord(provider: provider, snapshot: recordSnapshot($0, nativeZone, zone))
        }
    }

    func createRecord(in zone: ProviderZone, payload: CreateProviderRecordRequest) async throws {
        try await createRecordOperation(nativeZone(zone), zone, payload)
    }

    func createRecords(
        in zone: ProviderZone,
        payloads: [CreateProviderRecordRequest]
    ) async -> [Result<Void, Error>]? {
        guard let createRecordsOperation else { return nil }
        do {
            return try await createRecordsOperation(nativeZone(zone), zone, payloads)
        } catch {
            return payloads.map { _ in .failure(error) }
        }
    }

    func deleteRecord(in zone: ProviderZone, record: ProviderRecord) async throws {
        try await deleteRecordOperation(nativeZone(zone), zone, nativeRecord(record), record)
    }

    func updateRecord(
        in zone: ProviderZone,
        record: ProviderRecord,
        edits: UpdateProviderRecordRequest
    ) async throws {
        try await updateRecordOperation(nativeZone(zone), zone, nativeRecord(record), record, edits)
    }
}

typealias CloudflareDNSProviderService = ProviderDNSAdapter<CFZone, CFDNSRecord>

extension ProviderDNSAdapter where Zone == CFZone, Record == CFDNSRecord {
    init(service: CloudflareService) {
        self.init(
            provider: .cloudflare,
            loadZones: { try await service.listZones() },
            zoneSnapshot: { $0.snapshot() },
            createZone: { try await service.createZone(name: $0) },
            zoneDetails: { try await service.getZone(zoneId: $0.id) },
            loadRecords: { zone, _ in try await service.listRecords(zoneId: zone.id) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { zone, _, payload in
                _ = try await service.createRecord(
                    zoneId: zone.id,
                    payload: payload.toCloudflareRequest(zoneName: zone.name)
                )
            },
            deleteRecord: { zone, _, record, _ in
                try await service.deleteRecord(zoneId: zone.id, recordId: record.id)
            },
            updateRecord: { zone, _, record, _, edits in
                _ = try await service.updateRecord(
                    zoneId: zone.id,
                    recordId: record.id,
                    payload: edits.toCloudflareRequest(zoneName: zone.name, existingRecord: record)
                )
            }
        )
    }
}

typealias DigitalOceanDNSProviderService = ProviderDNSAdapter<DigitalOceanDomain, DigitalOceanDomainRecord>

extension ProviderDNSAdapter where Zone == DigitalOceanDomain, Record == DigitalOceanDomainRecord {
    init(service: DigitalOceanService) {
        self.init(
            provider: .digitalOcean,
            loadZones: service.listDomains,
            zoneSnapshot: { $0.snapshot(nameservers: DigitalOceanService.nameservers) },
            createZone: { try await service.createDomain(name: $0) },
            zoneDetails: { try await service.getDomain(name: $0.name) },
            deleteZone: { domain, _ in try await service.deleteDomain(name: domain.name) },
            loadRecords: { domain, _ in try await service.listRecords(domain: domain.name) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { domain, _, payload in
                _ = try await service.createRecord(
                    domain: domain.name,
                    request: payload.toDigitalOceanRequest(zoneName: domain.name)
                )
            },
            deleteRecord: { domain, _, record, _ in
                try await service.deleteRecord(domain: domain.name, recordId: record.id)
            },
            updateRecord: { domain, _, record, _, edits in
                _ = try await service.updateRecord(
                    domain: domain.name,
                    recordId: record.id,
                    request: edits.toDigitalOceanRequest(zoneName: domain.name, existingRecord: record)
                )
            }
        )
    }
}

typealias HetznerDNSProviderService = ProviderDNSAdapter<HetznerZone, HetznerRRSet>

extension ProviderDNSAdapter where Zone == HetznerZone, Record == HetznerRRSet {
    init(service: HetznerService) {
        self.init(
            provider: .hetzner,
            loadZones: service.listZones,
            zoneSnapshot: { $0.snapshot() },
            createZone: { try await service.createZone(name: $0) },
            zoneDetails: { try await service.getZone(idOrName: String($0.id)) },
            deleteZone: { zone, _ in try await service.deleteZone(idOrName: String(zone.id)) },
            loadRecords: { zone, _ in try await service.listRRSets(zoneIdOrName: String(zone.id)) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { zone, providerZone, payload in
                _ = try await service.createRRSet(
                    zoneIdOrName: String(zone.id),
                    request: payload.toHetznerRequest(zoneName: providerZone.name)
                )
            },
            deleteRecord: { zone, _, record, _ in
                try await service.deleteRRSet(zoneIdOrName: String(zone.id), rrset: record)
            },
            updateRecord: { zone, providerZone, record, _, edits in
                try await service.updateRRSet(
                    zoneIdOrName: String(zone.id),
                    existing: record,
                    desired: edits.toHetznerState(zoneName: providerZone.name, existing: record)
                )
            }
        )
    }
}

typealias AkamaiCloudDNSProviderService = ProviderDNSAdapter<AkamaiCloudDomain, AkamaiCloudDomainRecord>

extension ProviderDNSAdapter where Zone == AkamaiCloudDomain, Record == AkamaiCloudDomainRecord {
    init(service: AkamaiCloudService) {
        self.init(
            provider: .akamaiCloud,
            loadZones: service.listDomains,
            zoneSnapshot: { $0.snapshot(nameservers: AkamaiCloudService.nameservers) },
            createZone: { try await service.createDomain(name: $0) },
            zoneDetails: { try await service.getDomain(id: $0.id) },
            deleteZone: { domain, _ in try await service.deleteDomain(id: domain.id) },
            loadRecords: { domain, _ in try await service.listRecords(domainId: domain.id) },
            recordSnapshot: { record, domain, _ in
                record.snapshot(defaultTTL: domain.ttlSec == 0 ? 86400 : domain.ttlSec ?? 86400)
            },
            createRecord: { domain, providerZone, payload in
                let domain = try requireWritable(domain, in: providerZone, when: { $0.type == "master" })
                _ = try await service.createRecord(
                    domainId: domain.id,
                    request: payload.toAkamaiCloudRequest(zoneName: providerZone.name)
                )
            },
            deleteRecord: { domain, providerZone, record, _ in
                let domain = try requireWritable(domain, in: providerZone, when: { $0.type == "master" })
                try await service.deleteRecord(domainId: domain.id, recordId: record.id)
            },
            updateRecord: { domain, providerZone, record, _, edits in
                let domain = try requireWritable(domain, in: providerZone, when: { $0.type == "master" })
                _ = try await service.updateRecord(
                    domainId: domain.id,
                    recordId: record.id,
                    request: edits.toAkamaiCloudRequest(zoneName: providerZone.name, existing: record)
                )
            }
        )
    }
}

typealias VultrDNSProviderService = ProviderDNSAdapter<VultrDomain, VultrDomainRecord>

extension ProviderDNSAdapter where Zone == VultrDomain, Record == VultrDomainRecord {
    init(service: VultrService) {
        self.init(
            provider: .vultr,
            loadZones: service.listDomains,
            zoneSnapshot: { $0.snapshot(nameservers: VultrService.nameservers) },
            createZone: { try await service.createDomain(name: $0) },
            zoneDetails: { try await service.getDomain(name: $0.domain) },
            deleteZone: { domain, _ in try await service.deleteDomain(name: domain.domain) },
            loadRecords: { domain, _ in try await service.listRecords(domain: domain.domain) },
            recordSnapshot: { record, domain, _ in record.snapshot(zoneName: domain.domain) },
            createRecord: { domain, _, payload in
                _ = try await service.createRecord(
                    domain: domain.domain,
                    request: payload.toVultrRequest(zoneName: domain.domain)
                )
            },
            deleteRecord: { domain, _, record, _ in
                try await service.deleteRecord(domain: domain.domain, recordId: record.id)
            },
            updateRecord: { domain, _, record, _, edits in
                try await service.updateRecord(
                    domain: domain.domain,
                    recordId: record.id,
                    request: edits.toVultrRequest(zoneName: domain.domain, existing: record)
                )
            }
        )
    }
}

typealias DNSimpleDNSProviderService = ProviderDNSAdapter<DNSimpleZone, DNSimpleZoneRecord>

extension ProviderDNSAdapter where Zone == DNSimpleZone, Record == DNSimpleZoneRecord {
    init(service: DNSimpleService) {
        self.init(
            provider: .dnsimple,
            loadZones: service.listZones,
            zoneSnapshot: { $0.snapshot(nameservers: DNSimpleService.nameservers) },
            zoneDetailsSnapshot: { zone in
                let details = try await service.getZone(name: zone.name)
                let nameservers = await (try? service.nameservers(domain: zone.name)) ?? DNSimpleService.nameservers
                return details.snapshot(nameservers: nameservers)
            },
            updateNameservers: { zone, _, nameservers in
                try await service.updateNameservers(domain: zone.name, nameservers: nameservers)
            },
            loadRecords: { zone, _ in try await service.listRecords(zoneName: zone.name) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { zone, providerZone, payload in
                let zone = try requireWritable(zone, in: providerZone, when: { !$0.secondary })
                _ = try await service.createRecord(
                    zoneName: zone.name,
                    request: payload.toDNSimpleRequest(zoneName: zone.name)
                )
            },
            deleteRecord: { zone, providerZone, record, providerRecord in
                let zone = try requireWritable(zone, in: providerZone, when: { !$0.secondary })
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    id: String(record.id),
                    when: { !$0.systemRecord && $0.parentId == nil }
                )
                try await service.deleteRecord(zoneName: zone.name, recordId: record.id)
            },
            updateRecord: { zone, providerZone, record, providerRecord, edits in
                let zone = try requireWritable(zone, in: providerZone, when: { !$0.secondary })
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    id: String(record.id),
                    when: { !$0.systemRecord && $0.parentId == nil }
                )
                _ = try await service.updateRecord(
                    zoneName: zone.name,
                    recordId: record.id,
                    request: edits.toDNSimpleRequest(zoneName: zone.name, existing: record)
                )
            }
        )
    }
}

typealias GandiDNSProviderService = ProviderDNSAdapter<GandiDomain, GandiRecordSet>

extension ProviderDNSAdapter where Zone == GandiDomain, Record == GandiRecordSet {
    init(service: GandiService) {
        self.init(
            provider: .gandi,
            loadZones: service.listDomains,
            zoneSnapshot: { $0.snapshot() },
            createZoneSnapshot: { name in
                let domain = try await service.createDomain(name: name)
                let nameservers = try await service.nameservers(domain: domain.fqdn)
                return domain.snapshot(nameservers: nameservers)
            },
            zoneDetailsSnapshot: { domain in
                let details = try await service.getDomain(name: domain.fqdn)
                let nameservers = try await service.nameservers(domain: domain.fqdn)
                return details.snapshot(nameservers: nameservers)
            },
            loadRecords: { domain, _ in try await service.listRecordSets(domain: domain.fqdn) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { domain, _, payload in
                let mutation = try payload.toGandiMutation(zoneName: domain.fqdn)
                try await service.createRecordSet(
                    domain: domain.fqdn,
                    name: mutation.name,
                    type: mutation.type,
                    request: mutation.request
                )
            },
            deleteRecord: { domain, _, record, providerRecord in
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    when: { $0.rrsetType.uppercased() != "SOA" }
                )
                try await service.deleteRecordSet(
                    domain: domain.fqdn,
                    name: record.rrsetName,
                    type: record.rrsetType
                )
            },
            updateRecord: { domain, _, record, providerRecord, edits in
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    when: { $0.rrsetType.uppercased() != "SOA" }
                )
                let mutation = try edits.toGandiMutation(zoneName: domain.fqdn, existing: record)
                if mutation.name == record.rrsetName, mutation.type == record.rrsetType.uppercased() {
                    try await service.replaceRecordSet(
                        domain: domain.fqdn,
                        name: mutation.name,
                        type: mutation.type,
                        request: mutation.request
                    )
                    return
                }
                try await service.createRecordSet(
                    domain: domain.fqdn,
                    name: mutation.name,
                    type: mutation.type,
                    request: mutation.request
                )
                do {
                    try await service.deleteRecordSet(
                        domain: domain.fqdn,
                        name: record.rrsetName,
                        type: record.rrsetType
                    )
                } catch {
                    try? await service.deleteRecordSet(
                        domain: domain.fqdn,
                        name: mutation.name,
                        type: mutation.type
                    )
                    throw error
                }
            }
        )
    }
}

typealias DeSECDNSProviderService = ProviderDNSAdapter<DeSECDomain, DeSECRRset>

extension ProviderDNSAdapter where Zone == DeSECDomain, Record == DeSECRRset {
    init(service: DeSECService) {
        self.init(
            provider: .deSEC,
            loadZones: service.listDomains,
            zoneSnapshot: { $0.snapshot() },
            createZone: { try await service.createDomain(name: $0) },
            zoneDetails: { try await service.getDomain(name: $0.name) },
            deleteZone: { domain, _ in try await service.deleteDomain(name: domain.name) },
            loadRecords: { domain, _ in try await service.listRRsets(domain: domain.name) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { domain, _, payload in
                let mutation = try payload.toDeSECMutation(
                    zoneName: domain.name,
                    minimumTTL: domain.minimumTTL
                )
                try await service.createRRset(domain: domain.name, request: mutation.request)
            },
            createRecords: { domain, _, payloads in
                do {
                    let requests = try payloads.map {
                        try $0.toDeSECMutation(
                            zoneName: domain.name,
                            minimumTTL: domain.minimumTTL
                        ).request
                    }
                    try await service.createRRsets(domain: domain.name, requests: requests)
                    return payloads.map { _ in .success(()) }
                } catch {
                    return payloads.map { _ in .failure(error) }
                }
            },
            deleteRecord: { domain, _, record, providerRecord in
                try requireEditable(providerRecord)
                try await service.deleteRRset(
                    domain: domain.name,
                    subname: record.subname,
                    type: record.type
                )
            },
            updateRecord: { domain, _, record, providerRecord, edits in
                try requireEditable(providerRecord)
                let mutation = try edits.toDeSECMutation(
                    zoneName: domain.name,
                    minimumTTL: domain.minimumTTL,
                    existing: record
                )
                if mutation.request.subname == record.subname,
                   mutation.request.type == record.type.uppercased()
                {
                    try await service.replaceRRset(domain: domain.name, request: mutation.request)
                    return
                }
                try await service.createRRset(domain: domain.name, request: mutation.request)
                do {
                    try await service.deleteRRset(domain: domain.name, subname: record.subname, type: record.type)
                } catch {
                    try? await service.deleteRRset(
                        domain: domain.name,
                        subname: mutation.request.subname,
                        type: mutation.request.type
                    )
                    throw error
                }
            }
        )
    }
}

struct PowerDNSDNSProviderService: DNSProviderService {
    let provider = DNSProvider.powerDNS
    let service: PowerDNSService

    func listZones(environmentId: UUID) async throws -> [ProviderZone] {
        try await service.listZones().map {
            ProviderZone(provider: provider, snapshot: $0.snapshot(), environmentId: environmentId)
        }
    }

    func createZone(named name: String, environmentId: UUID) async throws -> ProviderZone {
        let zone = try await service.createZone(name: name)
        return ProviderZone(provider: provider, snapshot: zone.snapshot(), environmentId: environmentId)
    }

    func zoneDetails(for zone: ProviderZone) async throws -> ProviderZone {
        let nativeZone = try nativeZone(zone, as: PowerDNSZone.self)
        let details = try await service.getZone(id: nativeZone.id)
        return ProviderZone(provider: provider, snapshot: details.snapshot(), environmentId: zone.environmentId)
    }

    func deleteZone(_ zone: ProviderZone) async throws {
        try await service.deleteZone(id: nativeZone(zone, as: PowerDNSZone.self).id)
    }

    func records(for zone: ProviderZone) async throws -> [ProviderRecord] {
        let nativeZone = try nativeZone(zone, as: PowerDNSZone.self)
        let details = try await service.getZone(id: nativeZone.id)
        return (details.rrsets ?? []).map {
            ProviderRecord(provider: provider, snapshot: $0.snapshot(zoneName: details.name))
        }
    }

    func createRecord(in zone: ProviderZone, payload: CreateProviderRecordRequest) async throws {
        let nativeZone = try writableZone(from: zone)
        let change = try payload.toPowerDNSChange(zoneName: nativeZone.name)
        let details = try await service.getZone(id: nativeZone.id)
        try rejectConflict(change: change, in: details.rrsets ?? [])
        try await service.patchZone(id: nativeZone.id, changes: [change])
    }

    func deleteRecord(in zone: ProviderZone, record: ProviderRecord) async throws {
        let nativeZone = try writableZone(from: zone)
        let nativeRecord = try writableRecord(from: record)
        try await service.patchZone(
            id: nativeZone.id,
            changes: [.delete(name: nativeRecord.name, type: nativeRecord.type)]
        )
    }

    func updateRecord(
        in zone: ProviderZone,
        record: ProviderRecord,
        edits: UpdateProviderRecordRequest
    ) async throws {
        let nativeZone = try writableZone(from: zone)
        let nativeRecord = try writableRecord(from: record)
        let change = try edits.toPowerDNSChange(zoneName: nativeZone.name, existing: nativeRecord)
        if powerDNSRecordIdentity(change.name, change.type) == powerDNSRecordIdentity(
            nativeRecord.name,
            nativeRecord.type
        ) {
            try await service.patchZone(id: nativeZone.id, changes: [change])
            return
        }

        let details = try await service.getZone(id: nativeZone.id)
        try rejectConflict(change: change, in: details.rrsets ?? [])
        try await service.patchZone(
            id: nativeZone.id,
            changes: [change, .delete(name: nativeRecord.name, type: nativeRecord.type)]
        )
    }

    private func rejectConflict(change: PowerDNSRRsetChange, in rrsets: [PowerDNSRRset]) throws {
        let destination = powerDNSRecordIdentity(change.name, change.type)
        guard !rrsets.contains(where: { powerDNSRecordIdentity($0.name, $0.type) == destination }) else {
            throw ProviderAPIError.invalidRecordContent(
                provider: provider,
                type: change.type,
                message: "an RRset already exists at the destination name and type"
            )
        }
    }

    private func writableZone(from zone: ProviderZone) throws -> PowerDNSZone {
        let native = try nativeZone(zone, as: PowerDNSZone.self)
        guard native.isWritable else {
            throw ProviderOperationError.readOnlyZone(provider: provider, zoneName: zone.name)
        }
        return native
    }

    private func writableRecord(from record: ProviderRecord) throws -> PowerDNSRRset {
        let native = try nativeRecord(record, as: PowerDNSRRset.self)
        guard record.isEditable else {
            throw ProviderOperationError.readOnlyRecord(provider: provider, recordId: record.id)
        }
        return native
    }
}

private func powerDNSRecordIdentity(_ name: String, _ type: String) -> String {
    "\(name.lowercased())|\(type.uppercased())"
}

typealias ScalewayDNSProviderService = ProviderDNSAdapter<ScalewayDNSZone, ScalewayRecord>

extension ProviderDNSAdapter where Zone == ScalewayDNSZone, Record == ScalewayRecord {
    init(service: ScalewayService) {
        self.init(
            provider: .scaleway,
            loadZones: service.listZones,
            zoneSnapshot: { $0.snapshot() },
            zoneDetails: { try await service.getZone(name: $0.name) },
            deleteZone: { zone, _ in try await service.deleteZone(name: zone.name) },
            updateNameservers: { zone, providerZone, nameservers in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                guard zone.subdomain.isEmpty else {
                    throw ProviderAPIError.operationFailed(
                        provider: .scaleway,
                        operation: "nameserver update",
                        message: "Registrar nameservers can only be changed for a root domain."
                    )
                }
                try await service.updateNameservers(zoneName: zone.name, nameservers: nameservers)
            },
            loadRecords: { zone, _ in try await service.listRecords(zoneName: zone.name) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { zone, providerZone, payload in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                try await service.apply(
                    zoneName: zone.name,
                    changes: [.add(payload.toScalewayRecord(zoneName: zone.name))]
                )
            },
            deleteRecord: { zone, providerZone, record, _ in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                try await service.apply(zoneName: zone.name, changes: [.delete(id: record.id)])
            },
            updateRecord: { zone, providerZone, record, _, edits in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                let replacement = try edits.toScalewayRecord(zoneName: zone.name, existing: record)
                try await service.apply(zoneName: zone.name, changes: [.set(id: record.id, record: replacement)])
            }
        )
    }
}

typealias OVHCloudDNSProviderService = ProviderDNSAdapter<OVHCloudZone, OVHCloudRecord>

extension ProviderDNSAdapter where Zone == OVHCloudZone, Record == OVHCloudRecord {
    init(service: OVHCloudService) {
        self.init(
            provider: .ovhCloud,
            loadZones: {
                var zones: [OVHCloudZone] = []
                for name in try await service.listZones() {
                    let zone = try await service.getZone(name: name)
                    zones.append(zone)
                }
                return zones
            },
            zoneSnapshot: { $0.snapshot() },
            zoneDetails: { try await service.getZone(name: $0.name) },
            updateNameservers: { zone, _, nameservers in
                try await service.updateNameservers(domain: zone.name, nameservers: nameservers)
            },
            loadRecords: { zone, _ in try await service.listRecords(zoneName: zone.name) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { zone, _, payload in
                _ = try await service.createRecord(
                    zoneName: zone.name,
                    record: payload.toOVHCloudCreate(zoneName: zone.name)
                )
                try await service.refreshZone(name: zone.name)
            },
            deleteRecord: { zone, _, record, _ in
                try await service.deleteRecord(zoneName: zone.name, id: record.id)
                try await service.refreshZone(name: zone.name)
            },
            updateRecord: { zone, _, record, _, edits in
                let resolvedType = (edits.type ?? record.fieldType).uppercased()
                if resolvedType == record.fieldType.uppercased() {
                    try await service.updateRecord(
                        zoneName: zone.name,
                        id: record.id,
                        record: edits.toOVHCloudUpdate(zoneName: zone.name, existing: record)
                    )
                    try await service.refreshZone(name: zone.name)
                    return
                }
                let destination = try await service.createRecord(
                    zoneName: zone.name,
                    record: edits.toOVHCloudCreate(zoneName: zone.name, existing: record)
                )
                do {
                    try await service.deleteRecord(zoneName: zone.name, id: record.id)
                } catch {
                    try? await service.deleteRecord(zoneName: zone.name, id: destination.id)
                    throw error
                }
                try await service.refreshZone(name: zone.name)
            }
        )
    }
}

typealias IBMNS1DNSProviderService = ProviderDNSAdapter<IBMNS1Zone, IBMNS1Record>

extension ProviderDNSAdapter where Zone == IBMNS1Zone, Record == IBMNS1Record {
    init(service: IBMNS1Service) {
        self.init(
            provider: .ibmNS1,
            loadZones: service.listZones,
            zoneSnapshot: { $0.snapshot() },
            createZone: { try await service.createZone(name: $0) },
            zoneDetails: { try await service.getZone(name: $0.zone) },
            deleteZone: { zone, providerZone in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                try await service.deleteZone(name: zone.zone)
            },
            loadRecords: { zone, _ in try await service.listRecords(zoneName: zone.zone) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { zone, providerZone, payload in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                try await service.createRecord(payload.toIBMNS1Record(zoneName: zone.zone))
            },
            deleteRecord: { zone, providerZone, record, providerRecord in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                try requireEditable(providerRecord)
                try await service.deleteRecord(zone: zone.zone, domain: record.domain, type: record.type)
            },
            updateRecord: { zone, providerZone, record, providerRecord, edits in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                try requireEditable(providerRecord)
                let replacement = try edits.toIBMNS1Record(zoneName: zone.zone, existing: record)
                let sameIdentity = replacement.domain.caseInsensitiveCompare(record.domain) == .orderedSame &&
                    replacement.type.caseInsensitiveCompare(record.type) == .orderedSame
                if sameIdentity {
                    try await service.updateRecord(replacement)
                    return
                }
                try await service.createRecord(replacement)
                do {
                    try await service.deleteRecord(zone: zone.zone, domain: record.domain, type: record.type)
                } catch {
                    try? await service.deleteRecord(
                        zone: zone.zone,
                        domain: replacement.domain,
                        type: replacement.type
                    )
                    throw error
                }
            }
        )
    }
}

typealias UltraDNSProviderService = ProviderDNSAdapter<UltraDNSZone, UltraDNSRRSet>

extension ProviderDNSAdapter where Zone == UltraDNSZone, Record == UltraDNSRRSet {
    init(service: UltraDNSService) {
        self.init(
            provider: .ultraDNS,
            loadZones: service.listZones,
            zoneSnapshot: { $0.snapshot() },
            zoneDetails: { try await service.getZone(name: $0.name) },
            deleteZone: { zone, providerZone in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                try await service.deleteZone(name: zone.name)
            },
            loadRecords: { zone, _ in try await service.listRRSets(zoneName: zone.name) },
            recordSnapshot: { record, zone, _ in record.snapshot(zoneName: zone.name) },
            createRecord: { zone, providerZone, payload in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                let mutation = try payload.toUltraDNSRRSet(zoneName: zone.name)
                try await service.createRRSet(
                    zone: zone.name,
                    owner: mutation.owner,
                    type: mutation.type,
                    write: mutation.write
                )
            },
            deleteRecord: { zone, providerZone, record, providerRecord in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                try requireEditable(providerRecord)
                try await service.deleteRRSet(zone: zone.name, owner: record.ownerName, type: record.type)
            },
            updateRecord: { zone, providerZone, record, providerRecord, edits in
                let zone = try requireWritable(zone, in: providerZone, when: \.isWritable)
                try requireEditable(providerRecord)
                let mutation = try edits.toUltraDNSRRSet(zoneName: zone.name, existing: record)
                let sameIdentity = mutation.owner.caseInsensitiveCompare(record.ownerName) == .orderedSame &&
                    mutation.type.caseInsensitiveCompare(record.type) == .orderedSame
                if sameIdentity {
                    try await service.replaceRRSet(
                        zone: zone.name,
                        owner: mutation.owner,
                        type: mutation.type,
                        write: mutation.write
                    )
                    return
                }
                try await service.createRRSet(
                    zone: zone.name,
                    owner: mutation.owner,
                    type: mutation.type,
                    write: mutation.write
                )
                do {
                    try await service.deleteRRSet(zone: zone.name, owner: record.ownerName, type: record.type)
                } catch {
                    try? await service.deleteRRSet(
                        zone: zone.name,
                        owner: mutation.owner,
                        type: mutation.type
                    )
                    throw error
                }
            }
        )
    }
}

struct GoDaddyDNSProviderService: DNSProviderService {
    let provider = DNSProvider.goDaddy
    let service: GoDaddyService

    func listZones(environmentId: UUID) async throws -> [ProviderZone] {
        try await service.listDomains().map {
            ProviderZone(provider: provider, snapshot: $0.snapshot(), environmentId: environmentId)
        }
    }

    func zoneDetails(for zone: ProviderZone) async throws -> ProviderZone {
        let nativeZone = try nativeZone(zone, as: GoDaddyDomain.self)
        let details = try await service.getDomain(name: nativeZone.domain)
        return ProviderZone(provider: provider, snapshot: details.snapshot(), environmentId: zone.environmentId)
    }

    func updateNameservers(for zone: ProviderZone, nameservers: [String]) async throws {
        try await service.updateNameservers(
            domain: nativeZone(zone, as: GoDaddyDomain.self).domain,
            nameservers: nameservers
        )
    }

    func records(for zone: ProviderZone) async throws -> [ProviderRecord] {
        let nativeZone = try nativeZone(zone, as: GoDaddyDomain.self)
        return try await goDaddyRecordSets(from: service.listRecords(domain: nativeZone.domain)).map {
            ProviderRecord(provider: provider, snapshot: $0.snapshot())
        }
    }

    func createRecord(in zone: ProviderZone, payload: CreateProviderRecordRequest) async throws {
        let nativeZone = try nativeZone(zone, as: GoDaddyDomain.self)
        let mutation = try payload.toGoDaddyMutation(zoneName: nativeZone.domain)
        try await service.addRecords(domain: nativeZone.domain, records: mutation.records)
    }

    func deleteRecord(in zone: ProviderZone, record: ProviderRecord) async throws {
        let nativeZone = try nativeZone(zone, as: GoDaddyDomain.self)
        let nativeRecord = try writableRecord(from: record)
        try await removeRecordSet(nativeRecord, domain: nativeZone.domain)
    }

    func updateRecord(
        in zone: ProviderZone,
        record: ProviderRecord,
        edits: UpdateProviderRecordRequest
    ) async throws {
        let nativeZone = try nativeZone(zone, as: GoDaddyDomain.self)
        let existing = try writableRecord(from: record)
        let mutation = try edits.toGoDaddyMutation(zoneName: nativeZone.domain, existing: existing)
        let sameEndpoint = mutation.type.caseInsensitiveCompare(existing.type) == .orderedSame &&
            mutation.nativeName.caseInsensitiveCompare(existing.nativeName) == .orderedSame

        if sameEndpoint {
            if mutation.type == "SRV" {
                try await replaceSRVRecordSet(existing, with: mutation, domain: nativeZone.domain)
            } else {
                try await service.replaceRecords(
                    domain: nativeZone.domain,
                    type: mutation.type,
                    name: mutation.nativeName,
                    records: mutation.records
                )
            }
            return
        }

        let destinationBefore = try await service.records(
            domain: nativeZone.domain,
            type: mutation.type,
            name: mutation.nativeName
        )
        let hasConflict = mutation.type == "SRV"
            ? destinationBefore.contains(where: mutation.matchesIdentity)
            : !destinationBefore.isEmpty
        guard !hasConflict else {
            throw ProviderAPIError.invalidRecordContent(
                provider: provider,
                type: mutation.type,
                message: "a record set already exists at the destination name"
            )
        }

        let destinationRecords = nativeWriteRecords(destinationBefore) + mutation.records
        if destinationBefore.isEmpty {
            try await service.addRecords(domain: nativeZone.domain, records: mutation.records)
        } else {
            try await service.replaceRecords(
                domain: nativeZone.domain,
                type: mutation.type,
                name: mutation.nativeName,
                records: destinationRecords
            )
        }

        do {
            try await removeRecordSet(existing, domain: nativeZone.domain)
        } catch {
            if destinationBefore.isEmpty {
                try? await service.deleteRecordSet(
                    domain: nativeZone.domain,
                    type: mutation.type,
                    name: mutation.nativeName
                )
            } else {
                try? await service.replaceRecords(
                    domain: nativeZone.domain,
                    type: mutation.type,
                    name: mutation.nativeName,
                    records: nativeWriteRecords(destinationBefore)
                )
            }
            throw error
        }
    }

    private func replaceSRVRecordSet(
        _ existing: GoDaddyRecordSet,
        with mutation: GoDaddyRecordMutation,
        domain: String
    ) async throws {
        let current = try await service.records(domain: domain, type: existing.type, name: existing.nativeName)
        let siblings = current.filter { !existing.matchesIdentity(of: $0) }
        let identityChanged = existing.service?.caseInsensitiveCompare(mutation.service ?? "") != .orderedSame ||
            existing.recordProtocol?.caseInsensitiveCompare(mutation.recordProtocol ?? "") != .orderedSame
        if identityChanged, siblings.contains(where: mutation.matchesIdentity) {
            throw ProviderAPIError.invalidRecordContent(
                provider: provider,
                type: mutation.type,
                message: "an SRV record set already exists for that service and protocol"
            )
        }
        try await service.replaceRecords(
            domain: domain,
            type: mutation.type,
            name: mutation.nativeName,
            records: nativeWriteRecords(siblings) + mutation.records
        )
    }

    private func removeRecordSet(_ recordSet: GoDaddyRecordSet, domain: String) async throws {
        guard recordSet.type.uppercased() == "SRV" else {
            try await service.deleteRecordSet(domain: domain, type: recordSet.type, name: recordSet.nativeName)
            return
        }

        let current = try await service.records(domain: domain, type: recordSet.type, name: recordSet.nativeName)
        let remaining = current.filter { !recordSet.matchesIdentity(of: $0) }
        if remaining.isEmpty {
            try await service.deleteRecordSet(domain: domain, type: recordSet.type, name: recordSet.nativeName)
        } else {
            try await service.replaceRecords(
                domain: domain,
                type: recordSet.type,
                name: recordSet.nativeName,
                records: nativeWriteRecords(remaining)
            )
        }
    }

    private func nativeWriteRecords(_ records: [GoDaddyDNSRecord]) -> [GoDaddyWriteRecord] {
        records.map {
            GoDaddyWriteRecord(
                type: $0.type,
                name: $0.name,
                data: $0.data,
                ttl: DNSProvider.goDaddy.normalizeTTL($0.ttl) ?? DNSProvider.goDaddy.defaultTTL,
                priority: $0.priority,
                service: $0.service,
                recordProtocol: $0.recordProtocol,
                port: $0.port,
                weight: $0.weight
            )
        }
    }

    private func writableRecord(from record: ProviderRecord) throws -> GoDaddyRecordSet {
        let nativeRecord = try nativeRecord(record, as: GoDaddyRecordSet.self)
        guard provider.capabilities.canEdit(recordType: nativeRecord.type) else {
            throw ProviderOperationError.readOnlyRecord(provider: provider, recordId: record.id)
        }
        return nativeRecord
    }
}

typealias PorkbunDNSProviderService = ProviderDNSAdapter<PorkbunDomain, PorkbunDNSRecord>

extension ProviderDNSAdapter where Zone == PorkbunDomain, Record == PorkbunDNSRecord {
    init(service: PorkbunService) {
        self.init(
            provider: .porkbun,
            loadZones: service.listDomains,
            zoneSnapshot: { $0.snapshot() },
            zoneDetailsSnapshot: { domain in
                let details = try await service.getDomain(name: domain.domain)
                let nameservers = try await service.nameservers(domain: domain.domain)
                return details.snapshot(nameservers: nameservers)
            },
            updateNameservers: { domain, _, nameservers in
                try await service.updateNameservers(domain: domain.domain, nameservers: nameservers)
            },
            loadRecords: { domain, _ in try await service.listRecords(domain: domain.domain).records },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { domain, _, payload in
                for request in try payload.toPorkbunRequests(zoneName: domain.domain) {
                    _ = try await service.createRecord(domain: domain.domain, request: request)
                }
            },
            deleteRecord: { domain, _, record, providerRecord in
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    when: { DNSProvider.porkbun.capabilities.canEdit(recordType: $0.type) }
                )
                try await service.deleteRecord(domain: domain.domain, recordId: record.id)
            },
            updateRecord: { domain, _, record, providerRecord, edits in
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    when: { DNSProvider.porkbun.capabilities.canEdit(recordType: $0.type) }
                )
                try await service.updateRecord(
                    domain: domain.domain,
                    recordId: record.id,
                    request: edits.toPorkbunRequest(zoneName: domain.domain, existing: record)
                )
            }
        )
    }
}

typealias NameComDNSProviderService = ProviderDNSAdapter<NameComDomain, NameComDNSRecord>

extension ProviderDNSAdapter where Zone == NameComDomain, Record == NameComDNSRecord {
    init(service: NameComService) {
        self.init(
            provider: .nameCom,
            loadZones: service.listDomains,
            zoneSnapshot: { $0.snapshot() },
            zoneDetails: { try await service.getDomain(name: $0.domainName) },
            updateNameservers: { domain, _, nameservers in
                try await service.updateNameservers(domain: domain.domainName, nameservers: nameservers)
            },
            loadRecords: { domain, _ in try await service.listRecords(domain: domain.domainName) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { domain, _, payload in
                for request in try payload.toNameComRequests(zoneName: domain.domainName) {
                    _ = try await service.createRecord(domain: domain.domainName, request: request)
                }
            },
            deleteRecord: { domain, _, record, providerRecord in
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    when: { DNSProvider.nameCom.capabilities.canEdit(recordType: $0.type) }
                )
                try await service.deleteRecord(domain: domain.domainName, recordId: record.id)
            },
            updateRecord: { domain, _, record, providerRecord, edits in
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    when: { DNSProvider.nameCom.capabilities.canEdit(recordType: $0.type) }
                )
                _ = try await service.updateRecord(
                    domain: domain.domainName,
                    recordId: record.id,
                    request: edits.toNameComRequest(zoneName: domain.domainName, existing: record)
                )
            }
        )
    }
}

typealias NamecheapDNSProviderService = ProviderDNSAdapter<NamecheapDomain, NamecheapHost>

extension ProviderDNSAdapter where Zone == NamecheapDomain, Record == NamecheapHost {
    init(service: NamecheapService) {
        self.init(
            provider: .namecheap,
            loadZones: service.listDomains,
            zoneSnapshot: { $0.snapshot() },
            zoneDetails: service.domainDetails,
            updateNameservers: { domain, _, nameservers in
                try await service.updateNameservers(domain: domain, nameservers: nameservers)
            },
            loadRecords: { domain, _ in try await service.listHosts(domain: domain) },
            recordSnapshot: { record, domain, _ in record.snapshot(zoneName: domain.name) },
            createRecord: { domain, _, payload in
                try await service.createHosts(domain: domain, payload: payload)
            },
            createRecords: { domain, _, payloads in
                await service.createHosts(domain: domain, payloads: payloads)
            },
            deleteRecord: { domain, _, record, providerRecord in
                try requireEditable(providerRecord)
                try await service.deleteHost(domain: domain, record: record)
            },
            updateRecord: { domain, _, record, providerRecord, edits in
                try requireEditable(providerRecord)
                try await service.updateHost(domain: domain, record: record, edits: edits)
            }
        )
    }
}

typealias SpaceshipDNSProviderService = ProviderDNSAdapter<SpaceshipDomain, SpaceshipDNSRecord>

extension ProviderDNSAdapter where Zone == SpaceshipDomain, Record == SpaceshipDNSRecord {
    init(service: SpaceshipService) {
        self.init(
            provider: .spaceship,
            loadZones: service.listDomains,
            zoneSnapshot: { $0.snapshot() },
            zoneDetails: { try await service.getDomain(name: $0.name) },
            updateNameservers: { domain, _, nameservers in
                try await service.updateNameservers(domain: domain.name, nameservers: nameservers)
            },
            loadRecords: { domain, _ in try await service.listRecords(domain: domain.name) },
            recordSnapshot: { record, domain, _ in record.snapshot(zoneName: domain.name) },
            createRecord: { domain, _, payload in
                try await service.saveRecords(
                    domain: domain.name,
                    records: payload.toSpaceshipMutations(zoneName: domain.name)
                )
            },
            deleteRecord: { domain, _, record, providerRecord in
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    when: { providerRecord.isEditable && $0.group?.type == "custom" }
                )
                try await service.deleteRecords(
                    domain: domain.name,
                    records: [record.mutation(ttl: nil)]
                )
            },
            updateRecord: { domain, _, record, providerRecord, edits in
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    when: { providerRecord.isEditable && $0.group?.type == "custom" }
                )
                let previous = record.mutation(ttl: nil)
                let updated = try edits.toSpaceshipMutation(zoneName: domain.name, existing: record)
                if previous.comparisonData == updated.comparisonData {
                    try await service.saveRecords(domain: domain.name, records: [updated])
                    return
                }
                try await service.saveRecords(domain: domain.name, records: [updated])
                do {
                    try await service.deleteRecords(domain: domain.name, records: [previous])
                } catch {
                    try? await service.deleteRecords(domain: domain.name, records: [updated])
                    throw error
                }
            }
        )
    }
}

typealias IONOSDNSProviderService = ProviderDNSAdapter<IONOSZone, IONOSRecord>

extension ProviderDNSAdapter where Zone == IONOSZone, Record == IONOSRecord {
    init(service: IONOSService) {
        self.init(
            provider: .ionos,
            loadZones: service.listZones,
            zoneSnapshot: { $0.snapshot() },
            zoneDetailsSnapshot: { try await service.getZone(id: $0.id).snapshot() },
            loadRecords: { zone, _ in try await service.getZone(id: zone.id).records },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { zone, providerZone, payload in
                let zone = try requireWritable(
                    zone,
                    in: providerZone,
                    when: { $0.type.caseInsensitiveCompare("SLAVE") != .orderedSame }
                )
                let requests = try payload.toIONOSMutations(zoneName: zone.name).map(\.createRequest)
                _ = try await service.createRecords(zoneId: zone.id, requests: requests)
            },
            deleteRecord: { zone, providerZone, record, providerRecord in
                let zone = try requireWritable(
                    zone,
                    in: providerZone,
                    when: { $0.type.caseInsensitiveCompare("SLAVE") != .orderedSame }
                )
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    when: { DNSProvider.ionos.capabilities.canEdit(recordType: $0.type) }
                )
                try await service.deleteRecord(zoneId: zone.id, recordId: record.id)
            },
            updateRecord: { zone, providerZone, record, providerRecord, edits in
                let zone = try requireWritable(
                    zone,
                    in: providerZone,
                    when: { $0.type.caseInsensitiveCompare("SLAVE") != .orderedSame }
                )
                let record = try requireWritable(
                    record,
                    for: providerRecord,
                    when: { DNSProvider.ionos.capabilities.canEdit(recordType: $0.type) }
                )
                let mutation = try edits.toIONOSMutation(zoneName: zone.name, existing: record)
                let sameIdentity = mutation.name.caseInsensitiveCompare(record.name) == .orderedSame &&
                    mutation.type.caseInsensitiveCompare(record.type) == .orderedSame
                if sameIdentity {
                    _ = try await service.updateRecord(
                        zoneId: zone.id,
                        recordId: record.id,
                        request: mutation.updateRequest
                    )
                    return
                }
                let created = try await service.createRecords(
                    zoneId: zone.id,
                    requests: [mutation.createRequest]
                )
                guard created.count == 1, let createdRecord = created.first else {
                    throw ProviderAPIError.decoding(
                        provider: .ionos,
                        message: "IONOS returned \(created.count) records after a single-record create."
                    )
                }
                do {
                    try await service.deleteRecord(zoneId: zone.id, recordId: record.id)
                } catch {
                    try? await service.deleteRecord(zoneId: zone.id, recordId: createdRecord.id)
                    throw error
                }
            }
        )
    }
}

struct AzureDNSProviderService: DNSProviderService {
    let provider = DNSProvider.azureDNS
    let service: AzureDNSService

    func listZones(environmentId: UUID) async throws -> [ProviderZone] {
        try await service.listZones().map {
            ProviderZone(provider: provider, snapshot: $0.snapshot(), environmentId: environmentId)
        }
    }

    func createZone(named name: String, environmentId: UUID) async throws -> ProviderZone {
        let zone = try await service.createZone(name: name)
        return ProviderZone(provider: provider, snapshot: zone.snapshot(), environmentId: environmentId)
    }

    func zoneDetails(for zone: ProviderZone) async throws -> ProviderZone {
        let nativeZone = try nativeZone(zone, as: AzureDNSZone.self)
        let details = try await service.getZone(nativeZone)
        return ProviderZone(provider: provider, snapshot: details.snapshot(), environmentId: zone.environmentId)
    }

    func deleteZone(_ zone: ProviderZone) async throws {
        let nativeZone = try writableZone(from: zone)
        guard nativeZone.etag != nil else {
            throw missingETag(resource: "zone \(nativeZone.name)")
        }
        try await service.deleteZone(nativeZone)
    }

    func records(for zone: ProviderZone) async throws -> [ProviderRecord] {
        let nativeZone = try nativeZone(zone, as: AzureDNSZone.self)
        return try await service.listRecordSets(zone: nativeZone).map {
            ProviderRecord(provider: provider, snapshot: $0.snapshot(zoneName: nativeZone.name))
        }
    }

    func createRecord(in zone: ProviderZone, payload: CreateProviderRecordRequest) async throws {
        let nativeZone = try writableZone(from: zone)
        let mutation = try payload.toAzureDNSMutation(zoneName: nativeZone.name)
        _ = try await service.putRecordSet(zone: nativeZone, mutation: mutation, ifNoneMatch: "*")
    }

    func deleteRecord(in zone: ProviderZone, record: ProviderRecord) async throws {
        let nativeZone = try writableZone(from: zone)
        let nativeRecord = try writableRecord(from: record)
        let etag = try requiredETag(for: nativeRecord)
        try await service.deleteRecordSet(
            zone: nativeZone,
            relativeName: nativeRecord.name,
            type: nativeRecord.recordType,
            etag: etag
        )
    }

    func updateRecord(
        in zone: ProviderZone,
        record: ProviderRecord,
        edits: UpdateProviderRecordRequest
    ) async throws {
        let nativeZone = try writableZone(from: zone)
        let nativeRecord = try writableRecord(from: record)
        let sourceETag = try requiredETag(for: nativeRecord)
        let mutation = try edits.toAzureDNSMutation(zoneName: nativeZone.name, existing: nativeRecord)
        let sameIdentity = mutation.relativeName.caseInsensitiveCompare(nativeRecord.name) == .orderedSame &&
            mutation.type.caseInsensitiveCompare(nativeRecord.recordType) == .orderedSame

        if sameIdentity {
            _ = try await service.putRecordSet(
                zone: nativeZone,
                mutation: mutation,
                ifMatch: sourceETag
            )
            return
        }

        let created = try await service.putRecordSet(
            zone: nativeZone,
            mutation: mutation,
            ifNoneMatch: "*"
        )
        do {
            try await service.deleteRecordSet(
                zone: nativeZone,
                relativeName: nativeRecord.name,
                type: nativeRecord.recordType,
                etag: sourceETag
            )
        } catch {
            try? await service.deleteRecordSet(
                zone: nativeZone,
                relativeName: created.name,
                type: created.recordType,
                etag: created.etag
            )
            throw error
        }
    }

    private func writableZone(from zone: ProviderZone) throws -> AzureDNSZone {
        let nativeZone = try nativeZone(zone, as: AzureDNSZone.self)
        guard nativeZone.isPublic else {
            throw ProviderOperationError.readOnlyZone(provider: provider, zoneName: nativeZone.name)
        }
        return nativeZone
    }

    private func writableRecord(from record: ProviderRecord) throws -> AzureDNSRecordSet {
        let nativeRecord = try nativeRecord(record, as: AzureDNSRecordSet.self)
        guard provider.capabilities.canEdit(recordType: nativeRecord.recordType) else {
            throw ProviderOperationError.readOnlyRecord(provider: provider, recordId: record.id)
        }
        return nativeRecord
    }

    private func requiredETag(for record: AzureDNSRecordSet) throws -> String {
        guard let etag = record.etag, !etag.isEmpty else {
            throw missingETag(resource: "record set \(record.name) \(record.recordType)")
        }
        return etag
    }

    private func missingETag(resource: String) -> ProviderAPIError {
        ProviderAPIError.decoding(
            provider: provider,
            message: "\(resource) did not include the ETag required for a concurrency-safe mutation"
        )
    }
}

struct OracleCloudDNSProviderService: DNSProviderService {
    let provider = DNSProvider.oracleCloud
    let service: OracleCloudDNSService

    func listZones(environmentId: UUID) async throws -> [ProviderZone] {
        try await service.listZones().map {
            ProviderZone(provider: provider, snapshot: $0.snapshot(), environmentId: environmentId)
        }
    }

    func createZone(named name: String, environmentId: UUID) async throws -> ProviderZone {
        let zone = try await service.createZone(name: name)
        return ProviderZone(provider: provider, snapshot: zone.snapshot(), environmentId: environmentId)
    }

    func zoneDetails(for zone: ProviderZone) async throws -> ProviderZone {
        let nativeZone = try nativeZone(zone, as: OracleCloudZone.self)
        let details = try await service.getZone(nativeZone)
        return ProviderZone(provider: provider, snapshot: details.snapshot(), environmentId: zone.environmentId)
    }

    func deleteZone(_ zone: ProviderZone) async throws {
        let nativeZone = try nativeZone(zone, as: OracleCloudZone.self)
        let current = try await service.getZone(nativeZone)
        guard !current.isProtected else {
            throw ProviderOperationError.readOnlyZone(provider: provider, zoneName: current.name)
        }
        guard let etag = current.etag, !etag.isEmpty else {
            throw missingETag(resource: "zone \(current.name)")
        }
        try await service.deleteZone(current, etag: etag)
    }

    func records(for zone: ProviderZone) async throws -> [ProviderRecord] {
        let nativeZone = try nativeZone(zone, as: OracleCloudZone.self)
        return try await service.listRecordSets(zone: nativeZone).map {
            ProviderRecord(provider: provider, snapshot: $0.snapshot())
        }
    }

    func createRecord(in zone: ProviderZone, payload: CreateProviderRecordRequest) async throws {
        let nativeZone = try writableZone(from: zone)
        let mutation = try payload.toOracleCloudMutation(zoneName: nativeZone.name)
        if try await service.rrSetIfExists(
            zone: nativeZone,
            domain: mutation.domain,
            type: mutation.type
        ) != nil {
            throw ProviderAPIError.operationFailed(
                provider: provider,
                operation: "record creation",
                message: "an RRset already exists at \(mutation.domain) \(mutation.type)"
            )
        }
        _ = try await service.putRRSet(zone: nativeZone, mutation: mutation)
    }

    func deleteRecord(in zone: ProviderZone, record: ProviderRecord) async throws {
        let nativeZone = try writableZone(from: zone)
        let listedRecord = try nativeRecord(record, as: OracleCloudRRSet.self)
        let current = try await service.getRRSet(
            zone: nativeZone,
            domain: listedRecord.domain,
            type: listedRecord.type
        )
        try requireWritable(current, recordId: record.id)
        let etag = try requiredETag(for: current)
        try await service.deleteRRSet(
            zone: nativeZone,
            domain: current.domain,
            type: current.type,
            etag: etag
        )
    }

    func updateRecord(
        in zone: ProviderZone,
        record: ProviderRecord,
        edits: UpdateProviderRecordRequest
    ) async throws {
        let nativeZone = try writableZone(from: zone)
        let listedRecord = try nativeRecord(record, as: OracleCloudRRSet.self)
        let current = try await service.getRRSet(
            zone: nativeZone,
            domain: listedRecord.domain,
            type: listedRecord.type
        )
        try requireWritable(current, recordId: record.id)
        let sourceETag = try requiredETag(for: current)
        let mutation = try edits.toOracleCloudMutation(zoneName: nativeZone.name, existing: current)
        let sameIdentity = mutation.domain.caseInsensitiveCompare(current.domain) == .orderedSame &&
            mutation.type.caseInsensitiveCompare(current.type) == .orderedSame

        if sameIdentity {
            _ = try await service.putRRSet(
                zone: nativeZone,
                mutation: mutation,
                ifMatch: sourceETag
            )
            return
        }

        if try await service.rrSetIfExists(
            zone: nativeZone,
            domain: mutation.domain,
            type: mutation.type
        ) != nil {
            throw ProviderAPIError.operationFailed(
                provider: provider,
                operation: "record update",
                message: "the destination RRset already exists at \(mutation.domain) \(mutation.type)"
            )
        }

        let created = try await service.putRRSet(zone: nativeZone, mutation: mutation)
        do {
            try await service.deleteRRSet(
                zone: nativeZone,
                domain: current.domain,
                type: current.type,
                etag: sourceETag
            )
        } catch {
            if let createdETag = created.etag, !createdETag.isEmpty {
                try? await service.deleteRRSet(
                    zone: nativeZone,
                    domain: created.domain,
                    type: created.type,
                    etag: createdETag
                )
            }
            throw error
        }
    }

    private func writableZone(from zone: ProviderZone) throws -> OracleCloudZone {
        let nativeZone = try nativeZone(zone, as: OracleCloudZone.self)
        guard nativeZone.isWritablePublicPrimary else {
            throw ProviderOperationError.readOnlyZone(provider: provider, zoneName: nativeZone.name)
        }
        return nativeZone
    }

    private func requireWritable(_ record: OracleCloudRRSet, recordId: String) throws {
        guard provider.capabilities.canEdit(recordType: record.type), !record.isProtected else {
            throw ProviderOperationError.readOnlyRecord(provider: provider, recordId: recordId)
        }
    }

    private func requiredETag(for record: OracleCloudRRSet) throws -> String {
        guard let etag = record.etag, !etag.isEmpty else {
            throw missingETag(resource: "RRset \(record.domain) \(record.type)")
        }
        return etag
    }

    private func missingETag(resource: String) -> ProviderAPIError {
        ProviderAPIError.decoding(
            provider: provider,
            message: "\(resource) did not include the ETag required for a concurrency-safe mutation"
        )
    }
}

typealias Route53DNSProviderService = ProviderDNSAdapter<R53HostedZone, R53ResourceRecordSet>

extension ProviderDNSAdapter where Zone == R53HostedZone, Record == R53ResourceRecordSet {
    init(service: Route53Service) {
        self.init(
            provider: .route53,
            loadZones: service.listHostedZones,
            zoneSnapshot: { $0.snapshot() },
            createZone: { try await service.createHostedZone(name: $0) },
            updateNameservers: { _, zone, nameservers in
                try await service.updateDomainNameservers(domain: zone.name, nameservers: nameservers)
            },
            loadRecords: { zone, _ in
                try await service.listResourceRecordSets(hostedZoneId: zone.id)
            },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { zone, providerZone, payload in
                _ = try await service.createRecord(
                    hostedZoneId: zone.id,
                    request: payload.toRoute53Request(zoneName: providerZone.name)
                )
            },
            deleteRecord: { zone, _, record, _ in
                _ = try await service.deleteRecord(hostedZoneId: zone.id, record: record)
            },
            updateRecord: { zone, providerZone, record, _, edits in
                _ = try await service.updateRecord(
                    hostedZoneId: zone.id,
                    request: edits.toRoute53Request(oldRecord: record, zoneName: providerZone.name)
                )
            }
        )
    }
}

typealias VercelDNSProviderService = ProviderDNSAdapter<VercelDomain, VercelDNSRecord>

extension ProviderDNSAdapter where Zone == VercelDomain, Record == VercelDNSRecord {
    init(service: VercelService) {
        self.init(
            provider: .vercel,
            loadZones: { try await service.listDomains() },
            zoneSnapshot: { $0.snapshot() },
            createZone: { try await service.createDomain(name: $0) },
            updateNameservers: { domain, _, nameservers in
                try await service.updateNameservers(domain: domain.name, nameservers: nameservers)
            },
            loadRecords: { domain, _ in try await service.listDNSRecords(domain: domain.name) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { domain, _, payload in
                _ = try await service.createDNSRecord(
                    domain: domain.name,
                    payload: payload.toVercelRequest(domain: domain.name)
                )
            },
            deleteRecord: { domain, _, record, _ in
                _ = try await service.deleteDNSRecord(domain: domain.name, recordId: record.id)
            },
            updateRecord: { domain, _, record, _, edits in
                _ = try await service.updateDNSRecord(
                    recordId: record.id,
                    payload: edits.toVercelRequest(domain: domain.name, existingRecord: record)
                )
            }
        )
    }
}

typealias GoogleCloudDNSProviderService = ProviderDNSAdapter<GCPManagedZone, GCPResourceRecordSet>

extension ProviderDNSAdapter where Zone == GCPManagedZone, Record == GCPResourceRecordSet {
    init(service: GoogleCloudService) {
        self.init(
            provider: .googleCloud,
            loadZones: { try await service.listZones() },
            zoneSnapshot: { $0.snapshot() },
            createZone: { try await service.createZone(name: $0) },
            updateNameservers: { _, zone, nameservers in
                try await service.updateDomainNameservers(domain: zone.name, nameservers: nameservers)
            },
            loadRecords: { zone, _ in try await service.listRecords(zoneId: zone.id) },
            recordSnapshot: { record, _, _ in record.snapshot() },
            createRecord: { zone, _, payload in
                _ = try await service.createRecord(
                    zoneId: zone.id,
                    record: payload.toGoogleCloudRequest(zoneName: zone.dnsName)
                )
            },
            deleteRecord: { zone, _, record, _ in
                try await service.deleteRecord(zoneId: zone.id, record: record)
            },
            updateRecord: { zone, _, record, _, edits in
                let updated = edits.toGoogleCloudRequest(oldRecord: record, zoneName: zone.dnsName)
                _ = try await service.updateRecord(
                    zoneId: zone.id,
                    oldRecord: record,
                    newRecord: updated
                )
            }
        )
    }
}
