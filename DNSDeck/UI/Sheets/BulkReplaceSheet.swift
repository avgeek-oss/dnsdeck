#if os(macOS)
import AvgeekDesignSystem
import AvgeekLocalizationCore
import AvgeekLocalizationUI
import SwiftUI

struct BulkReplaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @AppLocalized private var localize

    let zone: ProviderZone
    @Binding var isSubmitting: Bool

    @State private var findText = ""
    @State private var replaceText = ""
    @State private var isReplacing = false
    @State private var currentRecordIndex = 0
    @State private var showingResults = false
    @State private var result: AppModel.BatchReplaceResult?
    @State private var preview = BulkReplacePreview(items: [])

    private func updatePreview() {
        preview = BulkReplaceEngine.preview(records: model.records, zone: zone, find: findText, replace: replaceText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                inputSection
                previewTable
                Spacer()
            }
            .padding(20)
            .frame(minWidth: 920, minHeight: 560)
            .navigationTitle("Bulk Replace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        guard !isReplacing else { return }
                        dismiss()
                    }
                    .disabled(isReplacing)
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: applyChanges) {
                        if isReplacing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(
                                    "Replacing... (\(min(currentRecordIndex, max(preview.validItems.count, 1)))/\(max(preview.validItems.count, 1)))"
                                )
                            }
                        } else {
                            Text(
                                "Replace \(preview.validItems.count) record\(preview.validItems.count == 1 ? "" : "s")"
                            )
                        }
                    }
                    .disabled(
                        isReplacing ||
                            findText.isEmpty ||
                            preview.validItems.isEmpty ||
                            !preview.invalidItems.isEmpty
                    )
                    .accessibilityIdentifier("record.bulkReplace.submit")
                }
            }
            .sheet(isPresented: $showingResults) {
                if let result {
                    BatchResultsSheet(
                        title: "Bulk replace results",
                        summaryTitle: "Bulk replace processed",
                        isSuccessful: result.failedRecords == 0,
                        metrics: [
                            .count(result.successfulRecords, "successful", .green, includeZero: true),
                            .count(result.failedRecords, "failed", .red),
                            .count(result.invalidRecords, "skipped", .orange),
                            .count(result.unchangedRecords, "unchanged", .secondary),
                        ].compactMap(\.self),
                        errors: result.errors.map { ($0.recordName, $0.error.localizedDescription) },
                        exportFilename: "bulk-replace-errors.csv",
                        minimumSize: CGSize(width: 720, height: 520)
                    )
                }
            }
            .onChange(of: showingResults) {
                if !showingResults, result != nil {
                    dismiss()
                }
            }
            .onChange(of: findText) { updatePreview() }
            .onChange(of: replaceText) { updatePreview() }
            .onAppear { updatePreview() }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replace a literal substring across all loaded records in this zone.")
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Find")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    NativeTextField(placeholder: localize("Substring to find"), text: $findText)
                        .accessibilityIdentifier("record.bulkReplace.find")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Replace With")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    NativeTextField(placeholder: localize("Replacement text"), text: $replaceText)
                        .accessibilityIdentifier("record.bulkReplace.replacement")
                }
            }
        }
    }

    private var previewTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            if preview.changedItems.isEmpty {
                AvgeekEmptyStateView(
                    icon: "text.magnifyingglass",
                    title: "No changes to preview",
                    message: findText.isEmpty ?
                        "Enter a substring to preview replacements." :
                        "No records contain that substring."
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                Table(preview.changedItems) {
                    TableColumn("Status") { item in
                        Text(item.statusText)
                            .foregroundColor(item.isInvalid ? .red : item.isReady ? .green : .secondary)
                            .lineLimit(2)
                            .help(item.statusText)
                    }
                    .width(min: 180, ideal: 240)

                    TableColumn("Type") { item in
                        TypeBadge(type: item.record.type)
                    }
                    .width(min: 70, ideal: 90, max: 120)

                    TableColumn("Current Name") { item in
                        Text(item.currentName)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    .width(min: 180, ideal: 230)

                    TableColumn("New Name") { item in
                        Text(item.updatedName)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    .width(min: 180, ideal: 230)

                    TableColumn("Current Value") { item in
                        Text(item.currentValue)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    .width(min: 180, ideal: 230)

                    TableColumn("New Value") { item in
                        Text(item.updatedValue)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    .width(min: 180, ideal: 230)
                }
                .frame(minHeight: 340)
            }
        }
    }

    private func applyChanges() {
        Task {
            isReplacing = true
            isSubmitting = true
            currentRecordIndex = 0

            defer {
                isReplacing = false
                isSubmitting = false
            }

            let replaceResult = await model.replaceRecordsBatch(in: zone, preview: preview) { progress in
                currentRecordIndex = Int(progress * Double(max(preview.validItems.count, 1)))
            }

            result = replaceResult
            await MainActor.run {
                // On success, dismiss silently. Only surface the results sheet
                // when there are failures to review.
                if replaceResult.failedRecords == 0, replaceResult.invalidRecords == 0 {
                    dismiss()
                } else {
                    showingResults = true
                }
            }
        }
    }
}

#endif
