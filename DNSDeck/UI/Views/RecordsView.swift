

import AvgeekDesignSystem
import os
import SwiftUI
#if os(macOS)
import UniformTypeIdentifiers
#endif

struct RecordsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var lockController: AppLockController
    @StateObject private var settings = SettingsManager.shared
    let zone: ProviderZone

    @State private var showAdd = false
    @State private var isSubmitting = false
    @StateObject private var debouncedSearch = DebouncedSearch()
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteIDs: [String] = []
    @State private var selectedRecord: ProviderRecord?
    @State private var showZoneInfo = false
    @State private var filteredRecords: [ProviderRecord] = []

    #if os(macOS)
    @State private var selectedRecordIDs: Set<String> = []
    @State private var showCSVImport = false
    @State private var showCSVExport = false
    @State private var showBulkDelete = false
    @State private var recordsToDelete: [ProviderRecord] = []
    @State private var showBulkConvert = false
    @State private var recordsToConvert: [ProviderRecord] = []
    @State private var conversionTargetType = ""
    @State private var showBulkReplace = false
    @State private var sortOrder: [KeyPathComparator<ProviderRecord>] = []
    @State private var availableDestinationZones: [ProviderZone] = []
    @State private var isLoadingDestinationZones = false
    @State private var isPreparingCopy = false
    @State private var copyPreview: AppModel.RecordCopyPreview?
    @State private var destinationZoneLoadID = UUID()
    #endif

    private var helpers: RecordHelpers {
        RecordHelpers(zone: zone)
    }

    private func updateFilteredRecords() {
        filteredRecords = SearchFilter.filterRecords(model.records, searchText: debouncedSearch.debouncedSearchText)
        #if os(macOS)
        if !sortOrder.isEmpty {
            filteredRecords.sort(using: sortOrder)
        }
        #endif
    }

    private var hasAnyPriorityRecords: Bool {
        filteredRecords.contains { $0.priority != nil }
    }

    private var inlineLoadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(Constants.UIText.loadingRecords)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noRecordsView: some View {
        AvgeekEmptyStateView(
            icon: "doc.text.magnifyingglass",
            title: debouncedSearch.debouncedSearchText.isEmpty ? "No Records Found" : "No Matching Records",
            message: debouncedSearch.debouncedSearchText.isEmpty ?
                "This zone doesn't have any DNS records yet." :
                "No records match your search criteria.",
            buttonTitle: debouncedSearch.debouncedSearchText.isEmpty ? "Add Record" : nil,
            buttonIcon: debouncedSearch.debouncedSearchText.isEmpty ? "plus" : nil,
            onButtonTap: debouncedSearch.debouncedSearchText.isEmpty ? { showAdd = true } : nil
        )
        .accessibilityIdentifier("record.search.empty")
        .disabled(isSubmitting)
    }

    private var recordsTable: some View {
        #if os(macOS)
        Table(filteredRecords, selection: $selectedRecordIDs, sortOrder: $sortOrder) {
            TableColumn("Type", value: \.sortType) { (record: ProviderRecord) in
                TypeBadge(type: record.type)
                    .accessibilityIdentifier("record.type.\(record.name)")
            }
            .width(min: 80, ideal: 100, max: 120)

            TableColumn("Name", value: \.sortName) { (record: ProviderRecord) in
                HStack(alignment: .center, spacing: 6) {
                    BadgesStack(record: record, helpers: helpers)
                    helpers.recordNameDisplay(record)
                        .textSelection(.enabled)
                        .help(record.name)
                        .accessibilityLabel(record.name)
                        .accessibilityIdentifier("record.name.\(record.name)")
                }
            }
            .width(min: Constants.UI.tableColumnMinWidth, ideal: 200, max: .infinity)

            TableColumn("Content", value: \.sortContent) { (record: ProviderRecord) in
                HStack(alignment: .center, spacing: 6) {
                    if let proxied = record.proxied {
                        CloudflareProxyIcon(isProxied: proxied)
                    }
                    let content = helpers.recordContentText(for: record, masked: settings.maskContentColumn)
                    Text(content)
                        .textSelection(.enabled)
                        .font(helpers.isIPv4Address(content) ? .body.monospaced() : .body)
                        .accessibilityLabel(content)
                        .accessibilityIdentifier("record.content.\(record.name)")
                        #if os(macOS)
                        .lineLimit(settings.wrapTextContent ? nil : 1)
                        .modifier(TruncationModifier(wrapped: settings.wrapTextContent))
                        #endif
                        .help(settings.maskContentColumn ? "Right-click to copy actual content" : content)
                        .contextMenu {
                            if settings.maskContentColumn {
                                Button("Copy Actual Content") {
                                    copyToClipboard(helpers.recordContentText(for: record))
                                }
                            }
                        }
                }
            }
            .width(min: Constants.UI.contentColumnMinWidth, ideal: 300, max: .infinity)

            if settings.showTTLColumn {
                TableColumn("TTL", value: \.sortTTL) { (record: ProviderRecord) in
                    Text(helpers.ttlText(record.ttl))
                        .foregroundColor(record.ttl == 1 ? .secondary : .primary)
                        .accessibilityIdentifier("record.ttl.\(record.name)")
                }
                .width(min: 60, ideal: 80, max: 100)
            }

            if hasAnyPriorityRecords {
                TableColumn("Priority", value: \.sortPriority) { (record: ProviderRecord) in
                    if let priority = record.priority {
                        PriorityBadge(priority: priority)
                    }
                }
                .width(min: 60, ideal: 80, max: 80)
            }

            if settings.showCommentColumn, zone.provider == .cloudflare {
                TableColumn("Comments", value: \.sortComment) { (record: ProviderRecord) in
                    if let comment = record.comment, !comment.isEmpty {
                        Text(comment)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .help(comment)
                            .accessibilityIdentifier("record.comment.\(record.name)")
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("record.comment.\(record.name)")
                    }
                }
                .width(min: 160, ideal: 160, max: 200)
            }

            TableColumn("Created", value: \.sortCreatedOn) { (record: ProviderRecord) in
                if let createdOn = record.createdOn {
                    Text(createdOn.formattedString(format: settings.dateTimeFormat))
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("record.created.\(record.name)")
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 160, ideal: 160, max: 200)

            TableColumn("Last Modified", value: \.sortModifiedOn) { (record: ProviderRecord) in
                if let modifiedOn = record.modifiedOn {
                    Text(modifiedOn.formattedString(format: settings.dateTimeFormat))
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 160, ideal: 160, max: 200)
        }
        .contextMenu(forSelectionType: ProviderRecord.ID.self) { items in
            if items.count == 1, let recordId = items.first,
               let record = model.records.first(where: { $0.id == recordId })
            {
                Button(Constants.UIText.copyRecordName) {
                    copyToClipboard(helpers.recordNameText(for: record))
                }
                .accessibilityIdentifier("record.context.copyName")
                .disabled(isSubmitting)
                Button(Constants.UIText.copyRecordValue) {
                    copyToClipboard(helpers.recordContentText(for: record))
                }
                .accessibilityIdentifier("record.context.copyValue")
                .disabled(isSubmitting)

                Divider()

                Button("Edit") {
                    selectedRecord = record
                }
                .accessibilityIdentifier("record.context.edit")
                .disabled(isSubmitting || !record.isEditable)

                let targets = RecordConversionMap.targets(for: record.type)
                if !targets.isEmpty {
                    Menu("Convert to...") {
                        ForEach(targets, id: \.self) { target in
                            Button(target) {
                                recordsToConvert = [record]
                                conversionTargetType = target
                                showBulkConvert = true
                            }
                        }
                    }

                    Divider()
                }

                Divider()

                copyToDestinationMenu(records: [record])

                Divider()

                Button("Delete", role: .destructive) {
                    pendingDeleteIDs = [recordId]
                    showDeleteConfirmation = true
                }
                .accessibilityIdentifier("record.context.delete")
                .disabled(isSubmitting)
            } else if items.count > 1 {
                let selectedRecords = model.records.filter { items.contains($0.id) }
                let types = Set(selectedRecords.map(\.type))

                if types.count == 1, let sourceType = types.first {
                    let targets = RecordConversionMap.targets(for: sourceType)
                    if !targets.isEmpty {
                        Menu("Convert to...") {
                            ForEach(targets, id: \.self) { target in
                                Button(target) {
                                    recordsToConvert = selectedRecords
                                    conversionTargetType = target
                                    showBulkConvert = true
                                }
                            }
                        }

                        Divider()
                    }
                }

                copyToDestinationMenu(records: selectedRecords)

                Divider()

                Button("Bulk Replace") {
                    showBulkReplace = true
                }
                .accessibilityIdentifier("record.context.bulkReplace")
                .disabled(isSubmitting || model.records.isEmpty)

                Divider()

                Button("Delete \(items.count) Records", role: .destructive) {
                    recordsToDelete = selectedRecords
                    showBulkDelete = true
                }
                .accessibilityIdentifier("record.context.bulkDelete")
                .disabled(isSubmitting)
            }
        }
        #else
        recordsList
        #endif
    }

    #if os(iOS)
    private var recordsList: some View {
        List(filteredRecords) { record in
            NavigationLink(destination: RecordDetailView(record: record, zone: zone)) {
                RecordRowView(record: record, zone: zone)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", role: .none) {
                    pendingDeleteIDs = [record.id]
                    showDeleteConfirmation = true
                }
                .disabled(isSubmitting)
                .tint(.red)

                Button("Edit") {
                    selectedRecord = record
                }
                .disabled(isSubmitting || !record.isEditable)
                .tint(.blue)
            }
            .contextMenu {
                Button(Constants.UIText.copyRecordName) {
                    copyToClipboard(helpers.recordNameText(for: record))
                }
                Button(Constants.UIText.copyRecordValue) {
                    copyToClipboard(helpers.recordContentText(for: record))
                }

                Divider()

                ShareLink(item: shareText(for: record)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Divider()

                Button("Edit") {
                    selectedRecord = record
                }
                .disabled(isSubmitting || !record.isEditable)

                Divider()

                Button("Delete", role: .destructive) {
                    pendingDeleteIDs = [record.id]
                    showDeleteConfirmation = true
                }
                .disabled(isSubmitting)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await model.refreshRecords(for: zone, forceRefresh: true)
        }
    }
    #endif

    @ViewBuilder
    private var platformContent: some View {
        #if os(macOS)
        HSplitView {
            VStack(spacing: 0) {
                if filteredRecords.isEmpty, !model.isLoading {
                    noRecordsView
                } else {
                    recordsTable
                        .loadingOverlay(text: Constants.UIText.loadingRecords, isVisible: model.isLoading)
                }
            }
            .frame(minWidth: 400)

            if showZoneInfo {
                ZoneInfoView(zone: zone)
                    .frame(minWidth: 350, maxWidth: 450)
            }
        }
        .searchable(text: $debouncedSearch.searchText, placement: .toolbar, prompt: "Search records...")
        .navigationTitle(zone.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !selectedRecordIDs.isEmpty {
                    if selectedRecordIDs.count == 1,
                       let recordId = selectedRecordIDs.first,
                       let record = model.records.first(where: { $0.id == recordId })
                    {
                        Button {
                            selectedRecord = record
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .accessibilityIdentifier("record.edit")
                        .disabled(isSubmitting || !record.isEditable)
                    }

                    Button {
                        if selectedRecordIDs.count == 1 {
                            pendingDeleteIDs = Array(selectedRecordIDs)
                            showDeleteConfirmation = true
                        } else {
                            let records = model.records.filter { selectedRecordIDs.contains($0.id) }
                            recordsToDelete = records
                            showBulkDelete = true
                        }
                    } label: {
                        Label(
                            "Delete \(selectedRecordIDs.count) record\(selectedRecordIDs.count == 1 ? "" : "s")",
                            systemImage: "trash"
                        )
                    }
                    .accessibilityIdentifier("record.delete")
                    .disabled(isSubmitting)
                }

                Button {
                    showCSVImport = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("record.import")
                .disabled(isSubmitting)

                Button {
                    showCSVExport = true
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("record.export")
                .disabled(isSubmitting || filteredRecords.isEmpty)

                Button {
                    showBulkReplace = true
                } label: {
                    Label("Bulk Replace", systemImage: "text.magnifyingglass")
                }
                .accessibilityIdentifier("record.bulkReplace")
                .disabled(isSubmitting || model.records.isEmpty)

                Button {
                    showAdd = true
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(Constants.UIText.addRecord, systemImage: "plus")
                    }
                }
                .accessibilityIdentifier("record.add")
                .disabled(isSubmitting)

                Button {
                    showZoneInfo.toggle()
                } label: {
                    Label("Zone Info", systemImage: "info.circle")
                }
                .accessibilityIdentifier("record.zoneInfo")
                .help("Show zone information")

                Button {
                    Task { await model.refreshRecords(for: zone, forceRefresh: true) }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .accessibilityIdentifier("record.refresh")
                    .help("Force refresh records")
            }
        }
        .sheet(isPresented: $showCSVImport) {
            CSVImportSheet(zone: zone, isSubmitting: $isSubmitting)
                .environmentObject(model)
        }
        .fileExporter(
            isPresented: $showCSVExport,
            document: CSVExportDocument(records: filteredRecords),
            contentType: .commaSeparatedText,
            defaultFilename: "\(zone.name.replacingOccurrences(of: ".", with: "-"))-records.csv"
        ) { result in
            switch result {
            case .success:
                break
            case let .failure(error):
                Logger.ui.error("Error exporting CSV: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $showBulkDelete) {
            BulkRecordActionSheet(
                zone: zone,
                records: recordsToDelete,
                action: .delete,
                isSubmitting: $isSubmitting
            )
            .environmentObject(model)
        }
        .sheet(isPresented: $showBulkConvert) {
            if !recordsToConvert.isEmpty, let sourceType = recordsToConvert.first?.type {
                BulkRecordActionSheet(
                    zone: zone,
                    records: recordsToConvert,
                    action: .convert(sourceType: sourceType, targetType: conversionTargetType),
                    isSubmitting: $isSubmitting
                )
                .environmentObject(model)
            }
        }
        .sheet(isPresented: $showBulkReplace) {
            BulkReplaceSheet(zone: zone, isSubmitting: $isSubmitting)
                .environmentObject(model)
        }
        .sheet(item: $copyPreview) { preview in
            CopyRecordsSheet(preview: preview, isSubmitting: $isSubmitting)
                .environmentObject(model)
        }
        .onChange(of: sortOrder) {
            updateFilteredRecords()
        }
        .onChange(of: model.zones) {
            Task {
                await loadAvailableDestinationZones()
            }
        }
        .onChange(of: showBulkDelete) {
            if !showBulkDelete {
                selectedRecordIDs.removeAll()
            }
        }
        .onChange(of: showBulkConvert) {
            if !showBulkConvert {
                selectedRecordIDs.removeAll()
            }
        }
        .onChange(of: showBulkReplace) {
            if !showBulkReplace {
                selectedRecordIDs.removeAll()
            }
        }
        .modifier(RecordKeyboardShortcutsModifier(
            filteredRecords: filteredRecords,
            selectedRecordIDs: $selectedRecordIDs,
            selectedRecord: $selectedRecord,
            recordsToDelete: $recordsToDelete,
            showBulkDelete: $showBulkDelete,
            showCSVImport: $showCSVImport,
            showCSVExport: $showCSVExport,
            isSubmitting: isSubmitting,
            isLocked: lockController.isLocked,
            model: model
        ))
        #else
        NavigationStack {
            VStack(spacing: 0) {
                if filteredRecords.isEmpty {
                    if model.isLoading {
                        inlineLoadingView
                    } else {
                        noRecordsView
                    }
                } else {
                    recordsTable
                }
            }
            .navigationDestination(isPresented: $showZoneInfo) {
                ZoneInfoView(zone: zone)
                    .navigationTitle("Zone Info")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .searchable(
                text: $debouncedSearch.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search records..."
            )
            .navigationTitle(zone.name)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        showAdd = true
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(Constants.UIText.addRecord, systemImage: "plus")
                        }
                    }
                    .disabled(isSubmitting)

                    Button {
                        showZoneInfo = true
                    } label: {
                        Label("Zone Info", systemImage: "info.circle")
                    }
                }
            }
        }
        #endif
    }

    var body: some View {
        platformContent
            .sheet(isPresented: $showAdd) {
                RecordFormSheet(zone: zone, record: nil, isSubmitting: $isSubmitting)
                    .environmentObject(model)
                    .frame(width: editorSheetWidth)
            }
            .sheet(item: $selectedRecord) { record in
                RecordFormSheet(zone: zone, record: record, isSubmitting: $isSubmitting)
                    .environmentObject(model)
                    .frame(width: editorSheetWidth)
            }
            .alert(Constants.UIText.deleteRecords, isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    confirmDelete()
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteIDs = []
                }
            } message: {
                let count = pendingDeleteIDs.count
                Text("\(count) record\(count == 1 ? "" : "s") will be deleted and cannot be reversed.")
            }
            .onChange(of: model.records) {
                recordsDidChange()
            }
            .onChange(of: debouncedSearch.debouncedSearchText) {
                updateFilteredRecords()
            }
            .onChange(of: debouncedSearch.searchText) { _, _ in
                lockController.registerUserActivity()
            }
            .task(id: zone.id) {
                updateFilteredRecords()
                #if os(macOS)
                await loadAvailableDestinationZones()
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .addRecord)) { notification in
                guard notificationTargetsCurrentWindow(notification) else { return }
                guard !lockController.isLocked else { return }
                Task { @MainActor in
                    if model.selectedZone?.id == zone.id {
                        showAdd = true
                    }
                }
            }
    }

    private var editorSheetWidth: CGFloat? {
        #if os(macOS)
        520
        #else
        nil
        #endif
    }

    private func confirmDelete() {
        let ids = pendingDeleteIDs
        pendingDeleteIDs = []
        #if os(macOS)
        selectedRecordIDs.removeAll()
        #endif
        Task {
            await deleteRecordsWithErrorHandling(ids: ids)
        }
    }

    private func recordsDidChange() {
        #if os(macOS)
        selectedRecordIDs.removeAll()
        recordsToDelete.removeAll()
        recordsToConvert.removeAll()
        #endif
        updateFilteredRecords()
    }

    private func deleteRecordsWithErrorHandling(ids: [String]) async {
        await model.deleteRecords(in: zone, recordIds: ids)
        if model.errorHandler.currentError == nil {
            AvgeekFeedback.impact(.medium)
        } else {
            AvgeekFeedback.error()
        }
    }

    private func notificationTargetsCurrentWindow(_ notification: Notification) -> Bool {
        guard let targetModel = notification.object as? AppModel else {
            return true
        }
        return targetModel === model
    }

    #if os(macOS)
    private func copyToDestinationMenu(records: [ProviderRecord]) -> some View {
        Menu("Copy to...") {
            if isLoadingDestinationZones {
                Button("Loading zones...") {}
                    .disabled(true)
            } else if availableDestinationZones.isEmpty {
                Button("No other zones available") {}
                    .disabled(true)
            } else {
                ForEach(availableDestinationZones) { destinationZone in
                    Button(destinationZoneMenuTitle(destinationZone)) {
                        prepareCopyPreview(records: records, destinationZone: destinationZone)
                    }
                }
            }
        }
        .disabled(records.isEmpty || isSubmitting || isPreparingCopy)
    }

    private func prepareCopyPreview(records: [ProviderRecord], destinationZone: ProviderZone) {
        Task {
            isPreparingCopy = true
            defer { isPreparingCopy = false }

            copyPreview = await model.prepareRecordCopyPreview(
                from: zone,
                records: records,
                to: destinationZone
            )
        }
    }

    private func loadAvailableDestinationZones() async {
        let loadID = UUID()
        destinationZoneLoadID = loadID
        availableDestinationZones = []
        isLoadingDestinationZones = true

        let sourceZone = zone
        let destinationZones = await model.availableDestinationZones(excluding: sourceZone)

        guard !Task.isCancelled, destinationZoneLoadID == loadID, zone.id == sourceZone.id else {
            return
        }

        availableDestinationZones = destinationZones
        isLoadingDestinationZones = false
    }

    private func destinationZoneMenuTitle(_ destinationZone: ProviderZone) -> String {
        "\(destinationZone.name) — \(destinationZone.provider.displayName)"
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    #endif

    #if os(iOS)
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }
    #endif

    /// Builds a shareable plain-text representation of a record.
    private func shareText(for record: ProviderRecord) -> String {
        let helpers = RecordHelpers(zone: zone)
        let name = helpers.recordNameText(for: record)
        let value = helpers.recordContentText(for: record)
        let ttl = record.ttl.map { helpers.ttlText($0) } ?? "—"
        return """
        \(record.type)\t\(name)\t\(value)
        TTL: \(ttl)
        """
    }
}

#if os(macOS)
private extension ProviderRecord {
    var sortType: String {
        recordData.type.uppercased()
    }

    var sortName: String {
        recordData.name.lowercased()
    }

    var sortContent: String {
        recordData.content.lowercased()
    }

    var sortTTL: Int {
        recordData.ttl ?? Int.min
    }

    var sortPriority: Int {
        recordData.priority ?? Int.min
    }

    var sortComment: String {
        (recordData.comment ?? "").lowercased()
    }

    var sortCreatedOn: Date {
        recordData.createdOn ?? .distantPast
    }

    var sortModifiedOn: Date {
        recordData.modifiedOn ?? .distantPast
    }
}
#endif

// MARK: - Keyboard Shortcuts Modifier (macOS)

#if os(macOS)
private struct RecordKeyboardShortcutsModifier: ViewModifier {
    let filteredRecords: [ProviderRecord]
    @Binding var selectedRecordIDs: Set<String>
    @Binding var selectedRecord: ProviderRecord?
    @Binding var recordsToDelete: [ProviderRecord]
    @Binding var showBulkDelete: Bool
    @Binding var showCSVImport: Bool
    @Binding var showCSVExport: Bool
    let isSubmitting: Bool
    let isLocked: Bool
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .onKeyPress(.escape) {
                selectedRecordIDs.removeAll()
                return .handled
            }
            .onKeyPress(.delete) {
                guard !isLocked, !selectedRecordIDs.isEmpty else { return .ignored }
                let records = model.records.filter { selectedRecordIDs.contains($0.id) }
                recordsToDelete = records
                showBulkDelete = true
                return .handled
            }
            .onKeyPress(keys: ["a"]) { press in
                guard press.modifiers == .command, !filteredRecords.isEmpty else { return .ignored }
                selectedRecordIDs = Set(filteredRecords.map(\.id))
                return .handled
            }
            .onKeyPress(keys: ["e"]) { press in
                // Cmd+E: Edit selected record
                if press.modifiers == .command {
                    guard !isLocked,
                          selectedRecordIDs.count == 1,
                          let recordId = selectedRecordIDs.first,
                          let record = model.records.first(where: { $0.id == recordId }),
                          record.isEditable
                    else { return .ignored }
                    selectedRecord = record
                    return .handled
                }
                // Cmd+Shift+E: Export CSV
                if press.modifiers == [.command, .shift] {
                    guard !isLocked, !isSubmitting, !filteredRecords.isEmpty else { return .ignored }
                    showCSVExport = true
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(keys: ["i"]) { press in
                guard press.modifiers == [.command, .shift], !isLocked, !isSubmitting else { return .ignored }
                showCSVImport = true
                return .handled
            }
    }
}

#endif

// MARK: - Record Validation Functions (Shared)

struct RecordHelpers {
    let zone: ProviderZone

    func isApexRecord(_ record: ProviderRecord) -> Bool {
        record.name.isEmpty ||
            record.name == "@" ||
            record.name == "." ||
            record.name == zone.name ||
            record.name == "\(zone.name)." ||
            record.name == ".\(zone.name)" ||
            record.name == ".\(zone.name)."
    }

    func isWildcardRecord(_ record: ProviderRecord) -> Bool {
        record.name == "*" || record.name.hasPrefix("*")
    }

    fileprivate func badges(for record: ProviderRecord) -> [RecordBadge] {
        RecordBadge.allCases.filter { $0.applies(to: record, helpers: self) }
    }

    func isIPv4Address(_ text: String) -> Bool {
        let ipv4Regex = #"^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#
        return text.range(of: ipv4Regex, options: .regularExpression) != nil
    }

    func recordNameText(for record: ProviderRecord) -> String {
        record.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func recordContentText(for record: ProviderRecord, masked: Bool = false) -> String {
        let content: String
        content = record.content

        if masked, !content.isEmpty {
            return String(repeating: "•", count: min(content.count, 20))
        }

        return content
    }

    func recordContentText(record: ProviderRecord) -> String {
        recordContentText(for: record, masked: false)
    }

    func ttlText(_ ttl: Int?) -> String {
        guard let ttl else { return "—" }
        return ttl == 1 ? "Auto" : "\(ttl)s"
    }

    func recordNameDisplay(_ record: ProviderRecord, monochrome: Bool = false) -> Text {
        let dimmed: Color = .primary.opacity(0.5)

        /*
         * Apex Domains
         */
        if isApexRecord(record) {
            if
                record.name.isEmpty ||
                record.name == "@" ||
                record.name == "." ||
                record.name == zone.name ||
                record.name == "\(zone.name)."
            {
                return Text(zone.name).foregroundColor(monochrome ? .primary : dimmed)
            }

            return Text(record.name).foregroundColor(monochrome ? .primary : dimmed)
        }

        /*
         * Wildcard Domains
         */
        if isWildcardRecord(record) {
            if record.name.count > 1, record.name.hasPrefix("*") {
                if monochrome { return Text(record.name) }
                let rest = String(record.name.dropFirst(1))
                return Text("*") + Text(rest).foregroundColor(.primary.opacity(0.4))
            }

            return Text("*").foregroundColor(.primary)
        }

        /*
         * Subdomains & FQDNs
         */
        let zoneSuffix = ".\(zone.name)"
        let zoneSuffixDot = ".\(zone.name)."
        if record.name.hasSuffix(zoneSuffix) || record.name.hasSuffix(zoneSuffixDot) {
            let activeSuffix = record.name.hasSuffix(zoneSuffixDot) ? zoneSuffixDot : zoneSuffix
            let primaryPart = String(record.name.dropLast(activeSuffix.count))
            if monochrome { return Text(record.name) }
            return Text("\(primaryPart)\(Text(activeSuffix).foregroundColor(dimmed))")
        }

        if record.name.contains(".") {
            let parts = record.name.split(separator: ".", maxSplits: 1)
            if parts.count == 2 {
                if monochrome { return Text(record.name) }
                return Text("\(parts[0])\(Text(".\(parts[1])").foregroundColor(dimmed))")
            }

            return Text(record.name).foregroundColor(monochrome ? .primary : dimmed)
        }

        return Text(record.name)
    }
}

// MARK: - Shared Components

private enum RecordBadge: String, CaseIterable, Identifiable {
    case apex
    case wildcard
    case spf
    case dkim
    case dmarc
    case tlsrpt
    case sts
    case bimi

    var id: Self {
        self
    }

    var view: BadgeView {
        switch self {
        case .apex: .apex
        case .wildcard: .wildcard
        case .spf: .spf
        case .dkim: .dkim
        case .dmarc: .dmarc
        case .tlsrpt: .tlsrpt
        case .sts: .sts
        case .bimi: .bimi
        }
    }

    func applies(to record: ProviderRecord, helpers: RecordHelpers) -> Bool {
        switch self {
        case .apex: helpers.isApexRecord(record)
        case .wildcard: helpers.isWildcardRecord(record)
        case .spf: matchesTXT(record, content: "V=SPF", names: "_SPF")
        case .dkim: matchesTXT(record, content: "V=DKIM", names: "_DOMAINKEY", "_DKIM")
        case .dmarc: matchesTXT(record, content: "V=DMARC", names: "_DMARC")
        case .tlsrpt: matchesTXT(record, content: "V=TLSRPT", names: "_TLSRPT")
        case .sts: matchesTXT(record, content: "V=STS", names: "_STS")
        case .bimi: matchesTXT(record, content: "V=BIMI", names: "_BIMI")
        }
    }

    private func matchesTXT(_ record: ProviderRecord, content: String, names: String...) -> Bool {
        guard record.type.uppercased() == "TXT" else { return false }
        let recordName = record.name.uppercased()
        return record.content.uppercased().contains(content) || names.contains { recordName.contains($0) }
    }
}

private struct BadgesStack: View {
    let record: ProviderRecord
    let helpers: RecordHelpers
    @StateObject private var settings = SettingsManager.shared

    var body: some View {
        if settings.showRecordBadges {
            let badges = helpers.badges(for: record)
            if !badges.isEmpty {
                HStack(alignment: .center, spacing: 6) {
                    ForEach(badges) { badge in
                        badge.view
                            .accessibilityIdentifier("record.badge.\(badge.rawValue).\(record.name)")
                    }
                }
            }
        }
    }
}

#if os(iOS)
private struct RecordRowView: View {
    let record: ProviderRecord
    let zone: ProviderZone
    @StateObject private var settings = SettingsManager.shared

    private var helpers: RecordHelpers {
        RecordHelpers(zone: zone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: all badges on a single line (type, priority, semantic, proxy)
            badgesLine

            // Record name (key) + content (value) kept tight together
            VStack(alignment: .leading, spacing: 2) {
                helpers.recordNameDisplay(record, monochrome: true)
                    .font(.callout.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(helpers.recordContentText(for: record, masked: settings.maskContentColumn))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .contextMenu {
                        if settings.maskContentColumn {
                            Button("Copy Actual Content") {
                                copyToClipboard(helpers.recordContentText(for: record))
                            }
                        }
                    }
            }

            // Comment
            if let comment = record.comment,
               !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.caption2)
                        .padding(.top, 1)

                    Text(comment.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.caption.italic())
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.tertiary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("View and manage this record")
    }

    private var accessibilityLabel: String {
        let name = helpers.recordNameText(for: record)
        let value = helpers.recordContentText(for: record, masked: false)
        return "\(record.type) record, \(name), points to \(value)"
    }

    @ViewBuilder
    private var badgesLine: some View {
        if hasAnyBadges {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    TypeBadge(type: record.type)
                    if let priority = record.priority {
                        PriorityBadge(priority: priority)
                    }
                    BadgesStack(record: record, helpers: helpers)
                    if let proxied = record.proxied, proxied {
                        BadgeView("CF PROXY", color: .orange, helpText: "Traffic is proxied through Cloudflare")
                            .accessibilityLabel("Traffic is proxied through Cloudflare")
                    }
                }
            }
        } else {
            TypeBadge(type: record.type)
        }
    }

    private var hasAnyBadges: Bool {
        record.priority != nil ||
            record.proxied == true ||
            (settings.showRecordBadges && !helpers.badges(for: record).isEmpty)
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }
}
#endif

// MARK: - View Modifiers

struct TruncationModifier: ViewModifier {
    let wrapped: Bool

    func body(content: Content) -> some View {
        if wrapped {
            content
        } else {
            content.truncationMode(.tail)
        }
    }
}
