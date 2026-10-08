import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AddZoneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @FocusState private var isZoneFieldFocused: Bool

    let environmentId: UUID

    @State private var selectedProvider: DNSProvider?
    @State private var zoneName = ""
    @State private var isCreating = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var createdZonePresentation: CreatedZonePresentation?

    private var availableProviders: [DNSProvider] {
        model.providers.filter { provider in
            provider.supportsZoneCreation && provider.isConnected(environmentId: environmentId)
        }
    }

    private var trimmedZoneName: String {
        zoneName.trimmed
    }

    private var zoneNameError: String? {
        guard !trimmedZoneName.isEmpty else { return nil }
        return DNSRecordValidator.validateDomain(trimmedZoneName)
    }

    private var canCreateZone: Bool {
        selectedProvider != nil && !trimmedZoneName.isEmpty && zoneNameError == nil && !isCreating
    }

    private var titleText: String {
        if let provider = selectedProvider {
            return "Add \(provider.displayName) Zone"
        }
        return "Add Zone"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    if availableProviders.isEmpty {
                        Text("Connect a supported provider to add a zone.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Provider", selection: selectedProviderBinding) {
                            ForEach(availableProviders) { provider in
                                Text(provider.displayName).tag(Optional(provider))
                            }
                        }
                        .disabled(availableProviders.count == 1)
                    }
                }

                Section {
                    zoneNameField
                } header: {
                    Text("Zone Name")
                } footer: {
                    Text(zoneNameError ?? "Enter the apex domain you want to create.")
                        .foregroundStyle(zoneNameError == nil ? Color.secondary : .red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(titleText)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating..." : "Create") {
                        Task { await createZone() }
                    }
                    .disabled(!canCreateZone)
                    .accessibilityIdentifier("zone.create")
                    #if os(macOS)
                    .keyboardShortcut(.defaultAction)
                    #endif
                }
            }
        }
        #if os(macOS)
        .frame(width: 420)
        #endif
        .onAppear(perform: configureInitialProviderSelection)
        .sheet(item: $createdZonePresentation, onDismiss: {
            dismiss()
        }) { presentation in
            ZoneNameserversSheet(
                zoneName: presentation.zoneName,
                nameservers: presentation.nameservers
            )
        }
        .alert("Unable to Create Zone", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private var zoneNameField: some View {
        TextField("example.com", text: $zoneName)
            .accessibilityIdentifier("zone.name")
            .focused($isZoneFieldFocused)
            .disabled(isCreating || availableProviders.isEmpty)
            .onSubmit {
                guard canCreateZone else { return }
                Task { await createZone() }
            }
    }

    private var selectedProviderBinding: Binding<DNSProvider?> {
        Binding(
            get: { selectedProvider },
            set: { selectedProvider = $0 }
        )
    }

    private func configureInitialProviderSelection() {
        if selectedProvider == nil, availableProviders.count == 1 {
            selectedProvider = availableProviders.first
        } else if let selectedProvider, !availableProviders.contains(selectedProvider) {
            self.selectedProvider = availableProviders.count == 1 ? availableProviders.first : nil
        }

        isZoneFieldFocused = !availableProviders.isEmpty
    }

    @MainActor
    private func createZone() async {
        guard let provider = selectedProvider, canCreateZone else { return }

        isCreating = true
        defer { isCreating = false }

        do {
            let createdZone = try await model.createZone(
                named: trimmedZoneName,
                provider: provider,
                environmentId: environmentId
            )

            if !createdZone.nameservers.isEmpty {
                createdZonePresentation = CreatedZonePresentation(
                    zoneName: createdZone.name,
                    nameservers: createdZone.nameservers
                )
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

private struct CreatedZonePresentation: Identifiable {
    let id = UUID()
    let zoneName: String
    let nameservers: [String]
}
