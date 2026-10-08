#if os(macOS)
import Foundation

struct BulkReplacePreview {
    let items: [BulkReplacePreviewItem]

    var changedItems: [BulkReplacePreviewItem] {
        items.filter(\.hasChanges)
    }

    var validItems: [BulkReplacePreviewItem] {
        items.filter(\.isReady)
    }

    var invalidItems: [BulkReplacePreviewItem] {
        items.filter(\.isInvalid)
    }

    var unchangedCount: Int {
        items.count - changedItems.count
    }
}

struct BulkReplacePreviewItem: Identifiable {
    enum Status {
        case unchanged
        case ready(UpdateProviderRecordRequest)
        case invalid(String)
    }

    let record: ProviderRecord
    let currentName: String
    let updatedName: String
    let currentValue: String
    let updatedValue: String
    let status: Status

    var id: String {
        record.id
    }

    var hasChanges: Bool {
        currentName != updatedName || currentValue != updatedValue
    }

    var isReady: Bool {
        if case .ready = status { true } else { false }
    }

    var isInvalid: Bool {
        if case .invalid = status { true } else { false }
    }

    var updateRequest: UpdateProviderRecordRequest? {
        if case let .ready(request) = status { request } else { nil }
    }

    var errorMessage: String? {
        if case let .invalid(message) = status { message } else { nil }
    }

    var statusText: String {
        switch status {
        case .unchanged: "Unchanged"
        case .ready: "Valid"
        case let .invalid(message): message
        }
    }
}

enum BulkReplaceEngine {
    static func preview(
        records: [ProviderRecord],
        zone: ProviderZone,
        find: String,
        replace: String
    ) -> BulkReplacePreview {
        BulkReplacePreview(items: records.map {
            previewItem(for: $0, zone: zone, find: find, replace: replace)
        })
    }

    private static func previewItem(
        for record: ProviderRecord,
        zone: ProviderZone,
        find: String,
        replace: String
    ) -> BulkReplacePreviewItem {
        let snapshot = record.recordData.snapshot
        let currentName = record.name.trimmed
        let currentValue = record.aliasTarget?.name ?? snapshot.values.joined(separator: " ")
        guard !find.isEmpty else {
            return item(record, currentName, currentName, currentValue, currentValue, .unchanged)
        }

        let updatedName = Self.replace(find, with: replace, in: currentName)
        let values = snapshot.aliasTarget == nil
            ? snapshot.values.map { Self.replace(find, with: replace, in: $0) }
            : []
        let alias = snapshot.aliasTarget.map { Self.replace(find, with: replace, in: $0.name) }
        let updatedValue = alias ?? values.joined(separator: " ")
        guard updatedName != currentName || updatedValue != currentValue else {
            return item(record, currentName, currentName, currentValue, currentValue, .unchanged)
        }

        if let error = DNSRecordValidator.validateRecordName(updatedName) {
            return invalid(record, currentName, updatedName, currentValue, updatedValue, error)
        }
        if let alias, let error = DNSRecordValidator.validateDomain(alias) {
            return invalid(record, currentName, updatedName, currentValue, updatedValue, error)
        }
        for value in values {
            if let error = DNSRecordValidator.validateRecordValue(type: snapshot.type, rawValue: value) {
                return invalid(record, currentName, updatedName, currentValue, updatedValue, error)
            }
        }

        let valueChanged = updatedValue != currentValue
        let request: UpdateProviderRecordRequest
        if record.provider == .cloudflare, ["SRV", "CAA"].contains(snapshot.type.uppercased()) {
            do {
                request = try cloudflareRequest(
                    type: snapshot.type,
                    zoneName: zone.name,
                    name: updatedName,
                    nameChanged: updatedName != currentName,
                    value: updatedValue
                )
            } catch {
                return invalid(
                    record,
                    currentName,
                    updatedName,
                    currentValue,
                    updatedValue,
                    error.localizedDescription
                )
            }
        } else {
            request = UpdateProviderRecordRequest(
                name: updatedName == currentName ? nil : updatedName,
                type: snapshot.type,
                content: valueChanged && values.count == 1 ? values[0] : nil,
                values: valueChanged && !values.isEmpty ? values : nil,
                aliasTarget: valueChanged ? alias : nil
            )
        }
        return item(record, currentName, updatedName, currentValue, updatedValue, .ready(request))
    }

    private static func cloudflareRequest(
        type: String,
        zoneName: String,
        name: String,
        nameChanged: Bool,
        value: String
    ) throws -> UpdateProviderRecordRequest {
        let data: RecordData? = switch type.uppercased() {
        case "SRV":
            UpdateProviderRecordRequest.cloudflareSRVData(
                zoneName: zoneName,
                name: name,
                content: value
            )
        case "CAA":
            UpdateProviderRecordRequest.cloudflareCAAData(content: value)
        default:
            nil
        }
        guard let data else {
            let format = type.uppercased() == "SRV"
                ? "priority weight port target"
                : "flags tag value"
            throw ProviderAPIError.invalidRecordContent(
                provider: .cloudflare,
                type: type,
                message: "expected \(format)"
            )
        }
        return UpdateProviderRecordRequest(
            name: nameChanged ? name : nil,
            type: type,
            recordData: data
        )
    }

    private static func replace(_ find: String, with replacement: String, in value: String) -> String {
        value.replacingOccurrences(of: find, with: replacement)
    }

    private static func invalid(
        _ record: ProviderRecord,
        _ currentName: String,
        _ updatedName: String,
        _ currentValue: String,
        _ updatedValue: String,
        _ error: String
    ) -> BulkReplacePreviewItem {
        item(record, currentName, updatedName, currentValue, updatedValue, .invalid(error))
    }

    private static func item(
        _ record: ProviderRecord,
        _ currentName: String,
        _ updatedName: String,
        _ currentValue: String,
        _ updatedValue: String,
        _ status: BulkReplacePreviewItem.Status
    ) -> BulkReplacePreviewItem {
        BulkReplacePreviewItem(
            record: record,
            currentName: currentName,
            updatedName: updatedName,
            currentValue: currentValue,
            updatedValue: updatedValue,
            status: status
        )
    }
}
#endif
