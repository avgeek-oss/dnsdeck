import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let environmentManager = EnvironmentManager.shared
    let lockController: AppLockController
    private let cacheManager = CacheManager.shared
    private let settings = SettingsManager.shared
    @Published var selectedEnvironment: DNSEnvironment? {
        didSet {
            refreshZonesTask?.cancel()
            refreshRecordsTask?.cancel()

            refreshZonesTask = Task { @MainActor in
                await Task.yield()
                zones.removeAll()
                records.removeAll()
                selectedZone = nil
                if selectedEnvironment != nil {
                    await refreshZones()
                }
            }
        }
    }

    private var refreshZonesTask: Task<Void, Never>?
    private var refreshRecordsTask: Task<Void, Never>?
    private var serviceInstances: [UUID: ProviderServiceBundle] = [:]

    let errorHandler = ErrorHandler()

    let providers: [DNSProvider] = DNSProvider.allCases
    @Published var zones: [ProviderZone] = []
    @Published var selectedZone: ProviderZone?

    @Published var records: [ProviderRecord] = []
    @Published var isLoading = false
    @Published var error: String?

    @Published private var editableCredentials: [UUID: [DNSProvider: [String: String]]] = [:]

    private var cancellables = Set<AnyCancellable>()

    init(lockController: AppLockController, selectsInitialEnvironment: Bool = true) {
        self.lockController = lockController

        environmentManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: .providerCredentialsDidChange)
            .sink { [weak self] notification in
                guard let self,
                      notification.object as AnyObject? !== self,
                      let environmentID = notification.userInfo?[NotificationUserInfoKey.environmentID] as? UUID
                else { return }
                handleCredentialChange(for: environmentID)
            }
            .store(in: &cancellables)

        performMigrationIfNeeded()

        if selectsInitialEnvironment, selectedEnvironment == nil {
            if let starredEnv = environmentManager.environments.first(where: { $0.isStarred }) {
                selectedEnvironment = starredEnv
            } else if let firstEnv = environmentManager.environments.first {
                selectedEnvironment = firstEnv
            }
        }
    }

    private func services(for environmentId: UUID) -> ProviderServiceBundle {
        if let existing = serviceInstances[environmentId] {
            return existing
        }

        let services = ProviderServiceFactory.makeServices(environmentId: environmentId)
        serviceInstances[environmentId] = services
        return services
    }

    func credentialBinding(
        for provider: DNSProvider,
        fieldId: String,
        environmentId: UUID
    ) -> Binding<String> {
        Binding(
            get: { self.editableCredentials[environmentId]?[provider]?[fieldId] ?? "" },
            set: {
                if self.editableCredentials[environmentId] == nil {
                    self.editableCredentials[environmentId] = [:]
                }
                if self.editableCredentials[environmentId]?[provider] == nil {
                    self.editableCredentials[environmentId]?[provider] = [:]
                }
                self.editableCredentials[environmentId]?[provider]?[fieldId] = $0
            }
        )
    }

    func loadCredentials(for environmentId: UUID) {
        editableCredentials[environmentId] = [:]

        for provider in providers {
            let stored = provider.storedCredentials(environmentId: environmentId)
            guard !stored.isEmpty else { continue }
            editableCredentials[environmentId]?[provider] = stored
        }
    }

    func saveCredential(for provider: DNSProvider, environmentId: UUID) {
        let credentials = editableCredentials[environmentId]?[provider] ?? [:]
        do {
            try provider.saveCredentials(credentials, environmentId: environmentId)
            serviceInstances.removeValue(forKey: environmentId)
            cacheManager.invalidateEnvironment(environmentId: environmentId)
            if environmentId == selectedEnvironment?.id {
                Task { await refreshZones(forceRefresh: true) }
            }
            postCredentialChange(for: environmentId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Clears a provider's stored credentials and refreshes zones so any zone
    /// belonging to the disconnected provider (including the selected one) is
    /// removed from the view.
    func disconnect(provider: DNSProvider, environmentId: UUID) {
        do {
            try provider.deleteCredentials(environmentId: environmentId)
            serviceInstances.removeValue(forKey: environmentId)
            cacheManager.invalidateEnvironment(environmentId: environmentId)
            loadCredentials(for: environmentId)
            if environmentId == selectedEnvironment?.id {
                Task { await refreshZones(forceRefresh: true) }
            }
            postCredentialChange(for: environmentId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func postCredentialChange(for environmentID: UUID) {
        NotificationCenter.default.post(
            name: .providerCredentialsDidChange,
            object: self,
            userInfo: [NotificationUserInfoKey.environmentID: environmentID]
        )
    }

    private func handleCredentialChange(for environmentID: UUID) {
        serviceInstances.removeValue(forKey: environmentID)
        cacheManager.invalidateEnvironment(environmentId: environmentID)
        loadCredentials(for: environmentID)
        if environmentID == selectedEnvironment?.id {
            Task { await refreshZones(forceRefresh: true) }
        }
    }

    private func performMigrationIfNeeded() {
        let migrationKey = UITestConfiguration.storageKey("dnsdeck.migration.completed")
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        let oldCloudflareStore = KeychainTokenStore(
            service: Constants.keychainService,
            account: "cloudflare.token"
        )

        let oldRoute53Store = KeychainRoute53CredentialsStore(service: Constants.keychainService)

        var hasOldCredentials = false

        if let oldToken = try? oldCloudflareStore.read(), !oldToken.trimmed.isEmpty {
            hasOldCredentials = true
        }

        if let oldCredentials = try? oldRoute53Store.read(),
           !oldCredentials.accessKeyId.trimmed.isEmpty,
           !oldCredentials.secretAccessKey.trimmed.isEmpty
        {
            hasOldCredentials = true
        }

        if hasOldCredentials {
            if environmentManager.environments.isEmpty {
                _ = environmentManager.createEnvironment(name: "Default")
            }

            guard let defaultEnv = environmentManager.environments.first else { return }

            if let oldToken = try? oldCloudflareStore.read(), !oldToken.trimmed.isEmpty {
                let newStore = KeychainTokenStore(
                    service: Constants.keychainService,
                    account: "cloudflare.token",
                    environmentId: defaultEnv.id
                )
                if (try? newStore.save(oldToken)) != nil {
                    try? oldCloudflareStore.delete()
                }
            }

            if let oldCredentials = try? oldRoute53Store.read(),
               !oldCredentials.accessKeyId.trimmed.isEmpty,
               !oldCredentials.secretAccessKey.trimmed.isEmpty
            {
                let newStore = KeychainRoute53CredentialsStore(
                    service: Constants.keychainService,
                    environmentId: defaultEnv.id
                )
                if (try? newStore.save(oldCredentials)) != nil {
                    try? oldRoute53Store.delete()
                }
            }

            UserDefaults.standard.set(true, forKey: migrationKey)

            selectedEnvironment = defaultEnv
        } else {
            if environmentManager.environments.isEmpty {
                _ = environmentManager.createEnvironment(name: "Default")
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }

    func refreshZones(forceRefresh: Bool = false) async {
        guard let environmentId = selectedEnvironment?.id else {
            zones = []
            return
        }

        refreshZonesTask?.cancel()

        let task = Task { @MainActor in
            isLoading = true
            defer { self.isLoading = false }

            let cacheKey = cacheManager.zonesKey(environmentId: environmentId)

            if !forceRefresh,
               settings.enableCache,
               let cachedZones: [ProviderZone] = cacheManager.get([ProviderZone].self, key: cacheKey)
            {
                guard !Task.isCancelled else { return }
                guard selectedEnvironment?.id == environmentId else { return }

                zones = cachedZones.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if let current = selectedZone, !cachedZones.contains(current) {
                    selectZone(nil)
                }
                return
            }

            var aggregated: [ProviderZone] = []
            var failedProviders: Set<DNSProvider> = []
            let previousZones = zones
            let envServices = services(for: environmentId)

            for provider in providers {
                guard !Task.isCancelled else { return }
                guard selectedEnvironment?.id == environmentId else { return }
                guard provider.isConnected(environmentId: environmentId) else { continue }

                do {
                    let providerZones = try await provider.listZones(
                        environmentId: environmentId,
                        services: envServices
                    )
                    guard !Task.isCancelled else { return }
                    guard selectedEnvironment?.id == environmentId else { return }

                    aggregated.append(contentsOf: providerZones)
                } catch {
                    if !Task.isCancelled, selectedEnvironment?.id == environmentId {
                        failedProviders.insert(provider)
                        aggregated.append(contentsOf: previousZones.filter { $0.provider == provider })
                        errorHandler.handle(error)
                    }
                }
            }

            guard !Task.isCancelled else { return }
            guard selectedEnvironment?.id == environmentId else { return }

            let sortedZones = aggregated
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            zones = sortedZones

            if settings.enableCache, failedProviders.isEmpty {
                cacheManager.set(sortedZones, key: cacheKey, ttl: settings.zonesCacheTTL)
            }

            if let current = selectedZone, !sortedZones.contains(where: { $0.id == current.id }) {
                selectZone(nil)
            }
        }

        refreshZonesTask = task
        await task.value
    }

    func refreshRecords(for zone: ProviderZone, forceRefresh: Bool = false) async {
        let zoneId = zone.id
        let environmentId = zone.environmentId
        let envServices = services(for: environmentId)
        let cacheKey = cacheManager.recordsKey(environmentId: environmentId, zoneId: zone.id)

        isLoading = true
        defer { self.isLoading = false }

        if !forceRefresh,
           settings.enableCache,
           let cachedRecords: [ProviderRecord] = cacheManager.get([ProviderRecord].self, key: cacheKey)
        {
            guard selectedZone?.id == zoneId else { return }
            records = cachedRecords
            return
        }

        do {
            let fetchedRecords = try await cacheManager.deduplicate(key: cacheKey) {
                try await zone.provider.records(for: zone, services: envServices)
            }

            guard selectedZone?.id == zoneId else { return }
            records = fetchedRecords

            if settings.enableCache {
                cacheManager.set(fetchedRecords, key: cacheKey, ttl: settings.recordsCacheTTL)
            }
        } catch {
            guard selectedZone?.id == zoneId else { return }
            errorHandler.handle(error)
        }
    }

    func createZone(named name: String, provider: DNSProvider, environmentId: UUID) async throws -> ProviderZone {
        let trimmedName = name.trimmed.lowercased()
        let envServices = services(for: environmentId)
        let createdZone = try await provider.createZone(
            named: trimmedName,
            environmentId: environmentId,
            services: envServices
        )
        let enrichedZone = await detailedZoneIfAvailable(for: createdZone)

        cacheManager.invalidate(key: cacheManager.zonesKey(environmentId: environmentId))

        if selectedEnvironment?.id == environmentId {
            var updatedZones = zones.filter { $0.id != enrichedZone.id }
            updatedZones.append(enrichedZone)
            zones = updatedZones.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selectZone(enrichedZone)
        }

        if selectedEnvironment?.id == environmentId {
            Task { @MainActor [environmentId] in
                guard self.selectedEnvironment?.id == environmentId else { return }
                await self.refreshZones(forceRefresh: true)
            }
        }

        return enrichedZone
    }

    func deleteZone(_ zone: ProviderZone) async throws {
        let environmentId = zone.environmentId
        let envServices = services(for: environmentId)

        try await zone.provider.deleteZone(zone, services: envServices)

        cacheManager.invalidate(key: cacheManager.zonesKey(environmentId: environmentId))
        cacheManager.invalidate(key: cacheManager.recordsKey(environmentId: environmentId, zoneId: zone.id))

        zones.removeAll { $0.id == zone.id }
        if selectedZone?.id == zone.id {
            selectZone(nil)
        }
    }

    func updateNameservers(for zone: ProviderZone, nameservers: [String]) async throws {
        guard zone.provider.supportsNameserverUpdate(for: zone),
              let policy = zone.provider.nameserverPolicy
        else {
            throw ProviderOperationError.unsupportedNameserverUpdate(provider: zone.provider)
        }
        let normalized = try NameserverUpdate.normalize(nameservers, policy: policy)
        let environmentId = zone.environmentId
        let envServices = services(for: environmentId)

        try await zone.provider.updateNameservers(
            for: zone,
            nameservers: normalized,
            services: envServices
        )

        cacheManager.invalidate(key: cacheManager.zonesKey(environmentId: environmentId))
        if selectedEnvironment?.id == environmentId {
            await refreshZones(forceRefresh: true)
        }
    }

    func selectZone(_ zone: ProviderZone?) {
        refreshRecordsTask?.cancel()
        refreshRecordsTask = Task { @MainActor in
            await Task.yield()
            selectedZone = zone
            if let zone {
                Task {
                    await refreshZoneDetailsIfNeeded(for: zone)
                }
            }
            if let zone {
                await refreshRecords(for: zone)
            } else {
                records.removeAll()
            }
        }
    }

    func refreshZoneDetailsIfNeeded(for zone: ProviderZone) async {
        guard zone.provider.capabilities.zoneCapabilities.contains(.details) else { return }
        let detailedZone = await detailedZoneIfAvailable(for: zone)

        guard detailedZone != zone else { return }

        if let selectedZone, selectedZone.id == detailedZone.id {
            self.selectedZone = detailedZone
        }

        if let index = zones.firstIndex(where: { $0.id == detailedZone.id }) {
            zones[index] = detailedZone
        }

        if settings.enableCache,
           let environmentId = selectedEnvironment?.id,
           environmentId == detailedZone.environmentId
        {
            let sortedZones = zones
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            zones = sortedZones
            cacheManager.set(
                sortedZones,
                key: cacheManager.zonesKey(environmentId: environmentId),
                ttl: settings.zonesCacheTTL
            )
        }
    }

    private func detailedZoneIfAvailable(for zone: ProviderZone) async -> ProviderZone {
        guard zone.provider.capabilities.zoneCapabilities.contains(.details) else { return zone }

        let envServices = services(for: zone.environmentId)

        do {
            return try await zone.provider.zoneDetails(for: zone, services: envServices)
        } catch {
            return zone
        }
    }

    func createRecord(in zone: ProviderZone, payload: CreateProviderRecordRequest) async throws {
        let environmentId = zone.environmentId
        let envServices = services(for: environmentId)

        try await zone.provider.createRecord(in: zone, payload: payload, services: envServices)

        cacheManager.invalidate(key: cacheManager.recordsKey(environmentId: environmentId, zoneId: zone.id))
        await refreshRecords(for: zone)
    }

    struct BatchImportResult {
        let totalRecords: Int
        let successfulRecords: Int
        let failedRecords: Int
        let errors: [BatchImportError]

        var isCompleteSuccess: Bool {
            failedRecords == 0
        }
    }

    struct BatchImportError {
        let recordIndex: Int
        let recordName: String
        let error: Error
    }

    struct RecordCopyCandidate: Identifiable {
        let sourceRecord: ProviderRecord
        let request: CreateProviderRecordRequest
        let previewRecord: RecordCopyPreviewRecord

        var id: String {
            sourceRecord.id
        }
    }

    struct RecordCopyPreviewRecord: Identifiable {
        let id: String
        let type: String
        let name: String
        let content: String
        let ttl: Int?
    }

    struct RecordCopyPreview: Identifiable {
        let id = UUID()
        let sourceZone: ProviderZone
        let destinationZone: ProviderZone
        let selectedCount: Int
        let candidates: [RecordCopyCandidate]
        let skippedExistingRecords: [RecordCopyPreviewRecord]

        var recordsToCopy: [RecordCopyPreviewRecord] {
            candidates.map(\.previewRecord)
        }
    }

    func availableDestinationZones(excluding sourceZone: ProviderZone) async -> [ProviderZone] {
        if selectedEnvironment?.id == sourceZone.environmentId {
            return destinationZones(from: zones, excluding: sourceZone)
        }

        var collectedZones: [ProviderZone] = []
        let environmentId = sourceZone.environmentId
        let envServices = services(for: environmentId)

        for provider in providers where provider.isConnected(environmentId: environmentId) {
            do {
                let providerZones = try await provider.listZones(
                    environmentId: environmentId,
                    services: envServices
                )
                collectedZones.append(contentsOf: providerZones)
            } catch {
                Logger.logError(
                    error,
                    context: "Load destination zones for \(provider.displayName) in \(environmentId.uuidString)"
                )
            }
        }

        return destinationZones(from: collectedZones, excluding: sourceZone)
    }

    private func destinationZones(
        from zones: [ProviderZone],
        excluding sourceZone: ProviderZone
    ) -> [ProviderZone] {
        zones
            .filter { $0.id != sourceZone.id }
            .sorted { lhs, rhs in
                let lhsTuple = (
                    lhs.provider.displayName.lowercased(),
                    lhs.name.lowercased()
                )
                let rhsTuple = (
                    rhs.provider.displayName.lowercased(),
                    rhs.name.lowercased()
                )

                return lhsTuple < rhsTuple
            }
    }

    func prepareRecordCopyPreview(
        from sourceZone: ProviderZone,
        records: [ProviderRecord],
        to destinationZone: ProviderZone
    ) async -> RecordCopyPreview? {
        let destinationServices = services(for: destinationZone.environmentId)

        do {
            let existingDestinationRecords = try await destinationZone.provider.records(
                for: destinationZone,
                services: destinationServices
            )
            let existingSignatures = Set(
                existingDestinationRecords.map { duplicateSignature(for: $0, in: destinationZone) }
            )

            var candidates: [RecordCopyCandidate] = []
            var skippedExistingRecords: [RecordCopyPreviewRecord] = []

            for record in records {
                let request = cloneRequest(for: record, from: sourceZone, to: destinationZone)
                let signature = duplicateSignature(for: request, in: destinationZone)
                let previewRecord = copyPreviewRecord(
                    for: record,
                    request: request,
                    destinationZone: destinationZone
                )

                if existingSignatures.contains(signature) {
                    skippedExistingRecords.append(previewRecord)
                } else {
                    candidates.append(RecordCopyCandidate(
                        sourceRecord: record,
                        request: request,
                        previewRecord: previewRecord
                    ))
                }
            }

            return RecordCopyPreview(
                sourceZone: sourceZone,
                destinationZone: destinationZone,
                selectedCount: records.count,
                candidates: candidates,
                skippedExistingRecords: skippedExistingRecords
            )
        } catch {
            errorHandler.handle(error)
            return nil
        }
    }

    func copyRecordsBatch(
        preview: RecordCopyPreview,
        progressCallback: @escaping (Double) -> Void
    ) async {
        let destinationZone = preview.destinationZone
        let destinationServices = services(for: destinationZone.environmentId)

        _ = await executeRecordBatch(
            preview.candidates,
            operationName: "Copy record to \(destinationZone.name)",
            recordName: \.sourceRecord.name,
            progress: { preview.candidates.isEmpty ? 1 : Double($0) / Double(preview.candidates.count) },
            progressCallback: progressCallback
        ) { candidate in
            try await destinationZone.provider.createRecord(
                in: destinationZone,
                payload: candidate.request,
                services: destinationServices
            )
        }

        cacheManager.invalidate(
            key: cacheManager.recordsKey(
                environmentId: destinationZone.environmentId,
                zoneId: destinationZone.id
            )
        )

        if selectedZone?.id == destinationZone.id {
            await refreshRecords(for: destinationZone, forceRefresh: true)
        }
    }

    func createRecordsBatch(
        in zone: ProviderZone,
        records: [CreateProviderRecordRequest],
        progressCallback: @escaping (Double) -> Void
    ) async -> BatchImportResult {
        let envServices = services(for: zone.environmentId)
        if let service = try? envServices.service(for: zone.provider),
           let providerResults = await service.createRecords(in: zone, payloads: records)
        {
            let results: [Result<Void, Error>] = if providerResults.count == records.count {
                providerResults
            } else {
                records.map { _ in .failure(ProviderAPIError.invalidResponse(provider: zone.provider)) }
            }
            var errors: [BatchImportError] = []
            for (index, result) in results.enumerated() {
                if case let .failure(error) = result {
                    let name = records[index].name
                    errors.append(BatchImportError(recordIndex: index, recordName: name, error: error))
                    Logger.logError(error, context: "Batch import \(name)")
                }
                progressCallback(Double(index + 1) / Double(records.count))
            }
            await refreshAfterRecordBatch(in: zone)
            return BatchImportResult(
                totalRecords: records.count,
                successfulRecords: records.count - errors.count,
                failedRecords: errors.count,
                errors: errors
            )
        }
        return await performRecordBatch(
            records,
            in: zone,
            operationName: "Batch import",
            recordName: \.name,
            progressCallback: progressCallback
        ) { record in
            try await zone.provider.createRecord(in: zone, payload: record, services: envServices)
        }
    }

    func deleteRecords(in zone: ProviderZone, recordIds: [String]) async {
        let environmentId = zone.environmentId
        let envServices = services(for: environmentId)

        for recordId in recordIds {
            do {
                try await zone.provider.deleteRecord(
                    in: zone,
                    recordId: recordId,
                    existingRecords: records,
                    services: envServices
                )
            } catch { errorHandler.handle(error) }
        }

        cacheManager.invalidate(key: cacheManager.recordsKey(environmentId: environmentId, zoneId: zone.id))
        await refreshRecords(for: zone)
    }

    func deleteRecordsBatch(
        in zone: ProviderZone,
        records recordsToDelete: [ProviderRecord],
        progressCallback: @escaping (Double) -> Void
    ) async -> BatchImportResult {
        let envServices = services(for: zone.environmentId)
        let orderedRecords = if zone.provider == .cloudflare {
            recordsToDelete.sorted { cloudflareDeletionRank($0.type) < cloudflareDeletionRank($1.type) }
        } else {
            recordsToDelete
        }
        return await performRecordBatch(
            orderedRecords,
            in: zone,
            operationName: "Batch delete",
            recordName: \.name,
            progressCallback: progressCallback
        ) { record in
            try await zone.provider.deleteRecord(in: zone, record: record, services: envServices)
        }
    }

    private func cloudflareDeletionRank(_ type: String) -> Int {
        switch type.uppercased() {
        case "DS": 0
        case "NS": 2
        default: 1
        }
    }

    private func performRecordBatch<Item>(
        _ items: [Item],
        in zone: ProviderZone,
        operationName: String,
        recordName: KeyPath<Item, String>,
        progressCallback: @escaping (Double) -> Void,
        operation: (Item) async throws -> Void
    ) async -> BatchImportResult {
        let outcome = await executeRecordBatch(
            items,
            operationName: operationName,
            recordName: recordName,
            progress: { Double($0) / Double(items.count) },
            progressCallback: progressCallback,
            operation: operation
        )
        await refreshAfterRecordBatch(in: zone)
        return BatchImportResult(
            totalRecords: items.count,
            successfulRecords: outcome.successful.count,
            failedRecords: outcome.errors.count,
            errors: outcome.errors
        )
    }

    private func executeRecordBatch<Item>(
        _ items: [Item],
        operationName: String,
        recordName: KeyPath<Item, String>,
        progress: (Int) -> Double,
        progressCallback: (Double) -> Void,
        operation: (Item) async throws -> Void
    ) async -> (successful: [Item], errors: [BatchImportError]) {
        var successful: [Item] = []
        var errors: [BatchImportError] = []
        for (index, item) in items.enumerated() {
            do {
                try await operation(item)
                successful.append(item)
            } catch {
                let name = item[keyPath: recordName]
                errors.append(BatchImportError(recordIndex: index, recordName: name, error: error))
                Logger.logError(error, context: "\(operationName) \(name)")
            }
            progressCallback(progress(index + 1))
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return (successful, errors)
    }

    private func refreshAfterRecordBatch(in zone: ProviderZone) async {
        cacheManager.invalidate(key: cacheManager.recordsKey(environmentId: zone.environmentId, zoneId: zone.id))
        await refreshRecords(for: zone)
    }

    struct BatchConvertResult {
        let totalRecords: Int
        let deletedRecords: Int
        let createdRecords: Int
        let deleteErrors: [BatchImportError]
        let createErrors: [BatchImportError]

        var isCompleteSuccess: Bool {
            deleteErrors.isEmpty && createErrors.isEmpty
        }

        var allErrors: [(recordName: String, error: String)] {
            let delErrs = deleteErrors.map { (
                recordName: $0.recordName,
                error: "Delete failed: \($0.error.localizedDescription)"
            ) }
            let createErrs = createErrors.map { (
                recordName: $0.recordName,
                error: "Create failed: \($0.error.localizedDescription)"
            ) }
            return delErrs + createErrs
        }
    }

    func convertRecordsBatch(
        in zone: ProviderZone,
        records recordsToConvert: [ProviderRecord],
        targetType: String,
        progressCallback: @escaping (Double) -> Void
    ) async -> BatchConvertResult {
        let environmentId = zone.environmentId
        let envServices = services(for: environmentId)
        let totalSteps = recordsToConvert.count * 2

        let createOutcome = await executeRecordBatch(
            recordsToConvert,
            operationName: "Bulk convert create",
            recordName: \.name,
            progress: { Double($0) / Double(totalSteps) },
            progressCallback: progressCallback
        ) { record in
            let createRequest = CreateProviderRecordRequest(
                name: record.name,
                type: targetType,
                content: record.content,
                ttl: record.ttl,
                proxied: nil,
                priority: (targetType == "MX" || targetType == "SRV") ? record.priority : nil,
                comment: record.comment
            )
            try await zone.provider.createRecord(in: zone, payload: createRequest, services: envServices)
        }
        let deleteOutcome = await executeRecordBatch(
            createOutcome.successful,
            operationName: "Bulk convert delete",
            recordName: \.name,
            progress: { Double(recordsToConvert.count + $0) / Double(totalSteps) },
            progressCallback: progressCallback
        ) { record in
            try await zone.provider.deleteRecord(in: zone, record: record, services: envServices)
        }

        await refreshAfterRecordBatch(in: zone)

        return BatchConvertResult(
            totalRecords: recordsToConvert.count,
            deletedRecords: deleteOutcome.successful.count,
            createdRecords: createOutcome.successful.count,
            deleteErrors: deleteOutcome.errors,
            createErrors: createOutcome.errors
        )
    }

    private func cloneRequest(
        for record: ProviderRecord,
        from sourceZone: ProviderZone,
        to destinationZone: ProviderZone
    ) -> CreateProviderRecordRequest {
        let normalizedType = record.type.uppercased()
        let relativeName = relativeRecordName(for: record.name, in: sourceZone)

        let normalizedContent = normalizedCopyContent(for: record, type: normalizedType)
        let normalizedPriority = normalizedCopyPriority(for: record, type: normalizedType, content: normalizedContent)
        let normalizedRecordData = normalizedCopyRecordData(
            for: record,
            type: normalizedType,
            relativeName: relativeName,
            destinationZone: destinationZone,
            content: normalizedContent,
            priority: normalizedPriority
        )

        let resolvedContent: String
        let resolvedPriority: Int?

        if normalizedType == "MX" {
            let parsedMX = parseMXComponents(content: normalizedContent, explicitPriority: normalizedPriority)
            resolvedContent = parsedMX.content
            resolvedPriority = parsedMX.priority
        } else if let normalizedRecordData, let flatContent = normalizedRecordData.flatContent {
            resolvedContent = flatContent
            resolvedPriority = normalizedRecordData.priority ?? normalizedPriority
        } else {
            resolvedContent = normalizedContent
            resolvedPriority = normalizedPriority
        }

        return CreateProviderRecordRequest(
            name: relativeName,
            type: normalizedType,
            content: resolvedContent,
            ttl: record.ttl,
            proxied: record.proxied,
            priority: resolvedPriority,
            comment: record.comment,
            recordData: normalizedRecordData
        )
    }

    private func copyPreviewRecord(
        for sourceRecord: ProviderRecord,
        request: CreateProviderRecordRequest,
        destinationZone: ProviderZone
    ) -> RecordCopyPreviewRecord {
        RecordCopyPreviewRecord(
            id: sourceRecord.id,
            type: request.type,
            name: destinationRecordName(for: request, in: destinationZone),
            content: copyPreviewContent(for: request),
            ttl: request.ttl
        )
    }

    private func destinationRecordName(for request: CreateProviderRecordRequest, in zone: ProviderZone) -> String {
        let relativeName = relativeRecordName(for: request.name, in: zone)
        let zoneName = normalizedZoneName(for: zone)

        if relativeName == "@" {
            return zoneName
        }

        return "\(relativeName).\(zoneName)"
    }

    private func normalizedZoneName(for zone: ProviderZone) -> String {
        zone.name.hasSuffix(".") ? String(zone.name.dropLast()) : zone.name
    }

    private func copyPreviewContent(for request: CreateProviderRecordRequest) -> String {
        if let recordData = request.recordData, let flatContent = recordData.flatContent {
            return flatContent
        }

        return request.content
    }

    private func duplicateSignature(for record: ProviderRecord, in zone: ProviderZone) -> String {
        let request = cloneRequest(for: record, from: zone, to: zone)
        return duplicateSignature(for: request, in: zone)
    }

    private func duplicateSignature(for request: CreateProviderRecordRequest, in zone: ProviderZone) -> String {
        let normalizedType = request.type.uppercased()
        let normalizedName = relativeRecordName(for: request.name, in: zone).lowercased()

        let contentSignature: String
        if let recordData = request.recordData, let flatContent = recordData.flatContent {
            contentSignature = flatContent
        } else if normalizedType == "MX" {
            let mx = parseMXComponents(content: request.content, explicitPriority: request.priority)
            if let priority = mx.priority {
                contentSignature = "\(priority) \(mx.content)"
            } else {
                contentSignature = mx.content
            }
        } else {
            contentSignature = request.content
        }

        let ttlSignature = request.ttl.map(String.init) ?? ""
        let proxiedSignature = zone.provider == .cloudflare ? String(request.proxied ?? false) : ""

        return [
            normalizedType,
            normalizedName,
            contentSignature.trimmingCharacters(in: .whitespacesAndNewlines),
            ttlSignature,
            proxiedSignature,
        ].joined(separator: "|")
    }

    private func normalizedCopyContent(for record: ProviderRecord, type: String) -> String {
        record.content
    }

    private func normalizedCopyPriority(for record: ProviderRecord, type: String, content: String) -> Int? {
        if let priority = record.priority {
            return priority
        }

        switch type {
        case "MX":
            return parseMXComponents(content: content, explicitPriority: nil).priority
        case "SRV":
            return parseSRVComponents(content: content, explicitPriority: nil)?.priority
        default:
            return nil
        }
    }

    private func normalizedCopyRecordData(
        for record: ProviderRecord,
        type: String,
        relativeName: String,
        destinationZone: ProviderZone,
        content: String,
        priority: Int?
    ) -> RecordData? {
        let cloudflareData = record.recordData.decode(CFDNSRecord.self)?.data
        return switch type {
        case "CAA":
            cloudflareData ??
                UpdateProviderRecordRequest.cloudflareCAAData(content: content)
        case "SRV":
            cloudflareData ??
                genericSRVRecordData(
                    relativeName: relativeName,
                    destinationZoneName: destinationZone.name,
                    content: content,
                    priority: priority
                )
        default:
            nil
        }
    }

    private func relativeRecordName(for rawName: String, in zone: ProviderZone) -> String {
        let zoneName = normalizedZoneName(for: zone)
        var normalizedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedName.hasSuffix(".") {
            normalizedName.removeLast()
        }

        if normalizedName.isEmpty ||
            normalizedName == "@" ||
            normalizedName == "." ||
            normalizedName == zoneName ||
            normalizedName == ".\(zoneName)"
        {
            return "@"
        }

        let zoneSuffix = ".\(zoneName)"
        if normalizedName.lowercased().hasSuffix(zoneSuffix.lowercased()) {
            let trimmed = String(normalizedName.dropLast(zoneSuffix.count))
            return trimmed.isEmpty ? "@" : trimmed
        }

        return normalizedName
    }

    private func parseMXComponents(content: String, explicitPriority: Int?) -> (priority: Int?, content: String) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if let explicitPriority {
            let parts = trimmedContent.split(separator: " ", maxSplits: 1).map(String.init)
            if parts.count == 2, Int(parts[0]) == explicitPriority {
                return (explicitPriority, parts[1])
            }
            return (explicitPriority, trimmedContent)
        }

        let parts = trimmedContent.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, let parsedPriority = Int(parts[0]) {
            return (parsedPriority, parts[1])
        }

        return (nil, trimmedContent)
    }

    private func parseSRVComponents(
        content: String,
        explicitPriority: Int?
    ) -> (priority: Int, weight: Int, port: Int, target: String)? {
        let parts = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)

        if parts.count == 4,
           let priority = Int(parts[0]),
           let weight = Int(parts[1]),
           let port = Int(parts[2])
        {
            return (priority, weight, port, parts[3])
        }

        if parts.count == 3,
           let explicitPriority,
           let weight = Int(parts[0]),
           let port = Int(parts[1])
        {
            return (explicitPriority, weight, port, parts[2])
        }

        return nil
    }

    private func genericSRVRecordData(
        relativeName: String,
        destinationZoneName: String,
        content: String,
        priority: Int?
    ) -> RecordData? {
        guard let components = parseSRVComponents(content: content, explicitPriority: priority) else {
            return nil
        }

        let nameParts = relativeName.split(separator: ".", maxSplits: 2).map(String.init)
        guard nameParts.count >= 2 else { return nil }

        let domain = nameParts.count > 2 ? nameParts[2] : destinationZoneName

        return RecordData(
            service: nameParts[0],
            proto: nameParts[1],
            name: domain,
            priority: components.priority,
            weight: components.weight,
            port: components.port,
            target: components.target
        )
    }

    #if os(macOS)
    struct BatchReplaceResult {
        let totalRecords: Int
        let attemptedRecords: Int
        let successfulRecords: Int
        let failedRecords: Int
        let invalidRecords: Int
        let unchangedRecords: Int
        let errors: [BatchImportError]

        var isCompleteSuccess: Bool {
            failedRecords == 0 && invalidRecords == 0
        }
    }

    func replaceRecordsBatch(
        in zone: ProviderZone,
        preview: BulkReplacePreview,
        progressCallback: @escaping (Double) -> Void
    ) async -> BatchReplaceResult {
        let applicableItems = preview.validItems
        let environmentId = zone.environmentId
        let envServices = services(for: environmentId)

        guard !applicableItems.isEmpty else {
            return BatchReplaceResult(
                totalRecords: preview.items.count,
                attemptedRecords: 0,
                successfulRecords: 0,
                failedRecords: 0,
                invalidRecords: preview.invalidItems.count,
                unchangedRecords: preview.unchangedCount,
                errors: []
            )
        }

        let outcome = await executeRecordBatch(
            applicableItems,
            operationName: "Bulk replace record",
            recordName: \.updatedName,
            progress: { Double($0) / Double(applicableItems.count) },
            progressCallback: progressCallback
        ) { item in
            guard let request = item.updateRequest else { return }
            try await zone.provider.updateRecord(
                in: zone,
                record: item.record,
                edits: request,
                services: envServices
            )
        }

        await refreshAfterRecordBatch(in: zone)

        return BatchReplaceResult(
            totalRecords: preview.items.count,
            attemptedRecords: applicableItems.count,
            successfulRecords: outcome.successful.count,
            failedRecords: outcome.errors.count,
            invalidRecords: preview.invalidItems.count,
            unchangedRecords: preview.unchangedCount,
            errors: outcome.errors
        )
    }
    #endif

    func updateRecord(
        in zone: ProviderZone,
        record: ProviderRecord,
        edits: UpdateProviderRecordRequest
    ) async throws {
        let environmentId = zone.environmentId
        let envServices = services(for: environmentId)

        try await zone.provider.updateRecord(in: zone, record: record, edits: edits, services: envServices)

        cacheManager.invalidate(key: cacheManager.recordsKey(environmentId: environmentId, zoneId: zone.id))
        await refreshRecords(for: zone)
    }
}
