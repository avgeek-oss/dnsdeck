import AvgeekLocalizationCore
import AvgeekLocalizationUI
import SwiftUI

enum PreferencesSection: String, CaseIterable, Identifiable {
    case general
    case languageTime
    case providers
    case mcp
    case cache
    case security
    case about

    var id: String {
        rawValue
    }

    func title(localizedBy localize: AppLocalizationResolver) -> String {
        switch self {
        case .general: localize("Display")
        case .languageTime: localize("Language & Time")
        case .providers: localize("Providers")
        case .mcp: localize("MCP")
        case .cache: localize("Cache")
        case .security: localize("Security")
        case .about: localize("About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "display"
        case .languageTime: "globe"
        case .providers: "antenna.radiowaves.left.and.right"
        case .mcp: "terminal"
        case .cache: "clock"
        case .security: "lock.shield"
        case .about: "info.circle"
        }
    }
}

enum SettingsRoute {
    static var selectedSectionKey: String {
        UITestConfiguration.storageKey("dnsdeck.settings.selectedSection")
    }

    static var providerEnvironmentKey: String {
        UITestConfiguration.storageKey("dnsdeck.settings.providerEnvironment")
    }

    static func resolvedEnvironmentID(
        preferredID: String,
        environments: [DNSEnvironment],
        selectedEnvironment: DNSEnvironment?
    ) -> UUID? {
        if let preferredID = UUID(uuidString: preferredID),
           environments.contains(where: { $0.id == preferredID })
        {
            return preferredID
        }
        if let selectedEnvironment,
           environments.contains(where: { $0.id == selectedEnvironment.id })
        {
            return selectedEnvironment.id
        }
        return environments.first?.id
    }
}

#if os(macOS)
enum SettingsWindowScene {
    static let sceneID = "settings"
}
#endif

struct SettingsNavigationHistory {
    private(set) var backStack: [PreferencesSection] = []
    private(set) var forwardStack: [PreferencesSection] = []

    var canGoBack: Bool {
        !backStack.isEmpty
    }

    var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    mutating func recordTransition(from previous: PreferencesSection, to next: PreferencesSection) {
        guard previous != next else { return }
        backStack.append(previous)
        forwardStack.removeAll()
    }

    mutating func goBack(from current: PreferencesSection) -> PreferencesSection? {
        guard let destination = backStack.popLast() else { return nil }
        forwardStack.append(current)
        return destination
    }

    mutating func goForward(from current: PreferencesSection) -> PreferencesSection? {
        guard let destination = forwardStack.popLast() else { return nil }
        backStack.append(current)
        return destination
    }
}

#if os(macOS)
struct SettingsSceneRootView: View {
    @StateObject private var model: AppModel
    @ObservedObject private var lockController: AppLockController
    @ObservedObject private var settingsManager: SettingsManager

    init(lockController: AppLockController, settingsManager: SettingsManager) {
        _model = StateObject(wrappedValue: AppModel(lockController: lockController, selectsInitialEnvironment: false))
        _lockController = ObservedObject(wrappedValue: lockController)
        _settingsManager = ObservedObject(wrappedValue: settingsManager)
    }

    var body: some View {
        PreferencesView()
            .environmentObject(model)
            .environmentObject(lockController)
            .environmentObject(settingsManager)
            .id(lockController.isLocked)
            .disabled(lockController.isLocked)
    }
}
#endif

struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var lockController: AppLockController
    @AppLocalized private var localize
    @AppStorage(SettingsRoute.selectedSectionKey) private var selectedSectionRawValue = PreferencesSection.general
        .rawValue
    #if os(macOS)
    @State private var navigationHistory = SettingsNavigationHistory()
    @State private var ignoresNextHistoryUpdate = false
    #endif
    #if os(iOS)
    @State private var path: [PreferencesSection] = []
    #endif

