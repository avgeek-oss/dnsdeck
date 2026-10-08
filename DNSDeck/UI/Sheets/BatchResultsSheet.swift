#if os(macOS)
import os
import SwiftUI
import UniformTypeIdentifiers

struct BatchResultMetric {
    let text: String
    let color: Color

    static func count(_ count: Int, _ label: String, _ color: Color, includeZero: Bool = false) -> Self? {
        count == 0 && !includeZero ? nil : Self(text: "\(count) \(label)", color: color)
    }
}

struct BatchResultsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let summaryTitle: String?
    let isSuccessful: Bool
    let metrics: [BatchResultMetric]
    let errors: [(recordName: String, error: String)]
    let exportFilename: String
    var errorHeading = "Failed records"
    var minimumSize = CGSize(width: 700, height: 500)

    @State private var showingExporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let summaryTitle {
                    summary(title: summaryTitle)
                    if !errors.isEmpty { Divider() }
                }
                if !errors.isEmpty { errorsTable }
                Spacer()
            }
            .padding(20)
            .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !errors.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingExporter = true
                        } label: {
                            Label("Export Errors", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: CSVErrorDocument(errors: errors),
                contentType: .commaSeparatedText,
                defaultFilename: exportFilename
            ) { result in
                if case let .failure(error) = result {
                    Logger.ui.error("Error exporting \(title.lowercased()): \(error.localizedDescription)")
                }
            }
        }
    }

    private func summary(title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSuccessful ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isSuccessful ? .green : .orange)
                .font(.system(size: 24))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                HStack(spacing: 12) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                        Text(metric.text)
                            .font(.caption)
                            .foregroundColor(metric.color)
                    }
                }
            }
            Spacer()
        }
    }

    private var errorsTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(errorHeading)
            Table(errors.enumerated().map { BatchErrorRow(
                index: $0.offset + 1,
                recordName: $0.element.recordName,
                error: $0.element.error
            ) }) {
                TableColumn("#") { row in
                    Text("\(row.index)").foregroundColor(.secondary)
                }
                .width(min: 40, ideal: 50, max: 60)
                TableColumn("Record Name") { row in
                    Text(row.recordName)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("batch.error.\(row.index).recordName")
                        .accessibilityLabel(row.recordName)
                }
                .width(min: 150, ideal: 200)
                TableColumn("Error") { row in
                    Text(row.error)
                        .textSelection(.enabled)
                        .help(row.error)
                        .accessibilityIdentifier("batch.error.\(row.index).message")
                        .accessibilityLabel(row.error)
                }
                .width(min: 300, ideal: 400)
            }
            .frame(minHeight: 300)
        }
    }
}

private struct BatchErrorRow: Identifiable {
    let id = UUID()
    let index: Int
    let recordName: String
    let error: String
}

struct CSVErrorDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText]
    }

    let errors: [(recordName: String, error: String)]

    init(errors: [(recordName: String, error: String)]) {
        self.errors = errors
    }

    init(configuration _: ReadConfiguration) throws {
        errors = []
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let rows = errors.map { "\(Self.escape($0.recordName)),\(Self.escape($0.error))" }
        guard let data = (["Record Name,Error"] + rows).joined(separator: "\n").appending("\n").data(using: .utf8)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { [",", "\n", "\""].contains($0) }) else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
#endif
