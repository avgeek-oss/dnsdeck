import AvgeekDesignSystem
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RecordFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    let zone: ProviderZone
    let record: ProviderRecord?
    @Binding var isSubmitting: Bool

    @StateObject private var localErrorHandler = ErrorHandler()
    @State private var form: RecordFormState
    @State private var showDiscardConfirmation = false

    init(zone: ProviderZone, record: ProviderRecord?, isSubmitting: Binding<Bool>) {
        self.zone = zone
        self.record = record
        _isSubmitting = isSubmitting
        _form = State(initialValue: RecordFormState(zone: zone, record: record))
    }

    var body: some View {
        NavigationStack {
            Form {
                recordSection
                if form.type == "MX" {
                    Section("Priority") { MXPriorityField(mxPriority: $form.mxPriority) }
                }
                if form.type == "SRV" {
                    Section("SRV Metrics") {
                        SRVMetricsFields(
                            srvPriority: $form.srvPriority,
                            srvWeight: $form.srvWeight,
                            srvPort: $form.srvPort
                        )
                    }
                }
                if form.type == "CAA" {
                    Section("CAA") {
                        CAADetails(caaFlags: $form.caaFlags, caaTag: $form.caaTag, caaValue: $form.caaValue)
                    }
                }
                Section("TTL") {
                    TTLField(ttlAuto: $form.ttlAuto, ttlValue: $form.ttlValue, provider: zone.provider)
                }
                if zone.provider == .cloudflare {
                    Section("Cloudflare") {
                        CloudflareProxyToggle(
                            recordType: form.type,
                            provider: zone.provider,
                            proxied: $form.proxied
                        )
                    }
                }
                if zone.provider.capabilities.features.contains(.comments) {
                    Section("Comment") {
                        CommentField(provider: zone.provider, comment: $form.comment)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(record == nil ? "Add DNS Record" : "Edit DNS Record")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { formToolbar }
        }
        .onAppear { record == nil ? syncTypeDefaults() : parseExistingRecord() }
        .onChange(of: form.type) {
            if record == nil { syncTypeDefaults() }
        }
        .withErrorHandling(localErrorHandler)
        .alert("Discard Changes?", isPresented: $showDiscardConfirmation) {
            Button("Discard", role: .destructive) { dismiss() }
                .accessibilityIdentifier("record.form.discard")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        #if os(macOS)
        .frame(minWidth: 520)
        #endif
    }

    private var recordSection: some View {
        Section("Record") {
            if record == nil {
                TypePicker(type: $form.type, provider: zone.provider)
            } else {
                HStack {
                    Text("Type")
                    Spacer()
                    Text(DNSRecordHelpers.typeLabel(for: form.type)).foregroundStyle(.secondary)
                }
            }
            NativeTextField(placeholder: DNSRecordHelpers.namePlaceholder(for: form.type), text: $form.name)
                .accessibilityIdentifier("record.form.name")
            if isMultiValueRecord {
                TextEditor(text: $form.content)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("record.form.content.input")
            } else {
                ContentField(
                    type: form.type,
                    content: $form.content,
                    ptrHostname: $form.ptrHostname,
                    caaValue: $form.caaValue,
                    srvService: $form.srvService,
                    srvProto: $form.srvProto,
                    srvDomain: $form.srvDomain,
                    srvTarget: $form.srvTarget
                )
                .accessibilityIdentifier("record.form.content")
            }
        }
    }

    @ToolbarContentBuilder private var formToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) {
                guard !isSubmitting else { return }
                if hasChanges { showDiscardConfirmation = true } else { dismiss() }
            }
            .disabled(isSubmitting)
            .accessibilityIdentifier("record.form.cancel")
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #else
            .keyboardShortcut(.escape)
            #endif
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: submitRecord) {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text(record == nil ? "Add" : "Update").frame(minWidth: 60)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!formValid || isSubmitting || (record != nil && !hasChanges))
            .accessibilityIdentifier("record.form.submit")
        }
    }

    private func syncTypeDefaults() {
        switch form.type {
        case "SRV":
            if form.srvDomain.isEmpty { form.srvDomain = zone.name }
            if form.srvService.isEmpty { form.srvService = "_service" }
            if form.name.isEmpty { form.name = "_service._tcp" }
            if form.srvTarget.isEmpty { form.srvTarget = zone.name }
        case "PTR":
            if form.ptrHostname.isEmpty { form.ptrHostname = zone.name }
        case "CAA":
            if form.caaValue.isEmpty { form.caaValue = "letsencrypt.org" }
        default:
            break
        }
    }

    private func parseExistingRecord() {
        guard let record else { return }
        switch form.type {
        case "SRV":
            if let data = record.recordData.decode(CFDNSRecord.self)?.data {
                form.srvPriority = data.priority ?? 10
                form.srvWeight = data.weight ?? 0
                form.srvPort = data.port ?? 443
                form.srvTarget = data.target ?? zone.name
                let parts = record.name.components(separatedBy: ".")
                if parts.count >= 2 {
                    form.srvService = parts[0]
                    form.srvProto = parts[1]
                    if parts.count > 2 { form.srvDomain = parts.dropFirst(2).joined(separator: ".") }
                }
            } else {
                let parts = record.content.components(separatedBy: " ")
                if parts.count >= 4 {
                    form.srvPriority = Int(parts[0]) ?? 10
                    form.srvWeight = Int(parts[1]) ?? 0
                    form.srvPort = Int(parts[2]) ?? 443
                    form.srvTarget = parts[3]
                }
            }
        case "PTR":
            form.ptrHostname = record.content
        case "CAA":
            let parts = record.content.components(separatedBy: " ")
            if parts.count >= 3 {
                form.caaFlags = Int(parts[0]) ?? 0
                form.caaTag = parts[1]
                form.caaValue = parts.dropFirst(2).joined(separator: " ")
            }
        default:
            break
        }
    }

    private func submitRecord() {
        guard !isSubmitting else { return }
        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            localErrorHandler.clearError()
            do {
                if let record {
                    try await model.updateRecord(in: zone, record: record, edits: updateRequest(for: record))
                } else {
                    try await model.createRecord(in: zone, payload: createRequest)
                }
                AvgeekFeedback.success()
                dismiss()
            } catch {
                localErrorHandler.handle(error)
                AvgeekFeedback.error()
            }
        }
    }

    private var createRequest: CreateProviderRecordRequest {
        CreateProviderRecordRequest(
            name: trimmedName,
            type: form.type,
            content: contentValue ?? "",
            ttl: form.ttlAuto ? 1 : form.ttlValue,
            proxied: Constants.DNSRecordTypes.proxyableTypes.contains(form.type) ? form.proxied : nil,
            priority: form.type == "MX" ? form.mxPriority : nil,
            comment: form.comment.trimmed.isEmpty ? nil : form.comment.trimmed,
            recordData: recordData
        )
    }

    private func updateRequest(for record: ProviderRecord) -> UpdateProviderRecordRequest {
        UpdateProviderRecordRequest(
            name: hasNameChanged ? trimmedName : nil,
            content: hasContentChanged && !isMultiValueRecord ? contentValue : nil,
            ttl: hasTTLChanged ? (form.ttlAuto ? 1 : form.ttlValue) : nil,
            proxied: hasProxiedChanged ? form.proxied : nil,
            priority: hasPriorityChanged ? form.mxPriority : nil,
            comment: hasCommentChanged ? (form.comment.trimmed.isEmpty ? "" : form.comment.trimmed) : nil,
            values: hasContentChanged && isMultiValueRecord ? multiValueLines : nil,
            recordData: hasRecordDataChanged(record) ? recordData : nil
        )
    }

    private var formValid: Bool {
        if isMultiValueRecord {
            return !trimmedName.isEmpty && !multiValueLines.isEmpty &&
                multiValueLines
                .allSatisfy { DNSRecordValidator.validateRecordValue(type: form.type, rawValue: $0) == nil }
        }
        return DNSRecordHelpers.isFormValid(
            type: form.type,
            name: trimmedName,
            contentValue: contentValue,
            recordData: recordData
        )
    }

    private var hasChanges: Bool {
        guard let record else { return form.isDirty }
        return hasNameChanged || hasContentChanged || hasTTLChanged || hasProxiedChanged ||
            hasPriorityChanged || hasCommentChanged || hasRecordDataChanged(record)
    }

    private var hasNameChanged: Bool {
        record.map { trimmedName != $0.name } ?? false
    }

    private var hasTTLChanged: Bool {
        record.map { (form.ttlAuto ? 1 : form.ttlValue) != ($0.ttl ?? 1) } ?? false
    }

    private var hasProxiedChanged: Bool {
        guard Constants.DNSRecordTypes.proxyableTypes.contains(form.type) else { return false }
        return record.map { form.proxied != ($0.proxied ?? false) } ?? false
    }

    private var hasPriorityChanged: Bool {
        form.type == "MX" && (record.map { form.mxPriority != ($0.priority ?? 10) } ?? false)
    }

    private var hasCommentChanged: Bool {
        zone.provider.capabilities.features.contains(.comments) &&
            (record.map { form.comment.trimmed != ($0.comment ?? "") } ?? false)
    }

    private var hasContentChanged: Bool {
        guard let record else { return false }
        if isMultiValueRecord { return multiValueLines != record.values }
        return contentValue.map { $0 != record.content } ?? false
    }

    private func hasRecordDataChanged(_ record: ProviderRecord) -> Bool {
        guard ["SRV", "CAA"].contains(form.type), let recordData else { return false }
        return record.recordData.decode(CFDNSRecord.self)?.data.map { $0 != recordData } ??
            (recordData.flatContent != record.content)
    }

    private var trimmedName: String {
        form.name.trimmed
    }

    private var contentValue: String? {
        DNSRecordHelpers.contentValue(for: form.type, content: form.content, ptrHostname: form.ptrHostname)
    }

    private var isMultiValueRecord: Bool {
        (record?.values.count ?? 0) > 1
    }

    private var multiValueLines: [String] {
        form.content.components(separatedBy: .newlines).map(\.trimmed).filter(\.isNotEmpty)
    }

    private var recordData: RecordData? {
        DNSRecordHelpers.recordData(
            for: form.type,
            srvService: form.srvService,
            srvProto: form.srvProto,
            srvDomain: form.srvDomain,
            srvPriority: form.srvPriority,
            srvWeight: form.srvWeight,
            srvPort: form.srvPort,
            srvTarget: form.srvTarget,
            caaFlags: form.caaFlags,
            caaTag: form.caaTag,
            caaValue: form.caaValue
        )
    }
}

