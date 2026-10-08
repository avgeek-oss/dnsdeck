import SwiftUI

struct UpdateNameserversSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    let zone: ProviderZone

    @State private var rows: [NameserverDraft]
    @State private var isSaving = false
    @State private var submissionError: String?

    init(zone: ProviderZone) {
        self.zone = zone
        let values = zone.nameservers.isEmpty ? ["", ""] : zone.nameservers
        _rows = State(initialValue: values.map(NameserverDraft.init))
    }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Domain", value: zone.name)

                Section("Nameservers") {
                    ForEach($rows) { $row in
                        HStack(spacing: 8) {
                            TextField("Nameserver", text: $row.value)
                                .textContentType(.URL)
                                .autocorrectionDisabled()

                            Button {
                                rows.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove Nameserver")
                            .disabled(rows.count <= policy.minimumCount || isSaving)
                        }
                    }

                    Button {
                        rows.append(NameserverDraft(value: ""))
                    } label: {
                        Label("Add Nameserver", systemImage: "plus")
                    }
                    .disabled(rows.count >= policy.maximumCount || isSaving)
                }

                Section {
                    Label(
                        "Changing registrar nameservers can interrupt DNS until delegation propagates.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)

                    if let validationMessage {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    } else if let submissionError {
                        Text(submissionError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Update Nameservers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        updateNameservers()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Update")
                        }
                    }
                    .accessibilityLabel("Update")
                    .disabled(validationMessage != nil || isSaving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
        .interactiveDismissDisabled(isSaving)
    }

    private var policy: ProviderNameserverPolicy {
        zone.provider.nameserverPolicy ?? .standard
    }

    private var validationMessage: String? {
        do {
            _ = try NameserverUpdate.normalize(rows.map(\.value), policy: policy)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func updateNameservers() {
        submissionError = nil
        isSaving = true
        let values = rows.map(\.value)
        Task {
            do {
                try await model.updateNameservers(for: zone, nameservers: values)
                dismiss()
            } catch {
                submissionError = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private struct NameserverDraft: Identifiable {
    let id = UUID()
    var value: String
}
