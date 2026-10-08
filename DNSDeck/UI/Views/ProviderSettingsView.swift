
import SwiftUI

struct ProviderSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var environmentManager = EnvironmentManager.shared
    @AppStorage(SettingsRoute.providerEnvironmentKey) private var preferredEnvironmentID = ""
    @State private var selectedProvider: DNSProvider?

    private var environmentID: UUID? {
        SettingsRoute.resolvedEnvironmentID(
            preferredID: preferredEnvironmentID,
            environments: environmentManager.environments,
            selectedEnvironment: model.selectedEnvironment
        )
    }

    private var environmentIDBinding: Binding<UUID?> {
        Binding(
            get: { environmentID },
            set: { preferredEnvironmentID = $0?.uuidString ?? "" }
        )
    }

    var body: some View {
        Form {
            Section("Environment") {
                Picker("Configure providers for", selection: environmentIDBinding) {
                    ForEach(environmentManager.environments) { environment in
                        Text(environment.name).tag(Optional(environment.id))
                    }
                }
                .accessibilityIdentifier("settings.providers.environment")
            }

            Section {
                if let environmentID {
                    ForEach(DNSProvider.allCases, id: \.self) { provider in
                        providerRow(for: provider, environmentID: environmentID)
                    }
                } else {
                    ContentUnavailableView(
                        "No Environments",
                        systemImage: "tray",
                        description: Text("Create an environment before connecting a provider.")
                    )
                }
            } header: {
                Text("DNS Providers")
            } footer: {
                Text("Credentials are stored separately for each environment.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let environmentID {
                preferredEnvironmentID = environmentID.uuidString
                model.loadCredentials(for: environmentID)
            }
        }
        .onChange(of: environmentID) { _, newEnvironmentID in
            if let newEnvironmentID {
                preferredEnvironmentID = newEnvironmentID.uuidString
                model.loadCredentials(for: newEnvironmentID)
            }
        }
        .sheet(item: $selectedProvider, onDismiss: {
            if let environmentID {
                model.loadCredentials(for: environmentID)
            }
        }) { provider in
            if let environmentID {
                ProviderConnectionSheet(provider: provider, environmentId: environmentID)
                    .environmentObject(model)
            }
        }
    }

    private func providerRow(for provider: DNSProvider, environmentID: UUID) -> some View {
        HStack {
            HStack(spacing: 8) {
                ProviderIcon(provider: provider)

                HStack(alignment: .center, spacing: 6) {
                    Text(provider.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .help(Text(provider.description))
                    if provider.isConnected(environmentId: environmentID) {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 6))
                            .accessibilityLabel("Connected")
                    }
                }
            }
            Spacer()
            Button(provider.isConnected(environmentId: environmentID) ? "Manage" : "Connect") {
                selectedProvider = provider
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("provider.\(provider.rawValue).connect")
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}
