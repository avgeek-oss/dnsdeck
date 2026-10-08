#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

enum ImportFormat: String, CaseIterable {
    case csv = "CSV"
    case bind = "BIND Zone"
    case inline = "Inline"
}

private enum FileImportKind {
    case csv
    case bind
}

struct CSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    let zone: ProviderZone
    @Binding var isSubmitting: Bool

    @StateObject private var localErrorHandler = ErrorHandler()

    @State private var selectedFileURL: URL?
    @State private var parseResult: CSVParseResult?
    @State private var showingFileImporter = false
    @State private var activeFileImportKind: FileImportKind?
    @State private var importProgress = 0.0
    @State private var isImporting = false
    @State private var importedCount = 0
    @State private var failedCount = 0
    @State private var currentRecordIndex = 0
    @State private var totalRecordsToImport = 0
    @State private var showingProgressDetails = false
    @State private var bulkComment = ""
    @State private var importFormat: ImportFormat = .csv
    @State private var bindText = ""
    @StateObject private var debouncedBind = DebouncedSearch(debounceDelay: 0.3)
    @State private var inlineRecords: [InlineRecord] = []
    @State private var showingImportResults = false
    @State private var importErrors: [(recordName: String, error: String)] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                formatPickerSection

                switch importFormat {
                case .csv:
                    fileSelectionSection
                case .bind:
                    bindInputSection
                case .inline:
                    inlineEditorSection
                }

                if zone.provider == .cloudflare {
                    if importFormat == .inline {
                        if !inlineRecords.isEmpty {
                            Divider()
                            bulkCommentSection
                        }
                    } else if let parseResult, parseResult.records.count > 0, !parseResult.hasErrors {
                        Divider()
                        bulkCommentSection
                    }
                }
                if importFormat != .inline, let parseResult {
                    Divider()
                    previewSection(parseResult: parseResult)
                }
                Spacer()
            }
            .padding(20)
            .frame(minWidth: importFormat == .inline ? 700 : 600, minHeight: importFormat == .inline ? 500 : 400)
            .navigationTitle("Import Records")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        guard !isImporting else { return }
                        dismiss()
                    }
                    .accessibilityIdentifier("record.import.cancel")
                    .disabled(isImporting)
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        if importFormat == .inline {
                            importInlineRecords()
                        } else {
                            importRecords()
                        }
                    }) {
                        if isImporting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Importing... (\(currentRecordIndex)/\(totalRecordsToImport))")
                            }
                        } else if importFormat == .inline {
                            Text(
                                "Import \(inlineRecords.count) record\(inlineRecords.count == 1 ? "" : "s")"
                            )
                        } else if parseResult?.hasErrors ?? false {
                            Text("Import")
                        } else {
                            Text(
                                "Import \(parseResult?.records.count ?? 0) record\(parseResult?.records.count == 1 ? "" : "s")"
                            )
                        }
                    }
                    .accessibilityIdentifier("record.import.submit")
                    .disabled(!canImport || isImporting)
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showingImportResults) {
                BatchResultsSheet(
                    title: "Bulk import results",
                    summaryTitle: "Bulk import processed",
                    isSuccessful: failedCount == 0,
                    metrics: [
                        .count(importedCount, "successful", .green, includeZero: true),
                        .count(failedCount, "failed", .red),
                    ].compactMap(\.self),
                    errors: importErrors,
                    exportFilename: "import-errors.csv"
                )
            }
            .onChange(of: showingImportResults) {
                if !showingImportResults, failedCount > 0 {
                    dismiss()
                }
            }
            .withErrorHandling(localErrorHandler)
        }
    }

    private var fileSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if parseResult == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Required columns: type, name, value")
                    Text("• Optional columns: ttl, priority, proxied, comment")
                    Text("• Supported types: \(Constants.DNSRecordTypes.supportedTypes.joined(separator: ", "))")
                    if zone.provider == .route53 {
                        Text("• Route53: TTL defaults to 300 seconds if not specified")
                    }
                    if zone.provider == .cloudflare {
                        Text("• Cloudflare: To enable proxy, set 'proxied' to 'true'")
                    }
                }
                .foregroundColor(.secondary)
                Divider()
            }
            HStack {
                if let selectedFileURL {
                    Text("\"\(selectedFileURL.path)\"")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("record.import.file.selected")
                } else {
                    Text("No file selected")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Choose File...") {
                    activeFileImportKind = .csv
                    showingFileImporter = true
                }
                .accessibilityIdentifier("record.import.file.choose")
                .disabled(isImporting)
            }
        }
    }

    private var formatPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Import Source", selection: $importFormat) {
                ForEach(ImportFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isImporting)
            .onChange(of: importFormat) {
                // Reset state when switching formats
                parseResult = nil
                selectedFileURL = nil
                bindText = ""
                debouncedBind.clear()
                inlineRecords = []
            }
            .fixedSize()

            Divider()
        }
    }

    private var bindInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if parseResult == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste BIND zone records or load a zone file.")
                        .foregroundColor(.secondary)
                    Text("Format: name TTL IN type value")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            TextEditor(text: $bindText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .disabled(isImporting)
                .onChange(of: bindText) {
                    debouncedBind.searchText = bindText
                }
                .onChange(of: debouncedBind.debouncedSearchText) {
                    parseBINDText()
                }

            HStack {
                Spacer()
                Button("Load File...") {
                    activeFileImportKind = .bind
                    showingFileImporter = true
                }
                .disabled(isImporting)
            }
        }
    }

    private func previewSection(parseResult: CSVParseResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if parseResult.hasWarnings {
                    Label(
                        "\(parseResult.errors.filter { $0.severity == .warning }.count) warning\(parseResult.errors.filter { $0.severity == .warning }.count == 1 ? "" : "s") found",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundColor(.orange)
                }

                if !parseResult.isValid {
                    Label(
                        "\(parseResult.errors.filter { $0.severity == .error }.count) error\(parseResult.errors.filter { $0.severity == .error }.count == 1 ? "" : "s") found",
                        systemImage: "xmark.circle.fill"
                    )
                    .foregroundColor(.red)
                }
            }

            if !parseResult.errors.isEmpty {
                errorsList(errors: parseResult.errors)
            }

            if !parseResult.records.isEmpty, !parseResult.hasErrors {
                recordsPreview(records: parseResult.records)
            }
        }
    }

    private func errorsList(errors: [CSVParseError]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(errors) { error in
                    Text("Line \(error.line): \(error.message)")
                        .font(.caption)
                        .foregroundColor(error.severity == .error ? .red : .orange)
                }
            }
        }
        .frame(maxHeight: 100)
        .cornerRadius(6)
    }

    private func recordsPreview(records: [CSVRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Table(records) {
                TableColumn("Type") { record in
                    TypeBadge(type: record.type)
                }
                .width(min: 50, ideal: 80, max: 100)

                TableColumn("Name") { record in
                    Text(record.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 100, ideal: 150)

                TableColumn("Value") { record in
                    Text(record.value)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 150, ideal: 250)

                TableColumn("TTL") { record in
                    Text(record.ttl.map(String.init) ?? "—")
                }
                .width(min: 50, ideal: 60, max: 80)

                TableColumn("Priority") { record in
                    Text(record.priority.map(String.init) ?? "—")
                }
                .width(min: 50, ideal: 70, max: 100)
            }
            .frame(height: 250)
            .accessibilityIdentifier("record.import.preview")
        }
    }

    private var bulkCommentSection: some View {
        TextField("Add common comment for imported records", text: $bulkComment, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2 ... 4)
            .disabled(isImporting)
    }

    private var canImport: Bool {
        if importFormat == .inline {
            return !inlineRecords.isEmpty && !inlineRecords.contains(where: \.hasErrors)
        }
        guard let parseResult else { return false }
        return parseResult.isValid && !parseResult.records.isEmpty
    }

    private var allowedContentTypes: [UTType] {
        switch activeFileImportKind {
        case .csv:
            [.commaSeparatedText, .plainText]
        case .bind:
            [.plainText]
        case nil:
            [.data]
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        let importKind = activeFileImportKind
        showingFileImporter = false
        activeFileImportKind = nil

        switch importKind {
        case .csv:
            handleCSVFileSelection(result)
        case .bind:
            handleBindFileSelection(result)
        case nil:
            break
        }
    }

    private func handleCSVFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            selectedFileURL = url
            parseCSVFile(url)
        case let .failure(error):
            localErrorHandler.handle(error)
        }
    }

    private func parseCSVFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let result = try CSVParser.parse(from: url)
            parseResult = result

            if !result.isValid {
                if let firstError = result.errors.first(where: { $0.severity == .error }) {
                    localErrorHandler.handle(AppError.general(firstError.message))
                }
            }
        } catch {
            localErrorHandler.handle(error)
            parseResult = nil
        }
    }

    private func parseBINDText() {
        let text = debouncedBind.debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            parseResult = nil
            return
        }
        parseResult = BINDParser.parse(content: text, zoneName: zone.name)
    }

    private func handleBindFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                bindText = content
                // Parse immediately (don't wait for debounce)
                parseResult = BINDParser.parse(content: content, zoneName: zone.name)
            } catch {
                localErrorHandler.handle(error)
            }
        case let .failure(error):
            localErrorHandler.handle(error)
        }
    }

    private var inlineEditorSection: some View {
        InlineRecordEditor(
            records: $inlineRecords,
            zone: zone
        )
    }

    private func importInlineRecords() {
        for index in inlineRecords.indices {
            inlineRecords[index].runValidation()
        }
        guard !inlineRecords.contains(where: \.hasErrors) else { return }
        startImport(inlineRecords.map {
            $0.toCreateProviderRecordRequest(provider: zone.provider)
        })
    }

    private func importRecords() {
        guard let parseResult, parseResult.isValid else { return }
        startImport(parseResult.records.map { $0.toCreateProviderRecordRequest() })
    }

    private func startImport(_ records: [CreateProviderRecordRequest]) {
        Task {
            isImporting = true
            isSubmitting = true
            importProgress = 0.0
            importedCount = 0
            failedCount = 0
            totalRecordsToImport = records.count
            currentRecordIndex = 0

            defer {
                isImporting = false
                isSubmitting = false
            }

            let result = await model.createRecordsBatch(
                in: zone,
                records: records.map(applyingBulkComment)
            ) { progress in
                importProgress = progress
                currentRecordIndex = Int(progress * Double(totalRecordsToImport))
            }

            importedCount = result.successfulRecords
            failedCount = result.failedRecords

            await MainActor.run {
                if result.isCompleteSuccess {
                    dismiss()
                } else {
                    importErrors = result.errors.map { error in
                        (recordName: error.recordName, error: error.error.localizedDescription)
                    }
                    showingImportResults = true
                }
            }
        }
    }

    private func applyingBulkComment(to request: CreateProviderRecordRequest) -> CreateProviderRecordRequest {
        let bulkComment = bulkComment.trimmed
        guard zone.provider == .cloudflare, !bulkComment.isEmpty else { return request }
        let comment = request.comment.map { "\(bulkComment) | \($0)" } ?? bulkComment
        return CreateProviderRecordRequest(
            name: request.name,
            type: request.type,
            content: request.content,
            ttl: request.ttl,
            proxied: request.proxied,
            priority: request.priority,
            comment: comment,
            recordData: request.recordData
        )
    }
}

#endif
