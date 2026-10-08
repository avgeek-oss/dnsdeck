import AvgeekDesignSystem
import SwiftUI

struct RecordDetailView: View {
    let record: ProviderRecord
    let zone: ProviderZone
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @StateObject private var settings = SettingsManager.shared
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var isSubmitting = false

    private var helpers: RecordHelpers {
        RecordHelpers(zone: zone)
    }

    private var monochromeRecordName: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var recordContent: some View {
        List {
            Section("Basic Information") {
                DetailRow(label: "Type", value: record.type) {
                    TypeBadge(type: record.type)
                }

                DetailRow(label: "Name", value: record.name, copiesValue: true) {
                    helpers.recordNameDisplay(record, monochrome: monochromeRecordName)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                DetailRow(label: "Content", value: record.content, copiesValue: true) {
                    Text(helpers.recordContentText(for: record, masked: false))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                if let ttl = record.ttl {
                    DetailRow(label: "TTL", value: "\(ttl)") {
                        Text(helpers.ttlText(ttl))
                            .font(.body.monospaced())
                    }
                }

                if let priority = record.priority {
                    DetailRow(label: "Priority", value: "\(priority)") {
                        PriorityBadge(priority: priority)
                    }
                }

                if let proxied = record.proxied, proxied {
                    DetailRow(label: "Proxied", value: "Yes") {
                        CloudflareProxyIcon(isProxied: proxied)
                    }
                }
            }

            Section("Metadata") {
                if let createdOn = record.createdOn {
                    DetailRow(label: "Created", value: createdOn.formattedString(format: settings.dateTimeFormat)) {
                        Text(createdOn.formattedString(format: settings.dateTimeFormat))
                            .textSelection(.enabled)
                    }
                } else {
                    DetailRow(label: "Created", value: "—") {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }

                if let modifiedOn = record.modifiedOn {
                    DetailRow(
                        label: "Last Modified",
                        value: modifiedOn.formattedString(format: settings.dateTimeFormat)
                    ) {
                        Text(modifiedOn.formattedString(format: settings.dateTimeFormat))
                            .textSelection(.enabled)
                    }
                } else {
                    DetailRow(label: "Last Modified", value: "—") {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }

                DetailRow(label: "Record ID", value: record.recordData.id) {
                    Text(record.recordData.id)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                if let comment = record.comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comments")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        Text(comment.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }

            if record.type.uppercased() == "SRV" {
                Section("SRV Record Details") {
                    ForEach(Array(srvDetails.enumerated()), id: \.offset) { _, detail in
                        DetailRow(label: detail.label, value: detail.value) {
                            Text(detail.value).font(.body.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var srvDetails: [(label: LocalizedStringResource, value: String)] {
        if let data = record.recordData.decode(CFDNSRecord.self)?.data {
            return [
                ("Priority", String(data.priority ?? 0)),
                ("Weight", String(data.weight ?? 0)),
                ("Port", String(data.port ?? 0)),
                ("Target", data.target ?? ""),
            ]
        }
        let parts = record.content.components(separatedBy: " ")
        guard parts.count >= 4 else { return [] }
        return [("Priority", parts[0]), ("Weight", parts[1]), ("Port", parts[2]), ("Target", parts[3])]
    }

    var body: some View {
        Group {
            #if os(iOS)
            NavigationStack {
                recordContent
                    .navigationTitle("Record Details")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            shareButton
                            editButton
                            deleteButton
                        }
                    }
            }
            #else
            NavigationStack {
                recordContent
                    .navigationTitle("Record Details")
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            shareButton
                            editButton
                            deleteButton
                        }
                    }
            }
            #endif
        }
        .sheet(isPresented: $showEditSheet) {
            RecordFormSheet(zone: zone, record: record, isSubmitting: $isSubmitting)
                .environmentObject(model)
        }
        .alert(Constants.UIText.deleteRecord, isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    isSubmitting = true
                    await deleteRecord()
                    isSubmitting = false
                }
            }
            .disabled(isSubmitting)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This record will be deleted and cannot be reversed.")
        }
    }

    private func deleteRecord() async {
        await model.deleteRecords(in: zone, recordIds: [record.id])
        if model.errorHandler.currentError == nil {
            AvgeekFeedback.impact(.medium)
            dismiss()
        } else {
            AvgeekFeedback.error()
        }
    }

    private var editButton: some View {
        Button {
            showEditSheet = true
        } label: {
            Image(systemName: "pencil")
        }
        .disabled(isSubmitting)
    }

    private var shareButton: some View {
        ShareLink(item: shareText) {
            Image(systemName: "square.and.arrow.up")
        }
        .help("Share this record")
    }

    private var shareText: String {
        let name = helpers.recordNameText(for: record)
        let value = helpers.recordContentText(for: record)
        let ttl = record.ttl.map { helpers.ttlText($0) } ?? "—"
        return """
        \(record.type)\t\(name)\t\(value)
        TTL: \(ttl)
        """
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
        }
        .disabled(isSubmitting)
    }
}

struct DetailRow<Content: View>: View {
    let label: LocalizedStringResource
    let value: String
    var copiesValue = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                #if os(macOS)
                .frame(width: 100, alignment: .leading)
                #else
                .frame(width: 80, alignment: .leading)
                #endif

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contextMenu {
            if copiesValue {
                Button("Copy") {
                    #if os(iOS)
                    UIPasteboard.general.string = value
                    #else
                    NSPasteboard.general.setString(value, forType: .string)
                    #endif
                }
            }
        }
    }
}
