#if os(macOS)
import AvgeekDesignSystem
import SwiftUI

// MARK: - InlineRecordEditor

struct InlineRecordEditor: View {
    @Binding var records: [InlineRecord]
    let zone: ProviderZone

    private let maxRecords = 1000
    private let supportedInlineTypes = ["A", "AAAA", "CNAME", "TXT"]

    private var showProxied: Bool {
        zone.provider == .cloudflare
    }

    private var totalErrorCount: Int {
        records.reduce(0) { $0 + $1.validationErrors.count }
    }

    private var allErrors: [(rowIndex: Int, field: String, message: String)] {
        var result: [(rowIndex: Int, field: String, message: String)] = []
        for (index, record) in records.enumerated() {
            for (field, message) in record.validationErrors.sorted(by: { $0.key < $1.key }) {
                result.append((rowIndex: index, field: field, message: message))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if records.isEmpty {
                emptyState
            } else {
                headerRow
                Divider()
                recordsList
            }

            Divider()
            bottomBar
            validationSummary
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        AvgeekEmptyStateView(
            icon: "plus.rectangle.on.rectangle",
            title: "No records yet",
            message: "Click \"Add Record\" below to start adding DNS records."
        )
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Type")
                .frame(width: 80, alignment: .leading)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Value")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("TTL")
                .frame(width: 56, alignment: .leading)
            if showProxied {
                Text("Proxy")
                    .frame(width: 40, alignment: .center)
            }
            Spacer()
                .frame(width: 24)
        }
        .font(.subheadline.weight(.medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Records List

    private var recordsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, _ in
                    recordRow(at: index)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(index % 2 == 0 ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                }
            }
        }
    }

    // MARK: - Record Row

    private func recordRow(at index: Int) -> some View {
        HStack(spacing: 8) {
            typePicker(at: index)
            nameField(at: index)
            valueField(at: index)
            ttlField(at: index)

            if showProxied {
                proxiedToggle(at: index)
            }

            actionButtons(at: index)
        }
    }

    // MARK: - Type Picker

    private func typePicker(at index: Int) -> some View {
        Picker("", selection: Binding(
            get: { records[index].type },
            set: { newType in
                records[index].type = newType
                records[index].runValidation()
            }
        )) {
            ForEach(supportedInlineTypes, id: \.self) { type in
                Text(type).tag(type)
            }
        }
        .labelsHidden()
        .frame(width: 80)
    }

    // MARK: - Text Fields

    private func nameField(at index: Int) -> some View {
        let hasError = records[index].validationErrors["name"] != nil
        return TextField("example.com", text: Binding(
            get: { records[index].name },
            set: { records[index].name = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .overlay(errorOverlay(hasError))
        .help(records[index].validationErrors["name"] ?? "")
        .onSubmit { records[index].runValidation() }
        .onChange(of: records[index].name) { revalidateIfNeeded(at: index, field: "name") }
        .frame(maxWidth: .infinity)
    }

    private func valueField(at index: Int) -> some View {
        let hasError = records[index].validationErrors["value"] != nil
        return TextField(valuePlaceholder(for: records[index].type), text: Binding(
            get: { records[index].value },
            set: { records[index].value = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .overlay(errorOverlay(hasError))
        .help(records[index].validationErrors["value"] ?? "")
        .onSubmit { records[index].runValidation() }
        .onChange(of: records[index].value) { revalidateIfNeeded(at: index, field: "value") }
        .frame(maxWidth: .infinity)
    }

    private func ttlField(at index: Int) -> some View {
        let hasError = records[index].validationErrors["ttl"] != nil
        return TextField("Auto", text: Binding(
            get: { records[index].ttl },
            set: { records[index].ttl = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .overlay(errorOverlay(hasError))
        .help(records[index].validationErrors["ttl"] ?? "")
        .onSubmit { records[index].runValidation() }
        .onChange(of: records[index].ttl) { revalidateIfNeeded(at: index, field: "ttl") }
        .frame(width: 56)
    }

    @ViewBuilder
    private func errorOverlay(_ hasError: Bool) -> some View {
        if hasError {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.red, lineWidth: 1.5)
        }
    }

    // MARK: - Proxied Toggle

    private func proxiedToggle(at index: Int) -> some View {
        let isProxyable = Constants.DNSRecordTypes.proxyableTypes.contains(records[index].type)
        return Group {
            if isProxyable {
                Toggle("", isOn: Binding(
                    get: { records[index].proxied },
                    set: { records[index].proxied = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            } else {
                Color.clear
            }
        }
        .frame(width: 40)
    }

    // MARK: - Action Buttons

    private func actionButtons(at index: Int) -> some View {
        Button {
            deleteRecord(at: index)
        } label: {
            Image(systemName: "trash")
                .foregroundColor(.red)
        }
        .buttonStyle(.borderless)
        .help("Delete record")
        .frame(width: 24)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                addRecord()
            } label: {
                Label("Add Record", systemImage: "plus")
            }
            .accessibilityIdentifier("record.import.inline.add")
            .disabled(records.count >= maxRecords)

            Spacer()

            Text("\(records.count) record\(records.count == 1 ? "" : "s")")
                .font(.body)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("record.import.inline.count")

            if records.count >= maxRecords {
                Text("(max \(maxRecords))")
                    .foregroundColor(.orange)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Validation Summary

    @ViewBuilder
    private var validationSummary: some View {
        if totalErrorCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Divider()

                Label(
                    "\(totalErrorCount) validation error\(totalErrorCount == 1 ? "" : "s")",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.red)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(allErrors.enumerated()), id: \.offset) { _, error in
                            Text("Row \(error.rowIndex + 1) - \(error.field): \(error.message)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .frame(maxHeight: 80)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Row Actions

    private func addRecord() {
        guard records.count < maxRecords else { return }
        let lastType = records.last?.type ?? "A"
        let type = supportedInlineTypes.contains(lastType) ? lastType : "A"
        let newRecord = InlineRecord(type: type)
        records.append(newRecord)
    }

    private func deleteRecord(at index: Int) {
        guard records.indices.contains(index) else { return }
        records.remove(at: index)
    }

    // MARK: - Helpers

    private func revalidateIfNeeded(at index: Int, field: String) {
        guard records.indices.contains(index) else { return }
        if records[index].validationErrors[field] != nil {
            records[index].runValidation()
        }
    }

    private func valuePlaceholder(for type: String) -> String {
        switch type {
        case "A": "192.168.1.1"
        case "AAAA": "2001:db8::1"
        case "CNAME": "target.example.com"
        case "TXT": "v=spf1 include:..."
        default: "Value"
        }
    }
}

#endif
