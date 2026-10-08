import SwiftUI

#if os(macOS)
struct DNSDeckSettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: SettingsWindowScene.sceneID)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
#endif
#if os(macOS)
import Cocoa

struct DNSDeckCommands: Commands {
    @FocusedObject private var model: AppModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // Intentionally empty to override the default "New" item behaviour.
        }

        CommandMenu("Environment") {
            Button("New Environment") {
                guard let model else { return }
                model.lockController.registerUserActivity()
                NotificationCenter.default.post(name: .showNewEnvironmentSheet, object: model)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(model == nil || model?.lockController.isLocked == true)

            Button("Rename Environment") {
                guard let model else { return }
                model.lockController.registerUserActivity()
                NotificationCenter.default.post(name: .showEditEnvironmentSheet, object: model)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model?.environmentManager.environments.isEmpty != false || model?.lockController.isLocked == true)
        }

        SidebarCommands()

        CommandMenu("Security") {
            Button("Lock DNSDeck") {
                guard let model else { return }
                model.lockController.registerUserActivity()
                model.lockController.triggerManualLock()
            }
            .keyboardShortcut("l", modifiers: [.command])
            .disabled(model == nil || model?.lockController.isLocked == true)
        }

        CommandMenu("Zone") {
            Button("Add Record") {
                guard let model else { return }
                model.lockController.registerUserActivity()
                NotificationCenter.default.post(name: .addRecord, object: model)
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(model?.selectedZone == nil || model?.lockController.isLocked == true)

            Button("Reload Zone") {
                guard let model else { return }
                model.lockController.registerUserActivity()
                NotificationCenter.default.post(name: .reloadZone, object: model)
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model?.selectedZone == nil || model?.lockController.isLocked == true)
        }

        CommandGroup(replacing: .help) {
            Button("Need assistance?") {
                if let url = URL(string: Configuration.Support.mailtoAssistance) {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("?", modifiers: [.command])

            Button("Provide Feedback") {
                if let url = URL(string: Configuration.Support.mailtoFeedback) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
#endif
