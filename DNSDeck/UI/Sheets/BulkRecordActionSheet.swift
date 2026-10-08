#if os(macOS)
import SwiftUI

struct BulkRecordActionSheet: View {
    enum Action {
        case delete
        case convert(sourceType: String, targetType: String)
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    let zone: ProviderZone
    let records: [ProviderRecord]
    let action: Action
    @Binding var isSubmitting: Bool

    @StateObject private var localErrorHandler = ErrorHandler()
    @State private var isRunning = false
    @State private var currentStep = 0
    @State private var showingResults = false
    @State private var errors: [(recordName: String, error: String)] = []

    private var navigationTitleText: String {
        switch action {
        case .delete:
            "Delete \(records.count) Record\(records.count == 1 ? "" : "s")"
        case let .convert(_, targetType):
            "Convert \(records.count) Record\(records.count == 1 ? "" : "s") to \(targetType)"
        }
    }

    private var verb: String {
        switch action {
        case .delete: "Delete"
        case .convert: "Convert"
        }
    }

    private var progressVerb: String {
        switch action {
        case .delete: "Deleting"
        case .convert: "Converting"
        }
    }

    private var isConversion: Bool {
        if case .convert = action { true } else { false }
    }

    private var totalSteps: Int {
        records.count * (isConversion ? 2 : 1)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                recordsPreview
                Spacer()
            }
            .padding(20)
            .frame(minWidth: 600, minHeight: 400)
            .navigationTitle(navigationTitleText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        guard !isRunning else { return }
                        dismiss()
                    }
                    .disabled(isRunning)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("record.bulkAction.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: performAction) {
                        if isRunning {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("\(progressVerb)... (\(currentStep)/\(totalSteps))")
                            }
                        } else {
                            Text("\(verb) \(records.count) record\(records.count == 1 ? "" : "s")")
                        }
                    }
                    .disabled(isRunning)
                    .accessibilityIdentifier(
                        isConversion ? "record.bulkConvert.submit" : "record.bulkDelete.submit"
                    )
                }
            }
            .sheet(isPresented: $showingResults) {
                BatchResultsSheet(
                    title: "Failed Records",
                    summaryTitle: nil,
                    isSuccessful: errors.isEmpty,
                    metrics: [],
                    errors: errors,
                    exportFilename: isConversion ? "conversion-errors.csv" : "deletion-errors.csv",
                    errorHeading: "Failed Records"
                )
            }
            .onChange(of: showingResults) {
                if !showingResults, !errors.isEmpty { dismiss() }
            }
            .withErrorHandling(localErrorHandler)
        }
    }

    private var recordsPreview: some View {
        Table(records) {
            TableColumn("Type") { record in
                if case let .convert(sourceType, targetType) = action {
                    HStack(spacing: 4) {
                        TypeBadge(type: sourceType)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TypeBadge(type: targetType)
                    }
                } else {
                    TypeBadge(type: record.type)
                }
            }
            .width(min: isConversion ? 120 : 50, ideal: isConversion ? 160 : 80, max: isConversion ? 200 : 100)

            TableColumn("Name") { record in
                Text(record.name).lineLimit(1).truncationMode(.tail)
            }
            .width(min: 100, ideal: 180)

            TableColumn("Content") { record in
                HStack(alignment: .center, spacing: 6) {
                    if let proxied = record.proxied {
                        CloudflareProxyIcon(isProxied: proxied)
                    }
                    Text(record.content).lineLimit(1).truncationMode(.tail)
                }
            }
            .width(min: 150, ideal: 250)

            TableColumn("TTL") { record in
                Text(record.ttl.map { $0 == 1 ? "Auto" : "\($0)s" } ?? "—")
            }
            .width(min: 50, ideal: 60, max: 80)

            if !isConversion {
                TableColumn("Priority") { record in
                    if let priority = record.priority {
                        PriorityBadge(priority: priority)
                    }
                }
                .width(min: 50, ideal: 70, max: 100)
            }
        }
        .frame(height: 300)
    }

    private func performAction() {
        Task {
            isRunning = true
            isSubmitting = true
            currentStep = 0
            defer {
                isRunning = false
                isSubmitting = false
            }

            let outcome: (successful: Bool, errors: [(recordName: String, error: String)])
            switch action {
            case .delete:
                let result = await model.deleteRecordsBatch(
                    in: zone,
                    records: records,
                    progressCallback: progress
                )
                outcome = (
                    result.isCompleteSuccess,
                    result.errors.map { ($0.recordName, $0.error.localizedDescription) }
                )
            case let .convert(_, targetType):
                let result = await model.convertRecordsBatch(
                    in: zone,
                    records: records,
                    targetType: targetType,
                    progressCallback: progress
                )
                outcome = (result.isCompleteSuccess, result.allErrors)
            }
            errors = outcome.errors
            if outcome.successful { dismiss() } else { showingResults = true }
        }
    }

    private func progress(_ value: Double) {
        currentStep = Int(value * Double(totalSteps))
    }
}
#endif