    private var selectedSection: PreferencesSection {
        PreferencesSection(rawValue: selectedSectionRawValue) ?? .general
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selectedSectionRawValue) {
                ForEach(PreferencesSection.allCases) { section in
                    Label(section.title(localizedBy: localize), systemImage: section.symbolName)
                        .accessibilityIdentifier("settings.section.\(section.rawValue)")
                        .tag(section.rawValue)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(188)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            settingsDetail(for: selectedSection)
                .navigationTitle(selectedSection.title(localizedBy: localize))
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button {
                            navigateBack()
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityIdentifier("settings.navigation.back")
                        .disabled(!navigationHistory.canGoBack)
                        .help("Go Back")

                        Button {
                            navigateForward()
                        } label: {
                            Image(systemName: "chevron.forward")
                        }
                        .accessibilityIdentifier("settings.navigation.forward")
                        .disabled(!navigationHistory.canGoForward)
                        .help("Go Forward")
                    }
                }
        }
        .toolbar(removing: .sidebarToggle)
        .onChange(of: selectedSectionRawValue) { oldValue, newValue in
            guard !ignoresNextHistoryUpdate else {
                ignoresNextHistoryUpdate = false
                return
            }
            guard let previous = PreferencesSection(rawValue: oldValue),
                  let next = PreferencesSection(rawValue: newValue)
            else { return }
            navigationHistory.recordTransition(from: previous, to: next)
        }
        .frame(minWidth: 700, minHeight: 458)
        #else
        NavigationStack(path: $path) {
            List(PreferencesSection.allCases) { section in
                NavigationLink(value: section) {
                    Label(section.title(localizedBy: localize), systemImage: section.symbolName)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: PreferencesSection.self) { section in
                settingsDetail(for: section)
                    .navigationTitle(section.title(localizedBy: localize))
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard selectedSection != .general else { return }
                path = [selectedSection]
            }
            .onChange(of: path) { _, newPath in
                selectedSectionRawValue = newPath.last?.rawValue ?? PreferencesSection.general.rawValue
            }
        }
        #endif
    }

    #if os(macOS)
    private func navigateBack() {
        guard let destination = navigationHistory.goBack(from: selectedSection) else { return }
        ignoresNextHistoryUpdate = true
        selectedSectionRawValue = destination.rawValue
    }

    private func navigateForward() {
        guard let destination = navigationHistory.goForward(from: selectedSection) else { return }
        ignoresNextHistoryUpdate = true
        selectedSectionRawValue = destination.rawValue
    }
    #endif

    private func settingsDetail(for section: PreferencesSection) -> some View {
        Group {
            switch section {
            case .general:
                DisplaySettingsView(lockController: lockController)
            case .languageTime:
                LanguageTimeSettingsView(lockController: lockController)
            case .providers:
                ProviderSettingsView()
                    .environmentObject(model)
            case .mcp:
                MCPSettingsView(lockController: lockController)
            case .cache:
                CacheTab(lockController: lockController)
            case .security:
                SecurityTab(lockController: lockController)
            case .about:
                AboutTab()
            }
        }
        .accessibilityIdentifier("settings.detail.\(section.rawValue)")
    }
}

enum MCPSettings {
    static let executableName = "DNSDeckMCP"

    #if os(macOS)
    static var commandPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
            .path
    }

    static var isCommandAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: commandPath)
    }

    static var postmanJSONConfiguration: String {
        prettyJSON(["command": commandPath])
    }

    static var claudeDesktopJSONConfiguration: String {
        prettyJSON([
            "mcpServers": [
                "dnsdeck": [
                    "command": commandPath,
                ],
            ],
        ])
    }

    static var codexTOMLConfiguration: String {
        """
        [mcp_servers.dnsdeck]
        command = "\(commandPath)"
        """
    }

    static var vsCodeJSONConfiguration: String {
        prettyJSON([
            "servers": [
                "dnsdeck": [
                    "command": commandPath,
                ],
            ],
        ])
    }

    static var cursorJSONConfiguration: String {
        prettyJSON([
            "mcpServers": [
                "dnsdeck": [
                    "command": commandPath,
                ],
            ],
        ])
    }

    private static func prettyJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string.replacingOccurrences(of: "\\/", with: "/")
    }
    #endif
}

struct MCPSettingsView: View {
    enum CopiedItem: String {
        case postman
        case claude
        case codex
        case vsCode
        case cursor
        case command
    }

    enum MCPDestination: String, CaseIterable, Identifiable {
        case postman
        case claudeDesktop
        case codex
        case vsCode
        case cursor
        case advanced

        var id: String {
            rawValue
        }

