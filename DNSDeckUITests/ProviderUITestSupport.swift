import AppKit
import XCTest

enum ProviderUITestApplication {
    static func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DNSDECK_UI_TESTING"] = "1"
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-NSQuitAlwaysKeepsWindows", "NO",
        ]
        app.launch()
        return app
    }
}

enum ProviderUITestCredentialEntry {
    static func paste(_ value: String, into field: XCUIElement) {
        ProviderUITestPasteboard.restoringContents {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            field.typeKey("v", modifierFlags: .command)
        }
    }
}

enum ProviderUITestPasteboard {
    static func capturedString(after action: () -> Void) -> String? {
        restoringContents {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            action()
            return pasteboard.string(forType: .string)
        }
    }

    static func restoringContents<Result>(_ action: () throws -> Result) rethrows -> Result {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        defer { snapshot.restore(to: pasteboard) }
        return try action()
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            )
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
