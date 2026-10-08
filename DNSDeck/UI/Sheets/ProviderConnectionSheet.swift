import AvgeekDesignSystem
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ProviderConnectionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showDisconnectConfirmation = false

    let provider: DNSProvider
    let environmentId: UUID

    private func openURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(provider.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let setup = provider.setupLink {
                        Button {
                            openURL(setup.url)
                        } label: {
                            Text(setup.title)
                        }
                        .buttonStyle(.bordered)
                        .help("Use the following link to get help with \(provider.displayName) credentials")
                    }
                }

                Section("Credentials") {
                    ForEach(provider.credentialFields) { field in
                        credentialField(field)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("provider.\(provider.rawValue).credentials")
            .navigationTitle(provider.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") {
                        dismiss()
                    }
                }

                if provider.isConnected(environmentId: environmentId) {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Disconnect", role: .destructive) {
                            showDisconnectConfirmation = true
                        }
                        .accessibilityIdentifier("provider.\(provider.rawValue).disconnect")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(primaryActionTitle) {
                        primaryAction()
                    }
                    .disabled(!hasValidCredentials)
                    .accessibilityIdentifier("provider.\(provider.rawValue).save")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 320)
        #endif
        .onAppear {
            model.loadCredentials(for: environmentId)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                model.error = nil
            }
        } message: {
            Text(errorMessage)
        }
        .alert("Disconnect \(provider.displayName)?", isPresented: $showDisconnectConfirmation) {
            Button("Disconnect", role: .destructive) {
                disconnectProvider()
            }
            .accessibilityIdentifier("provider.\(provider.rawValue).confirmDisconnect")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove your \(provider.displayName) credentials. You can reconnect at any time.")
        }
    }

    @ViewBuilder
    private func credentialField(_ field: ProviderCredentialField) -> some View {
        let binding = model.credentialBinding(
            for: provider,
            fieldId: field.id,
            environmentId: environmentId
        )

        VStack(alignment: .leading, spacing: 6) {
            switch field.kind {
            case .text:
                TextField(text: binding, prompt: Text(field.label)) {
                    Text(field.label)
                }
                .accessibilityIdentifier("provider.\(provider.rawValue).credential.\(field.id)")
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            case .secret:
                SecureField(text: binding, prompt: Text(field.label)) {
                    Text(field.label)
                }
                .accessibilityIdentifier("provider.\(provider.rawValue).credential.\(field.id)")
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .privacySensitive()
            case .multilineSecret:
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: binding)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .privacySensitive()
                    .accessibilityIdentifier("provider.\(provider.rawValue).credential.\(field.id)")
            }

            if let helpText = field.helpText {
                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hasValidCredentials: Bool {
        provider.credentialFields.filter(\.isRequired).allSatisfy { field in
            let value = model.credentialBinding(
                for: provider,
                fieldId: field.id,
                environmentId: environmentId
            ).wrappedValue
            return !value.trimmed.isEmpty
        }
    }

    private var primaryActionTitle: String {
        provider.isConnected(environmentId: environmentId) ? "Save" : "Connect"
    }

    private func primaryAction() {
        saveCredentialWithErrorHandling(for: provider)
        if !showingError {
            AvgeekFeedback.success()
            dismiss()
        }
    }

    private func disconnectProvider() {
        model.disconnect(provider: provider, environmentId: environmentId)

        if let error = model.error, !error.isEmpty {
            errorMessage = error
            showingError = true
            AvgeekFeedback.error()
            model.error = nil
        } else {
            AvgeekFeedback.impact(.medium)
            dismiss()
        }
    }

    private func saveCredentialWithErrorHandling(for provider: DNSProvider) {
        model.error = nil
        model.saveCredential(for: provider, environmentId: environmentId)

        if let error = model.error, !error.isEmpty {
            errorMessage = error
            showingError = true
            AvgeekFeedback.error()
            model.error = nil
        }
    }
}
