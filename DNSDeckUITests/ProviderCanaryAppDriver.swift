import CoreGraphics
import XCTest

final class ProviderCanaryAppDriver {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    @discardableResult
    func connect(
        _ configuration: ProviderCanaryConfiguration,
        keepSettingsOpen: Bool = false,
        waitForZone: Bool = true
    ) -> Bool {
        guard openProviderSettings() else { return false }

        let providerID = configuration.definition.providerID
        let providerButton = button("provider.\(providerID).connect")
        guard revealProviderButton(providerButton) else { return false }
        providerButton.click()

        for field in configuration.definition.credentialFields {
            guard let value = configuration.credentials[field.id], !value.isEmpty else {
                continue
            }
            let identifier = "provider.\(providerID).credential.\(field.id)"
            let input: XCUIElement
            let verifyValue: Bool
            switch field.kind {
            case .text:
                input = app.textFields.matching(identifier: identifier).firstMatch
                verifyValue = true
            case .secret:
                input = app.secureTextFields.matching(identifier: identifier).firstMatch
                verifyValue = false
            }
            guard enterCredential(
                value,
                in: input,
                providerID: providerID,
                verifyValue: verifyValue
            ) else {
                return false
            }
        }

        click(button("provider.\(providerID).save"))
        if let message = providerErrorAlertMessage() {
            XCTFail("\(configuration.definition.displayName) connection failed: \(message)")
            return false
        }
        guard providerButton.waitForExistence(timeout: 30) else {
            XCTFail("\(configuration.definition.displayName) did not finish connecting.")
            return false
        }

        if !keepSettingsOpen {
            closeSettingsWindow()
        }
        if waitForZone {
            return revealZone(named: configuration.zoneName, timeout: 60) != nil
        }
        return true
    }

    @discardableResult
    func disconnect(
        _ definition: ProviderCanaryDefinition,
        keepSettingsOpen: Bool = false
    ) -> Bool {
        guard openProviderSettings() else { return false }

        let providerID = definition.providerID
        let providerButton = button("provider.\(providerID).connect")
        guard revealProviderButton(providerButton) else { return false }
        providerButton.click()

        let disconnectButton = button("provider.\(providerID).disconnect")
        guard disconnectButton.waitForExistence(timeout: 10) else {
            XCTFail("\(definition.displayName) did not expose its disconnect action.")
            return false
        }
        disconnectButton.click()
        click(button("provider.\(providerID).confirmDisconnect"))

        guard providerButton.waitForExistence(timeout: 15) else {
            XCTFail("\(definition.displayName) did not finish disconnecting.")
            return false
        }
        if !keepSettingsOpen {
            closeSettingsWindow()
        }
        return true
    }

    @discardableResult
    func openProviderSettings() -> Bool {
        activateApp()
        if settingsWindow.waitForExistence(timeout: 0.5) {
            selectProviderSettingsSection()
            return true
        }

        let manageButton = button("providers.manage")
        if manageButton.waitForExistence(timeout: 2) {
            manageButton.click()
        } else {
            let connectButton = app.buttons["Connect a Provider"]
            guard connectButton.waitForExistence(timeout: 10) else {
                XCTFail("DNSDeck did not expose provider settings.")
                return false
            }
            connectButton.click()
        }

        guard settingsWindow.waitForExistence(timeout: 10) else {
            XCTFail("The settings window did not open.")
            return false
        }
        selectProviderSettingsSection()
        return true
    }

    func closeSettingsWindow() {
        guard settingsWindow.exists else { return }
        activateApp()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(
            settingsWindow.waitForNonExistence(timeout: 10),
            "The settings window did not close."
        )
    }

    private func selectProviderSettingsSection() {
        let sectionElement = element("settings.section.providers")
        XCTAssertTrue(
            sectionElement.waitForExistence(timeout: 10),
            "The providers settings section did not appear."
        )
        sectionElement.click()
        XCTAssertTrue(
            element("settings.detail.providers").waitForExistence(timeout: 10),
            "The providers settings detail did not appear."
        )
    }

    @discardableResult
    func openZone(named zoneName: String, timeout: TimeInterval = 60) -> Bool {
        guard let zone = revealZone(named: zoneName, timeout: timeout) else { return false }
        zone.click()
        XCTAssertTrue(
            button("record.add").waitForExistence(timeout: 30),
            "\(zoneName) did not open its records view."
        )
        return button("record.add").exists
    }

