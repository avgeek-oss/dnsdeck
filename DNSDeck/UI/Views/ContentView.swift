import AvgeekDesignSystem
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

private struct IdentifiableUUID: Identifiable, Hashable {
    let id: UUID
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var lockController: AppLockController
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsRoute.selectedSectionKey) private var selectedSettingsSection = PreferencesSection.general
        .rawValue
    @AppStorage(SettingsRoute.providerEnvironmentKey) private var settingsEnvironmentID = ""
    @State private var addZoneEnvironmentId: IdentifiableUUID?
    @State private var showingNewEnvironment = false
    @State private var showingEditEnvironment = false
    @State private var showingDeleteConfirmation = false
    @State private var showingZoneDeleteConfirmation = false
    @State private var environmentToEdit: DNSEnvironment?
    @State private var environmentToDelete: DNSEnvironment?
    @State private var zoneToDelete: ProviderZone?
    @State private var zoneForNameserverUpdate: ProviderZone?
    #if os(iOS)
    @State private var showingSettings = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var collapsedProviders: Set<DNSProvider> = []
    @State private var hasHandledZoneWindowRequest = false

    let zoneWindowRequest: ZoneWindowRequest?

    private var selectedEnvironmentBinding: Binding<DNSEnvironment?> {
        Binding(
            get: { model.selectedEnvironment },
            set: { newValue in
                Task { @MainActor in
                    lockController.registerUserActivity()
                    model.selectedEnvironment = newValue
                }
            }
        )
    }

    private var selectedZoneBinding: Binding<ProviderZone?> {
        Binding(
            get: { model.selectedZone },
            set: {
                lockController.registerUserActivity()
                model.selectZone($0)
            }
        )
    }

    private var starredEnvironments: [DNSEnvironment] {
        model.environmentManager.environments
            .filter(\.isStarred)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var unstarredEnvironments: [DNSEnvironment] {
        model.environmentManager.environments
            .filter { !$0.isStarred }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var sortedEnvironments: [DNSEnvironment] {
        starredEnvironments + unstarredEnvironments
    }

    var body: some View {
        NavigationSplitView {
            environmentSidebar
        } content: {
            zoneSidebar
        } detail: {
            detailView
        }
        #if os(iOS)
        .sheet(isPresented: $showingSettings, onDismiss: {
            Task { await model.refreshZones(forceRefresh: true) }
        }) {
            PreferencesView()
                .environmentObject(model)
                .environmentObject(lockController)
                .environmentObject(SettingsManager.shared)
        }
        #endif
        .sheet(item: $addZoneEnvironmentId) { context in
            AddZoneSheet(environmentId: context.id)
                .environmentObject(model)
        }
        .sheet(item: $zoneForNameserverUpdate) { zone in
            UpdateNameserversSheet(zone: zone)
                .environmentObject(model)
        }
        .sheet(isPresented: $showingNewEnvironment) {
            EnvironmentEditorSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $showingEditEnvironment) {
            if let environment = environmentToEdit {
                EnvironmentEditorSheet(environment: environment)
                    .environmentObject(model)
            }
        }
        .alert("Delete Environment", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                environmentToDelete = nil
            }
            Button("Delete", role: .destructive) {
                deleteEnvironment()
            }
        } message: {
            if let environment = environmentToDelete {
                Text("Are you sure you want to delete \"\(environment.name)\"? This action cannot be undone.")
            }
        }
        .alert("Delete DNS Zone", isPresented: $showingZoneDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                zoneToDelete = nil
            }
            Button("Delete", role: .destructive) {
                deleteSelectedZone()
            }
        } message: {
            if let zoneToDelete {
                Text(
                    "Delete \"\(zoneToDelete.name)\" and all of its DNS records from \(zoneToDelete.provider.displayName)? This action cannot be undone."
                )
            }
        }
        #if os(macOS)
        .onChange(of: model.zones) { _, newZones in
            if shouldDelayDefaultZoneSelection(for: newZones) {
                return
            }
            if model.selectedZone == nil, let firstZone = newZones.first {
                Task { @MainActor in
                    model.selectZone(firstZone)
                }
            }
        }
        #endif
        .task {
            await Task.yield()
            if let zoneWindowRequest,
               let requestedEnvironment = sortedEnvironments.first(where: { $0.id == zoneWindowRequest.environmentId })
            {
                model.selectedEnvironment = requestedEnvironment
            } else if model.selectedEnvironment == nil, let firstEnv = sortedEnvironments.first {
                model.selectedEnvironment = firstEnv
            }
        }
        .onAppear {
            lockController.handleScenePhaseChange(scenePhase)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNewEnvironmentSheet)) { notification in
            guard notificationTargetsCurrentWindow(notification) else { return }
            guard !lockController.isLocked else { return }
            showingNewEnvironment = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showEditEnvironmentSheet)) { notification in
            guard notificationTargetsCurrentWindow(notification) else { return }
            guard !lockController.isLocked else { return }
            Task { @MainActor in
                if let selectedEnv = model.selectedEnvironment {
                    environmentToEdit = selectedEnv
                    showingEditEnvironment = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadZone)) { notification in
            guard notificationTargetsCurrentWindow(notification) else { return }
            guard !lockController.isLocked else { return }
            Task { @MainActor in
                if let selectedZone = model.selectedZone {
                    await model.refreshRecords(for: selectedZone)
                }
            }
        }
        #if os(macOS)
        .onKeyPress(keys: ["p"]) { press in
            guard press.modifiers == .command,
                  !lockController.isLocked,
                  let environment = model.selectedEnvironment
            else { return .ignored }
            showSettings(.providers, environment: environment)
            return .handled
        }
        #endif
        .onChange(of: scenePhase) { _, newPhase in
            lockController.handleScenePhaseChange(newPhase)

            if newPhase == .active {
                SettingsManager.shared.refreshFromUserDefaults()
            }
        }
        .disabled(lockController.isLocked)
        #if os(macOS)
        .toolbar(lockController.isLocked ? .hidden : .visible, for: .windowToolbar)
        #endif
        .overlay {
            if lockController.isLocked {
                LockOverlayView()
                    .environmentObject(lockController)
            }
        }
        .withErrorHandling(model.errorHandler)
    }

    private var environmentSidebar: some View {
        Group {
            if sortedEnvironments.isEmpty {
                AvgeekEmptyStateView(
                    icon: "tray.and.arrow.down",
                    title: "No Environments",
                    message: "Create an environment to start managing DNS records.",
                    buttonTitle: "New Environment",
                    buttonIcon: "plus",
                    onButtonTap: { showingNewEnvironment = true }
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(selection: selectedEnvironmentBinding) {
                    if !starredEnvironments.isEmpty {
                        Section("Starred") {
                            ForEach(starredEnvironments) { environment in
                                environmentRow(for: environment)
                            }
                        }
                    }

                    if !unstarredEnvironments.isEmpty {
                        Section("Environments") {
                            ForEach(unstarredEnvironments) { environment in
                                environmentRow(for: environment)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Environments")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingNewEnvironment = true
                    } label: {
                        Label("New Environment", systemImage: "plus")
                    }
                    Button {
                        showSettings(.general)
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewEnvironment = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            #endif
        }
        .frame(minWidth: Constants.UI.minimumEnvironmentListWidth)
    }

    @ViewBuilder
    private var zoneSidebar: some View {
        if let selectedEnvironment = model.selectedEnvironment {
            let hasConnectedProviders = !connectedProviders(for: selectedEnvironment).isEmpty
            VStack(spacing: 0) {
                zoneList(for: selectedEnvironment)
            }
            .navigationTitle(selectedEnvironment.name)
            #if os(macOS)
            .navigationSplitViewColumnWidth(
                min: Constants.UI.minimumZoneListWidth,
                ideal: Constants.UI.preferredZoneListWidth,
                max: Constants.UI.maximumZoneListWidth
            )
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if hasConnectedProviders {
                        #if os(macOS)
                        Button {
                            addZoneEnvironmentId = IdentifiableUUID(id: selectedEnvironment.id)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("zone.add")
                        .help("Add a zone")

                        Button {
                            Task { await model.refreshZones(forceRefresh: true) }
                        } label: {
                            Label("Refresh Zones", systemImage: "arrow.clockwise")
                        }
                        .accessibilityIdentifier("zone.refresh")
                        .disabled(model.isLoading)
                        .help("Force refresh zones")
                        #else
                        Button {
                            addZoneEnvironmentId = IdentifiableUUID(id: selectedEnvironment.id)
                        } label: {
                            Image(systemName: "plus")
                        }
                        #endif
                    }

                    Button {
                        showSettings(.providers, environment: selectedEnvironment)
                    } label: {
                        Label("Manage Providers", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .accessibilityIdentifier("providers.manage")
                }
            }
        } else {
            AvgeekEmptyStateView(
                icon: "square.stack.3d.up.slash",
                title: "Select an environment",
                message: "Choose an environment from the sidebar to view zones"
            )
        }
    }

    @ViewBuilder
    private func zoneList(for environment: DNSEnvironment) -> some View {
        let providers = connectedProviders(for: environment)
        if providers.isEmpty {
            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(Constants.UIText.loadingZones)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else {
                noProvidersView(for: environment)
            }
        } else {
            List(selection: selectedZoneBinding) {
                ForEach(providers, id: \.self) { provider in
                    providerSection(for: provider)
                }
            }
            .listStyle(.sidebar)
            #if os(iOS)
            .refreshable {
                await model.refreshZones(forceRefresh: true)
            }
            #endif
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let zone = model.selectedZone {
            RecordsView(zone: zone)
        } else {
            AvgeekEmptyStateView(
                icon: "network",
                title: "No zone selected",
                message: "Once you connect a provider, select a zone to view and manage DNS records."
            )
        }
    }

    private func noProvidersView(for environment: DNSEnvironment) -> some View {
        AvgeekEmptyStateView(
            icon: "antenna.radiowaves.left.and.right",
            title: "No provider connected",
            message: "Connect a provider to view your zones.",
            buttonTitle: "Connect a Provider",
            buttonIcon: "plus",
            onButtonTap: {
                showSettings(.providers, environment: environment)
            }
        )
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func showSettings(_ section: PreferencesSection, environment: DNSEnvironment? = nil) {
        selectedSettingsSection = section.rawValue
        if let environment {
            settingsEnvironmentID = environment.id.uuidString
        }
        #if os(macOS)
        openWindow(id: SettingsWindowScene.sceneID)
        #else
        showingSettings = true
        #endif
    }

    private func environmentRow(for environment: DNSEnvironment) -> some View {
        NavigationLink(value: environment) {
            HStack(spacing: 8) {
                Button {
                    lockController.registerUserActivity()
                    model.environmentManager.toggleStar(for: environment)
                } label: {
                    Image(systemName: environment.isStarred ? "star.fill" : "star")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                #if os(macOS)
                .help(environment.isStarred ? "Unstar" : "Star")
                #endif

                Text(environment.name)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            Button {
                model.environmentManager.toggleStar(for: environment)
            } label: {
                Label(
                    environment.isStarred ? "Unstar" : "Star",
                    systemImage: environment.isStarred ? "star.slash" : "star"
                )
            }

            Divider()

            Button {
                environmentToEdit = environment
                showingEditEnvironment = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                environmentToDelete = environment
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(model.environmentManager.environments.count <= 1)
        }
    }

    private func providerTag(for provider: DNSProvider) -> some View {
        ProviderIcon(provider: provider)
    }

    private func connectedProviders(for environment: DNSEnvironment) -> [DNSProvider] {
        DNSProvider.allCases.filter { provider in
            provider.isConnected(environmentId: environment.id)
        }
    }

    private func zones(for provider: DNSProvider) -> [ProviderZone] {
        model.zones.filter { $0.provider == provider }
    }

    @ViewBuilder
    private func providerSection(for provider: DNSProvider) -> some View {
        let providerZones = zones(for: provider)
        let isCollapsed = collapsedProviders.contains(provider)

        DisclosureGroup(isExpanded: Binding(
            get: { !isCollapsed },
            set: { isExpanded in
                lockController.registerUserActivity()
                if isExpanded {
                    collapsedProviders.remove(provider)
                } else {
                    collapsedProviders.insert(provider)
                }
            }
        )) {
            providerZoneList(for: providerZones)
        } label: {
            providerSectionHeader(for: provider, count: providerZones.count)
        }
    }

    @ViewBuilder
    private func providerZoneList(for zones: [ProviderZone]) -> some View {
        if zones.isEmpty {
            Text(zoneStatusMessage)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        } else {
            ForEach(zones) { zone in
                zoneRow(for: zone)
            }
        }
    }

    private var zoneStatusMessage: String {
        model.isLoading ? Constants.UIText.loadingZones : "No zones found."
    }

    private func providerSectionHeader(for provider: DNSProvider, count: Int) -> some View {
        let countSuffix: String
        if count > 0 {
            let plural = count == 1 ? "zone" : "zones"
            countSuffix = " (\(count) \(plural))"
        } else {
            countSuffix = ""
        }
        return Text("\(provider.displayName)\(countSuffix)")
            .font(.subheadline.weight(.semibold))
    }

    private func deleteEnvironment() {
        guard let environment = environmentToDelete else { return }

        guard model.environmentManager.environments.count > 1 else { return }

        let wasSelected = model.selectedEnvironment?.id == environment.id

        model.environmentManager.deleteEnvironment(environment)

        if wasSelected {
            if let firstEnv = sortedEnvironments.first {
                Task { @MainActor in
                    model.selectedEnvironment = firstEnv
                }
            } else {
                Task { @MainActor in
                    model.selectedEnvironment = nil
                }
            }
        }

        environmentToDelete = nil
    }

    private func zoneRow(for zone: ProviderZone) -> some View {
        NavigationLink(value: zone) {
            HStack(spacing: 8) {
                providerTag(for: zone.provider)
                Text(zone.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("zone.row.\(zone.name)")
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                copyZoneName(zone)
            } label: {
                Label("Copy Zone Name", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("zone.context.copyName")

            #if os(macOS)
            Divider()

            Button {
                openZoneInNewWindow(zone)
            } label: {
                Label("Open in New Window", systemImage: "macwindow.badge.plus")
            }
            .accessibilityIdentifier("zone.context.openWindow")
            #endif

            if zone.provider.supportsNameserverUpdate(for: zone) {
                Divider()

                Button {
                    zoneForNameserverUpdate = zone
                } label: {
                    Label("Update Nameservers…", systemImage: "network")
                }
            }

            if zone.provider.capabilities.zoneCapabilities.contains(.delete) {
                Divider()

                Button(role: .destructive) {
                    zoneToDelete = zone
                    showingZoneDeleteConfirmation = true
                } label: {
                    Label("Delete Zone", systemImage: "trash")
                }
            }
        }
    }

    private func shouldDelayDefaultZoneSelection(for zones: [ProviderZone]) -> Bool {
        guard let zoneWindowRequest, !hasHandledZoneWindowRequest else { return false }
        guard model.selectedEnvironment?.id == zoneWindowRequest.environmentId else { return true }

        if let matchingZone = zones.first(where: { $0.id == zoneWindowRequest.zoneId }) {
            hasHandledZoneWindowRequest = true
            if model.selectedZone?.id != matchingZone.id {
                Task { @MainActor in
                    model.selectZone(matchingZone)
                }
            }
            return true
        }

        if model.isLoading {
            return true
        }

        hasHandledZoneWindowRequest = true
        return false
    }

    private func notificationTargetsCurrentWindow(_ notification: Notification) -> Bool {
        guard let targetModel = notification.object as? AppModel else {
            return true
        }
        return targetModel === model
    }

    private func copyZoneName(_ zone: ProviderZone) {
        lockController.registerUserActivity()
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(zone.name, forType: .string)
        #else
        UIPasteboard.general.string = zone.name
        #endif
    }

    private func deleteSelectedZone() {
        guard let zone = zoneToDelete else { return }
        zoneToDelete = nil

        Task {
            do {
                try await model.deleteZone(zone)
            } catch {
                model.errorHandler.handle(error)
            }
        }
    }

    #if os(macOS)
    private func openZoneInNewWindow(_ zone: ProviderZone) {
        lockController.registerUserActivity()
        openWindow(id: ZoneWindowRequest.sceneID, value: ZoneWindowRequest(zone: zone))
    }
    #endif
}
