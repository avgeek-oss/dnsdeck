#if os(macOS)
import SwiftUI

struct CopyRecordsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    let preview: AppModel.RecordCopyPreview
    @Binding var isSubmitting: Bool

    @State private var isCopying = false
    @State private var currentRecordIndex = 0

    private var navigationTitleText: String {
        "Copy \(preview.selectedCount) Record\(preview.selectedCount == 1 ? "" : "s") to \(preview.destinationZone.name)"
    }

    private var showsSummaryDetails: Bool {
        !preview.skippedExistingRecords.isEmpty || preview.candidates.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if showsSummaryDetails {
                    summarySection
                }
                recordsSection

                if !preview.skippedExistingRecords.isEmpty {
                    Divider()
                    skippedSection
                }

                Spacer()
            }
            .padding(20)
            .frame(minWidth: 700, minHeight: 400)
            .navigationTitle(navigationTitleText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(preview.candidates.isEmpty ? "Close" : "Cancel", role: .cancel) {
                        guard !isCopying else { return }
                        dismiss()
                    }
                    .disabled(isCopying)
                    .keyboardShortcut(.cancelAction)
                }

                if !preview.candidates.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: copyRecords) {
                            if isCopying {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Copying... (\(currentRecordIndex)/\(preview.candidates.count))")
                                }
                            } else {
                                Text(
                                    "Copy \(preview.candidates.count) record\(preview.candidates.count == 1 ? "" : "s")"
                                )
                            }
                        }
                        .disabled(isCopying)
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !preview.skippedExistingRecords.isEmpty {
                Text(
                    "\(preview.skippedExistingRecords.count) record\(preview.skippedExistingRecords.count == 1 ? "" : "s") already exist in the destination and will be skipped."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if preview.candidates.isEmpty {
                Text("All selected records already exist in the destination zone.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Table(preview.recordsToCopy) {
                TableColumn("Type") { record in
                    TypeBadge(type: record.type)
                }
                .width(min: 60, ideal: 80, max: 100)

                TableColumn("Name") { record in
                    Text(record.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 150, ideal: 220)

                TableColumn("Content") { record in
                    Text(record.content)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 220, ideal: 320)

                TableColumn("TTL") { record in
                    Text(ttlText(record.ttl))
                }
                .width(min: 50, ideal: 60, max: 80)
            }
            .frame(height: 220)
        }
    }

    private var skippedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Already in destination")

            Table(preview.skippedExistingRecords) {
                TableColumn("Type") { record in
                    TypeBadge(type: record.type)
                }
                .width(min: 60, ideal: 80, max: 100)

                TableColumn("Name") { record in
                    Text(record.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 150, ideal: 220)

                TableColumn("Content") { record in
                    Text(record.content)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 220, ideal: 320)
            }
            .frame(height: 120)
        }
    }

    private func ttlText(_ ttl: Int?) -> String {
        guard let ttl else { return "—" }
        return ttl == 1 ? "Auto" : "\(ttl)s"
    }

    private func copyRecords() {
        Task {
            isCopying = true
            isSubmitting = true
            currentRecordIndex = 0

            defer {
                isCopying = false
                isSubmitting = false
            }

            await model.copyRecordsBatch(preview: preview) { progress in
                currentRecordIndex = Int(progress * Double(max(preview.candidates.count, 1)))
            }

            await MainActor.run {
                dismiss()
            }
        }
    }
}

#endif