    func revealZone(named zoneName: String, timeout: TimeInterval) -> XCUIElement? {
        activateApp()
        let zone = element("zone.row.\(zoneName)")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if zone.exists, zone.isHittable {
                return zone
            }
            if let list = zoneList {
                list.scroll(byDeltaX: 0, deltaY: -300)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        if let list = zoneList {
            for _ in 0 ..< 30 {
                list.scroll(byDeltaX: 0, deltaY: 300)
                if zone.exists, zone.isHittable {
                    return zone
                }
            }
        }
        XCTFail("The expected zone did not appear: \(zoneName)")
        return nil
    }

    func refreshZones(expectedZoneNames: [String]) {
        let refreshButton = button("zone.refresh")
        clickWhenEnabled(refreshButton, timeout: 30)
        for zoneName in expectedZoneNames {
            XCTAssertNotNil(
                revealZone(named: zoneName, timeout: 60),
                "\(zoneName) disappeared after refreshing zones."
            )
        }
    }

    func copyZoneName(_ zoneName: String) -> String? {
        guard let zone = revealZone(named: zoneName, timeout: 60) else { return nil }
        return ProviderUITestPasteboard.capturedString {
            zone.rightClick()
            let copyItem = app.menuItems
                .matching(identifier: "zone.context.copyName")
                .firstMatch
            if copyItem.waitForExistence(timeout: 2) {
                copyItem.click()
            } else {
                app.menuItems["Copy Zone Name"].click()
            }
        }
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func button(_ identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).firstMatch
    }

    func click(_ element: XCUIElement, timeout: TimeInterval = 10) {
        activateApp()
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing UI element: \(element)")
        element.click()
    }

    func clickWhenEnabled(_ element: XCUIElement, timeout: TimeInterval = 10) {
        activateApp()
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing UI element: \(element)")
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: timeout), .completed)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    func activateApp() {
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    private var settingsWindow: XCUIElement {
        app.windows["settings"]
    }

    private var zoneList: XCUIElement? {
        app.windows.firstMatch.scrollViews.allElementsBoundByIndex
            .filter { $0.exists && $0.frame.width > 180 && $0.frame.width < 420 }
            .max { $0.frame.minX < $1.frame.minX }
    }

    private func enterCredential(
        _ value: String,
        in field: XCUIElement,
        providerID: String,
        verifyValue: Bool
    ) -> Bool {
        activateApp()
        guard field.waitForExistence(timeout: 10) else {
            XCTFail("Missing \(providerID) credential field.")
            return false
        }

        let form = element("provider.\(providerID).credentials")
        guard form.waitForExistence(timeout: 5) else {
            XCTFail("The \(providerID) credential form did not appear.")
            return false
        }

        let visibleFormFrame = form.frame.insetBy(dx: 8, dy: 8)
        for _ in 0 ..< 8 where !credentialFieldIsVisible(field, in: form) {
            let deltaY: CGFloat = field.frame.midY < visibleFormFrame.minY ? 180 : -180
            form.scroll(byDeltaX: 0, deltaY: deltaY)
        }

        guard credentialFieldIsVisible(field, in: form) else {
            XCTFail("A \(providerID) credential field never became hittable.")
            return false
        }

        field.click()
        field.typeKey("a", modifierFlags: .command)
        ProviderUITestCredentialEntry.paste(value, into: field)
        let enteredValue = field.value as? String ?? ""
        guard !enteredValue.isEmpty else {
            XCTFail("Credential paste left the \(providerID) field empty.")
            return false
        }
        if verifyValue, enteredValue != value {
            XCTFail("Credential input was altered or entered in a different \(providerID) field.")
            return false
        }
        return true
    }

    private func credentialFieldIsVisible(_ field: XCUIElement, in form: XCUIElement) -> Bool {
        form.frame.insetBy(dx: 8, dy: 8)
            .contains(CGPoint(x: field.frame.midX, y: field.frame.midY)) && field.isHittable
    }

    private func revealProviderButton(_ providerButton: XCUIElement) -> Bool {
        activateApp()
        if providerButton.waitForExistence(timeout: 1), providerButton.isHittable {
            return true
        }

        guard settingsWindow.waitForExistence(timeout: 5) else {
            XCTFail("The provider settings list did not appear.")
            return false
        }
        let providerList = settingsWindow.scrollViews.allElementsBoundByIndex
            .filter(\.exists)
            .max { $0.frame.width < $1.frame.width }
        guard let providerList else {
            XCTFail("The provider settings list did not expose a scroll view.")
            return false
        }

        for _ in 0 ..< 14 {
            providerList.scroll(byDeltaX: 0, deltaY: 300)
        }
        for _ in 0 ..< 28 {
            if providerButton.waitForExistence(timeout: 0.5), providerButton.isHittable {
                return true
            }
            providerList.scroll(byDeltaX: 0, deltaY: -250)
        }

        XCTFail("The requested provider did not become visible in settings.")
        return false
    }

    private func providerErrorAlertMessage() -> String? {
        let alert = app.alerts["Error"]
        guard alert.waitForExistence(timeout: 0.5) else { return nil }
        return alert.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty && $0 != "Error" }
            .joined(separator: " ")
    }
}