        private var text: (
            title: String.LocalizationValue,
            sectionTitle: String.LocalizationValue,
            instructions: String.LocalizationValue
        ) {
            switch self {
            case .postman:
                (
                    "Postman",
                    "Connect to Postman",
                    "Create an MCP request in Postman, choose STDIO, then paste this JSON configuration."
                )
            case .claudeDesktop:
                (
                    "Claude Desktop",
                    "Connect to Claude Desktop",
                    "Add DNSDeck to Claude Desktop's MCP server configuration."
                )
            case .codex:
                ("Codex", "Connect to Codex", "Add this server entry to your Codex config.toml.")
            case .vsCode:
                ("VS Code", "Connect to VS Code", "Add this server entry to your VS Code MCP configuration.")
            case .cursor:
                ("Cursor", "Connect to Cursor", "Add this server entry to your Cursor MCP configuration.")
            case .advanced:
                (
                    "Advanced",
                    "Advanced",
                    "MCP DNS changes use the environments and providers already configured in DNSDeck. Nameserver updates and delete operations require explicit confirmation, and mutations are written to the local MCP audit log."
                )
            }
        }

        func title(localizedBy localize: AppLocalizationResolver) -> String {
            localize(text.title)
        }

        func sectionTitle(localizedBy localize: AppLocalizationResolver) -> String {
            localize(text.sectionTitle)
        }

        func instructions(localizedBy localize: AppLocalizationResolver) -> String {
            localize(text.instructions)
        }

        #if os(macOS)
        private var integration: (
            configuration: String,
            copyTitle: String.LocalizationValue,
            copiedItem: CopiedItem
        ) {
            switch self {
            case .postman:
                (MCPSettings.postmanJSONConfiguration, "Copy Postman JSON", .postman)
            case .claudeDesktop:
                (MCPSettings.claudeDesktopJSONConfiguration, "Copy Claude Config", .claude)
            case .codex:
                (MCPSettings.codexTOMLConfiguration, "Copy Codex Config", .codex)
            case .vsCode:
                (MCPSettings.vsCodeJSONConfiguration, "Copy VS Code JSON", .vsCode)
            case .cursor:
                (MCPSettings.cursorJSONConfiguration, "Copy Cursor JSON", .cursor)
            case .advanced:
                (MCPSettings.commandPath, "Copy Command", .command)
            }
        }

        var configuration: String {
            integration.configuration
        }

        var copyTitle: String.LocalizationValue {
            integration.copyTitle
        }

        var copiedItem: CopiedItem {
            integration.copiedItem
        }
        #endif
    }

    @ObservedObject var lockController: AppLockController
    @AppLocalized private var localize
    @AppStorage(UITestConfiguration.storageKey("dnsdeck.mcp.destination"))
    private var selectedDestinationRawValue = MCPDestination.postman.rawValue
    @State private var copiedItem: CopiedItem?

    private var selectedDestination: MCPDestination {
        MCPDestination(rawValue: selectedDestinationRawValue) ?? .postman
    }

    private var selectedDestinationBinding: Binding<String> {
        Binding {
            selectedDestinationRawValue
        } set: { newValue in
            selectedDestinationRawValue = newValue
            copiedItem = nil
        }
    }