private struct RecordFormState {
    var type, name, content: String
    var ttlAuto: Bool
    var ttlValue: Int
    var proxied: Bool
    var mxPriority: Int
    var srvService, srvProto, srvDomain: String
    var srvPriority, srvWeight, srvPort: Int
    var srvTarget, ptrHostname, caaTag, caaValue, comment: String
    var caaFlags: Int

    init(zone: ProviderZone, record: ProviderRecord?) {
        type = record?.type ?? "A"
        name = record?.name ?? ""
        content = record.map { $0.values.count > 1 ? $0.values.joined(separator: "\n") : $0.content } ?? ""
        ttlAuto = record?.ttl == nil || record?.ttl == 1
        ttlValue = record?.ttl ?? 300
        proxied = record?.proxied ?? false
        mxPriority = record?.priority ?? 10
        srvService = "_service"
        srvProto = "_tcp"
        srvDomain = zone.name
        srvPriority = 10
        srvWeight = 0
        srvPort = 443
        srvTarget = zone.name
        ptrHostname = record?.content ?? ""
        caaFlags = 0
        caaTag = "issue"
        caaValue = "letsencrypt.org"
        comment = record?.comment ?? ""
    }

    var isDirty: Bool {
        !name.trimmed.isEmpty || !content.trimmed.isEmpty || !comment.trimmed.isEmpty ||
            (type == "MX" && mxPriority != 10) ||
            (type == "SRV" && (!srvTarget.trimmed.isEmpty || srvPriority != 10 || srvWeight != 0 || srvPort != 443)) ||
            (type == "CAA" && (!caaValue.trimmed.isEmpty || caaFlags != 0 || caaTag != "issue")) ||
            (type == "PTR" && !ptrHostname.trimmed.isEmpty) || !ttlAuto || ttlValue != 300 || proxied
    }
}
