

import AvgeekLocalizationUI
import Combine
import SwiftUI
#if os(macOS)
import Cocoa
#endif

@main
struct DNSDeckApp: App {
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var lockController = AppLockController.shared

    init() {
        UITestConfiguration.prepareForLaunch()
    }

    var body: some Scene {
        WindowGroup {
            LocalizedSceneContent(languageController: settingsManager.languageController) {
                AppWindowRootView(
                    lockController: lockController,
                    settingsManager: settingsManager
                )
                #if os(macOS)
                .frame(minWidth: Constants.UI.minimumWindowWidth, minHeight: Constants.UI.minimumWindowHeight)
                #endif
            }
            #if os(macOS)
            .modifier(WindowMenuSyncModifier())
            .onAppear {
                guard UITestConfiguration.isEnabled else { return }
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
                NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(
            width: Constants.UI.defaultWindowWidth,
            height: Constants.UI.defaultWindowHeight
        )
        #endif

        #if os(macOS)
        WindowGroup(id: ZoneWindowRequest.sceneID, for: ZoneWindowRequest.self) { request in
            LocalizedSceneContent(languageController: settingsManager.languageController) {
                AppWindowRootView(
                    lockController: lockController,
                    settingsManager: settingsManager,
                    zoneWindowRequest: request.wrappedValue
                )
                .frame(minWidth: Constants.UI.minimumWindowWidth, minHeight: Constants.UI.minimumWindowHeight)
            }
            .modifier(WindowMenuSyncModifier())
        } defaultValue: {
            ZoneWindowRequest.placeholder
        }
        .defaultSize(
            width: Constants.UI.defaultWindowWidth,
            height: Constants.UI.defaultWindowHeight
        )
        .commands {
            DNSDeckCommands()
        }

        Window("DNSDeck Settings", id: SettingsWindowScene.sceneID) {
            LocalizedSceneContent(languageController: settingsManager.languageController) {
                SettingsSceneRootView(
                    lockController: lockController,
                    settingsManager: settingsManager
                )
            }
        }
        .defaultSize(width: 710, height: 458)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            DNSDeckSettingsCommands()
        }
        #endif
    }
}

#if os(macOS)
private struct WindowMenuSyncModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                NSApp.mainMenu?.update()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("DNSLockStateChanged"))) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.mainMenu?.update()
                    NSApp.windows.forEach { $0.invalidateRestorableState() }
                    NSApp.mainMenu?.items.forEach { $0.menu?.update() }
                }
            }
    }
}
#endif