    var body: some View {
        Form {
            #if os(macOS)
            Section("MCP Status") {
                mcpStatusRow
                Text(
                    "DNSDeck includes a local STDIO MCP helper. MCP apps start it when they connect."
                )
                .settingsDescription()
            }

            Section("Destination") {
                Picker("MCP Destination", selection: selectedDestinationBinding) {
                    ForEach(MCPDestination.allCases) { destination in
                        Text(destination.title(localizedBy: localize))
                            .tag(destination.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.mcp.destination")

                Text("Choose the app you want to connect. DNSDeck will show only the setup details for that app.")
                    .settingsDescription()
            }

            Section(selectedDestination.sectionTitle(localizedBy: localize)) {
                Text(selectedDestination.instructions(localizedBy: localize))
                    .settingsDescription()

                if selectedDestination == .advanced {
                    LabeledContent("Transport", value: "STDIO")
                    LabeledContent("URL", value: "None")
                }

                configurationText(selectedDestination.configuration)
                destinationActions(for: selectedDestination)
            }
            #else
            Section("Mac Required") {
                Text(
                    "Local MCP clients launch STDIO tools on macOS. DNSDeck for iPhone and iPad can manage DNS directly, but iOS cannot host a local MCP companion process."
                )
                .settingsDescription()
            }
            #endif
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(lockController.isLocked)
    }

    #if os(macOS)
    private var mcpStatusRow: some View {
        HStack {
            Label("DNSDeck MCP", systemImage: "terminal")
                .font(.body.weight(.medium))

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(MCPSettings.isCommandAvailable ? .green : .secondary)
                    .font(.system(size: 6))
                    .accessibilityLabel(MCPSettings.isCommandAvailable ? "Ready" : "Unavailable")
                Text(MCPSettings.isCommandAvailable ? "Ready" : "Unavailable")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func configurationText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func destinationActions(for destination: MCPDestination) -> some View {
        if destination == .advanced {
            HStack {
                copyButton(item: destination.copiedItem, title: destination.copyTitle, value: destination.configuration)

                Button {
                    revealCommand()
                } label: {
                    Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
                }
                .disabled(!MCPSettings.isCommandAvailable)
            }
        } else {
            copyButton(item: destination.copiedItem, title: destination.copyTitle, value: destination.configuration)
        }
    }

    private func copyButton(item: CopiedItem, title: String.LocalizationValue, value: String) -> some View {
        Button {
            copyToClipboard(value)
            copiedItem = item
            resetCopiedItem(item)
        } label: {
            Label(
                copiedItem == item ? localize("Copied") : localize(title),
                systemImage: copiedItem == item ? "checkmark" : "doc.on.doc"
            )
        }
        .accessibilityIdentifier("settings.mcp.copy.\(item.rawValue)")
    }

    private func resetCopiedItem(_ item: CopiedItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard copiedItem == item else { return }
            copiedItem = nil
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func revealCommand() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: MCPSettings.commandPath)])
    }
    #endif
}

struct DisplaySettingsView: View {
    @AppStorage(UITestConfiguration.storageKey("dnsdeck.showRecordBadges")) private var showRecordBadges = true
    @AppStorage(UITestConfiguration.storageKey("dnsdeck.showTTLColumn")) private var showTTLColumn = true
    @AppStorage(UITestConfiguration.storageKey("dnsdeck.showCommentColumn")) private var showCommentColumn = true
    @AppStorage(UITestConfiguration.storageKey("dnsdeck.dimTypeBadges")) private var dimTypeBadges = false
    @AppStorage(UITestConfiguration.storageKey("dnsdeck.wrapTextContent")) private var wrapTextContent = false
    @ObservedObject var lockController: AppLockController

    init(lockController: AppLockController) {
        self.lockController = lockController
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show meta badges", isOn: $showRecordBadges)
                    .accessibilityIdentifier("settings.display.showRecordBadges")
                    .disabled(lockController.isLocked)
                Text(
                    "When enabled, badges (DKIM, DMARC, SPF, etc.) are shown next to record names to help identify important configurations."
                )
                .settingsDescription()

                Toggle("Use monotone badges", isOn: $dimTypeBadges)
                    .accessibilityIdentifier("settings.display.dimTypeBadges")
                    .disabled(lockController.isLocked)
                Text(
                    "When enabled, all badges will use the secondary color for a more subtle appearance instead of color-coded badges."
                )
                .settingsDescription()
            } header: {
                Text("Table Customizations")
            }

            Section {
                Toggle("Show TTL column", isOn: $showTTLColumn)
                    .accessibilityIdentifier("settings.display.showTTLColumn")
                    .disabled(lockController.isLocked)
                Text("When enabled, the Time-To-Live (TTL) column is shown in the records table.")
                    .settingsDescription()

                Toggle("Show comments column", isOn: $showCommentColumn)
                    .accessibilityIdentifier("settings.display.showCommentColumn")
                    .disabled(lockController.isLocked)
                Text("When enabled, the comment column is shown for records whenever applicable.")
                    .settingsDescription()

                Toggle("Wrap text content", isOn: $wrapTextContent)
                    .accessibilityIdentifier("settings.display.wrapTextContent")
                    .disabled(lockController.isLocked)
                Text("When enabled, text content wraps to multiple lines instead of being truncated with ellipsis.")
                    .settingsDescription()
            } header: {
                Text("Table Columns")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(lockController.isLocked)
    }
}

struct LanguageTimeSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @ObservedObject var lockController: AppLockController
    @AppLocalized private var localize

    init(lockController: AppLockController) {
        self.lockController = lockController
    }

    var body: some View {
        Form {
            Section("Language") {
                Picker("Application Language", selection: $settings.appLanguage) {
                    ForEach(SupportedLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
                .accessibilityIdentifier("settings.language.appLanguage")
                .disabled(lockController.isLocked)
            }

            Section {
                Picker("Display format", selection: $settings.dateTimeFormat) {
                    ForEach(DateTimeFormat.allCases) { format in
                        Text(format.displayName(localizedBy: localize)).tag(format)
                    }
                }
                .accessibilityIdentifier("settings.language.dateTimeFormat")
                .disabled(lockController.isLocked)
                Text("Choose how dates and times are displayed in the created and modified columns.")
                    .settingsDescription()
            } header: {
                Text("Date & Time")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(lockController.isLocked)
    }
}

struct SecurityTab: View {
    @ObservedObject var lockController: AppLockController
    @AppLocalized private var localize
    @AppStorage(UITestConfiguration.storageKey("dnsdeck.maskContentColumn")) private var maskContentColumn = false

    var body: some View {
        Form {
            Section {
                Toggle("Mask record values", isOn: $maskContentColumn)
                    .accessibilityIdentifier("settings.security.maskContent")
                    .disabled(lockController.isLocked)
                Text(
                    "When enabled, record content is masked for privacy. You can still copy the actual content using the context menu."
                )
                .settingsDescription()
            } header: {
                Text("Privacy")
            }

            Section {
                Picker("Auto-Lock", selection: $lockController.timeout) {
                    ForEach(AppLockController.Timeout.allCases) { option in
                        Text(option.displayName(localizedBy: localize)).tag(option)
                    }
                }
                .accessibilityIdentifier("settings.security.autoLock")
                .disabled(lockController.isLocked)

                Text(
                    "When enabled, DNSDeck automatically locks after the selected time away. On devices with Face ID or Touch ID you'll unlock with biometrics; on others you'll use your device password."
                )
                .settingsDescription()
            } header: {
                Text("App Lock")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(lockController.isLocked)
    }
}

struct CacheTab: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var cacheManager = CacheManager.shared
    @ObservedObject var lockController: AppLockController

    init(lockController: AppLockController) {
        self.lockController = lockController
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Caching", isOn: $settings.enableCache)
                    .accessibilityIdentifier("settings.cache.enabled")
                    .disabled(lockController.isLocked)
                Text("Cache zones and records locally to reduce API calls and improve performance")
                    .settingsDescription()
            }

            if settings.enableCache {
                Section("Cache Duration") {
                    cacheDurationPicker(
                        "Zones cache",
                        identifier: "settings.cache.zonesTTL",
                        selection: $settings.zonesCacheTTL
                    )
                    cacheDurationPicker(
                        "Records cache",
                        identifier: "settings.cache.recordsTTL",
                        selection: $settings.recordsCacheTTL
                    )
                }

                Section {
                    Button("Clear All Cache") {
                        cacheManager.clearAll()
                    }
                    .accessibilityIdentifier("settings.cache.clear")
                    .foregroundColor(.red)
                    .disabled(lockController.isLocked)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(lockController.isLocked)
    }

    private func cacheDurationPicker(
        _ title: LocalizedStringResource,
        identifier: String,
        selection: Binding<TimeInterval>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: selection) {
                ForEach(Self.cacheDurations, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(identifier)
            .disabled(lockController.isLocked)
        }
    }

    private static let cacheDurations: [(title: LocalizedStringResource, value: TimeInterval)] = [
        ("1 minute", 60), ("2 minutes", 120), ("5 minutes", 300), ("15 minutes", 900),
        ("30 minutes", 1800), ("1 hour", 3600), ("2 hours", 7200), ("3 hours", 10800),
        ("6 hours", 21600), ("12 hours", 43200), ("24 hours", 86400),
    ]
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 8) {
            #if os(macOS)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            #else
            Image(systemName: "app.fill")
                .font(.system(size: 48))
                .foregroundStyle(.accent)
            #endif

            VStack(spacing: 4) {
                Text("DNSDeck")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                {
                    Text("Version \(version) (\(build))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: {
                    if let url = URL(string: Configuration.Support.mailtoFeedback) {
                        #if os(macOS)
                        if UITestConfiguration.isEnabled {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        } else {
                            NSWorkspace.shared.open(url)
                        }
                        #else
                        if UITestConfiguration.isEnabled {
                            UIPasteboard.general.string = url.absoluteString
                        } else {
                            UIApplication.shared.open(url)
                        }
                        #endif
                    }
                }) {
                    HStack {
                        Image(systemName: "envelope")
                        Text("Provide Feedback")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

private extension View {
    func settingsDescription() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
