import CoreGraphics
import Foundation
import OSLog
import XCTest

class ProviderCanaryTestCase: XCTestCase {
    class var definition: ProviderCanaryDefinition {
        preconditionFailure("Concrete provider canaries must supply a definition.")
    }

    private var app: XCUIApplication!
    private var appDriver: ProviderCanaryAppDriver!
    private var configuration: ProviderCanaryConfiguration!
    private var backend: (any ProviderCanaryBackend)!
    private var staleRecordsRemoved = 0
    private let phaseLogger = Logger(
        subsystem: "dev.dnsdeck.DNSDeckUITests",
        category: "ProviderCanary"
    )

    override func setUp() async throws {
        continueAfterFailure = false

        let environment = ProcessInfo.processInfo.environment
        let definition = Self.definition
        let fixture = try await ProviderFixtureStore.fixture(for: definition.fixtureName)
        let runPrefix = Self.testRecordPrefix(buildID: environment["CI_BUILD_ID"], now: Date())
        configuration = try ProviderCanaryConfiguration(
            definition: definition,
            fixture: fixture,
            runPrefix: runPrefix
        )
        backend = try ProviderCanaryBackendFactory.make(configuration: configuration)
        staleRecordsRemoved = try await backend.deleteStaleRecords(
            olderThan: Date().addingTimeInterval(-3600)
        )
        addTeardownBlock { [backend] in
            _ = try await backend.deleteRunRecordsIfPresent()
        }
        try await backend.prepareRunRecords()

        app = ProviderUITestApplication.launch()
        appDriver = ProviderCanaryAppDriver(app: app)
    }

    override func tearDownWithError() throws {
        if testRun?.failureCount ?? 0 > 0, let app {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(Self.definition.displayName) failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app?.terminate()
        try super.tearDownWithError()
    }

    func runProviderCanary() async throws {
        let startedAt = Date()
        let providerConnected = perform("Connect \(configuration.definition.displayName)") {
            connectProvider()
        }
        guard providerConnected else { return }
        perform("Open fixture zone") {
            openFixtureZone()
        }
        if configuration.definition.profile == .comprehensive {
            perform("Use zone info and refresh toolbar actions") {
                exerciseZoneToolbar()
            }
            let importEditorClosed = perform("Open the inline import editor from the toolbar") {
                exerciseInlineImportToolbar()
            }
            guard importEditorClosed else { return }
        }
        let recordsCreated = perform("Create profile TXT records") {
            createProfileRecords()
        }
        guard recordsCreated else { return }
        let importFileURL = try configuration.writeCSVImportFixture()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: importFileURL)
        }
        let fileImported = perform("Import the \(configuration.definition.profile.rawValue) CSV fixture") {
            importRecordTypesFromCSV(importFileURL)
        }
        guard fileImported else { return }
        perform("Verify the profile record types in the records table") {
            verifyAllRecordTypesInUI()
        }
        phaseLogger.notice("Starting provider API verification")
        let liveRecords = try await backend.runRecords()
        verifyAllRecordTypesInProvider(liveRecords)
        phaseLogger.notice("Finished provider API verification")
        perform("Search records by name and content") {
            exerciseSearch()
        }
        perform("Copy and edit from the record context menu") {
            exerciseSingleRecordContextMenu(
                verifiesClipboard: configuration.definition.profile == .comprehensive
            )
        }
        try await verifyContextMenuEditInProvider()
        perform("Verify the context-menu edit refreshed in the records table") {
            assertRecord(configuration.primaryRecord, content: configuration.primaryRecord.editedContent)
        }
        if configuration.definition.profile == .comprehensive {
            perform("Use selection toolbar and keyboard shortcuts") {
                exerciseSelectionAndKeyboardShortcuts()
            }
            perform("Bulk replace run-owned record content") {
                bulkReplaceRecordContent()
            }
            perform("Bulk delete from the multi-selection context menu") {
                comprehensiveBulkDeleteRunRecords()
            }
        } else {
            perform("Delete all run-owned records") {
                basicBulkDeleteRunRecords()
            }
        }
        perform("Disconnect \(configuration.definition.displayName)") {
            disconnectProvider()
        }

        phaseLogger.notice("Starting final provider cleanup verification")
        let recordsCleanedAfterUIFlow = try await backend.deleteRunRecordsIfPresent()
        phaseLogger.notice("Finished final provider cleanup verification")
        XCTAssertEqual(recordsCleanedAfterUIFlow, 0, "The UI flow left run-owned records for API cleanup.")
        let cleanupReport = XCTAttachment(
            string: """
            provider=\(configuration.definition.providerID)
            profile=\(configuration.definition.profile.rawValue)
            recordCleanup=verified
            runPrefix=\(configuration.runPrefix)
            recordTypes=\(configuration.expectedRecordTypes.sorted().joined(separator: ","))
            recordTypeCount=\(configuration.expectedRecordTypes.count)
            csvImportedRecords=\(configuration.importedRecords.count)
            recordsCleanedAfterUIFlow=\(recordsCleanedAfterUIFlow)
            staleRecordsRemoved=\(staleRecordsRemoved)
            durationSeconds=\(Int(Date().timeIntervalSince(startedAt)))
            interactions=\(configuration.definition.profile.interactionNames.joined(separator: ","))
            """
        )
        cleanupReport.name = "\(configuration.definition.displayName) cleanup"
        cleanupReport.lifetime = .keepAlways
        add(cleanupReport)
    }

    private func connectProvider() -> Bool {
        appDriver.connect(configuration)
    }

    private func openFixtureZone() {
        XCTAssertTrue(appDriver.openZone(named: configuration.zoneName))
    }

    private func exerciseZoneToolbar() {
        click(button("record.zoneInfo"))
        XCTAssertTrue(element("zone.info").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Zone Name"].exists)
        click(button("record.zoneInfo"))
        XCTAssertTrue(element("zone.info").waitForNonExistence(timeout: 10))

        click(button("record.refresh"))
        XCTAssertTrue(button("record.add").waitForExistence(timeout: 30))

        typeKey("r", modifierFlags: .command)
        XCTAssertTrue(button("record.add").waitForExistence(timeout: 30))
    }

    private func createProfileRecords() -> Bool {
        guard createRecord(configuration.primaryRecord, from: .toolbar) else {
            return false
        }
        guard configuration.definition.profile == .comprehensive else {
            return true
        }
        return createRecord(configuration.secondaryRecord, from: .zoneMenu)
    }

    private func createRecord(_ record: ProviderCanaryRecordFixture, from entryPoint: RecordEntryPoint) -> Bool {
        switch entryPoint {
        case .toolbar:
            click(button("record.add"))
        case .zoneMenu:
            click(app.menuBars.menuBarItems["Zone"])
            click(app.menuItems["Add Record"])
        }

        click(popUpButton("record.form.type"))
        click(app.menuItems["TXT — Text record"])
        replaceText(in: textField("record.form.name"), with: record.relativeName)
        replaceRecordFormContent(with: record.initialContent)
        clickWhenEnabled(button("record.form.submit"))
        let formClosed = button("record.form.submit").waitForNonExistence(timeout: 30)
        if let message = providerErrorAlertMessage() {
            XCTFail(
                "\(configuration.definition.displayName) rejected record creation for " +
                    "\(record.relativeName): \(message)"
            )
            return false
        }
        guard formClosed else {
            XCTFail(
                "\(configuration.definition.displayName) did not finish creating record " +
                    "\(record.relativeName)."
            )
            return false
        }
        guard recordElement(record).waitForExistence(timeout: 30),
              contentElement(record).waitForExistence(timeout: 30),
              displayedText(of: contentElement(record)) == record.initialContent
        else {
            XCTFail(
                "\(configuration.definition.displayName) did not show the created record " +
                    "\(record.relativeName)."
            )
            return false
        }
        return true
    }

    private func exerciseInlineImportToolbar() -> Bool {
        click(button("record.import"))
        guard app.staticTexts["Import Records"].waitForExistence(timeout: 10) else {
            XCTFail("The import sheet did not open.")
            return false
        }
        click(app.radioButtons["Inline"])
        let recordCount = staticText("record.import.inline.count")
        guard recordCount.waitForExistence(timeout: 10) else {
            XCTFail("The inline import record count did not appear.")
            return false
        }
        XCTAssertEqual(recordCount.value as? String, "0 records")
        click(button("record.import.inline.add"))
        let oneRecord = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1 record"),
            object: recordCount
        )
        guard XCTWaiter.wait(for: [oneRecord], timeout: 10) == .completed else {
            XCTFail("Adding an inline record did not update the editor.")
            return false
        }
        clickCenter(button("record.import.cancel"))
        guard app.staticTexts["Import Records"].waitForNonExistence(timeout: 10) else {
            XCTFail("The import sheet did not close.")
            return false
        }
        return true
    }

    private func importRecordTypesFromCSV(_ fileURL: URL) -> Bool {
        click(button("record.import"))
        guard app.staticTexts["Import Records"].waitForExistence(timeout: 10) else {
            XCTFail("The import sheet did not open for CSV import.")
            return false
        }

        click(button("record.import.file.choose"))
        let openPanel = app.sheets["open-panel"]
        guard openPanel.waitForExistence(timeout: 10) else {
            XCTFail("The CSV file picker did not appear.")
            return false
        }
        app.activate()
        guard app.wait(for: .runningForeground, timeout: 5) else {
            XCTFail("DNSDeck did not regain focus for the CSV file picker.")
            return false
        }
        app.typeText("/")

        let pathTextField = app.textFields["PathTextField"]
        let legacyComboBox = app.comboBoxes.firstMatch
        let locationField: XCUIElement
        if pathTextField.waitForExistence(timeout: 5) {
            locationField = pathTextField
        } else if legacyComboBox.waitForExistence(timeout: 5) {
            locationField = legacyComboBox
        } else {
            XCTFail("The CSV file picker's location field did not appear.")
            return false
        }
        click(locationField)
        locationField.typeKey("a", modifierFlags: .command)
        ProviderUITestCredentialEntry.paste(fileURL.path, into: locationField)
        locationField.typeKey(.return, modifierFlags: [])

        let openButton = app.buttons.matching(identifier: "OKButton").firstMatch
        guard openButton.waitForExistence(timeout: 10) else {
            XCTFail("The CSV file picker did not make the selected file available to open.")
            return false
        }
        click(openButton)

        guard staticText("record.import.file.selected").waitForExistence(timeout: 15),
              element("record.import.preview").waitForExistence(timeout: 15)
        else {
            XCTFail("DNSDeck did not parse and preview the selected CSV file.")
            return false
        }

        let submitButton = button("record.import.submit")
        guard submitButton.waitForExistence(timeout: 10) else {
            XCTFail("The CSV import action did not appear.")
            return false
        }
        XCTAssertEqual(
            submitButton.label,
            "Import \(configuration.importedRecords.count) records"
        )
        clickWhenEnabled(submitButton, timeout: 15)

        let importTitle = app.staticTexts["Import Records"]
        let resultsTitle = app.staticTexts["Bulk import results"]
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if resultsTitle.exists {
                let recordName = app.staticTexts["batch.error.1.recordName"].firstMatch
                let message = app.staticTexts["batch.error.1.message"].firstMatch
                let recordDescription = (recordName.value as? String) ?? recordName.label
                let messageDescription = (message.value as? String) ?? message.label
                XCTFail(
                    "CSV import failed for \(recordDescription): \(messageDescription)"
                )
                return false
            }
            if !importTitle.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("The CSV import did not finish.")
        return false
    }

    private func verifyAllRecordTypesInUI() {
        replaceSearchText(with: configuration.runPrefix)
        for recordType in configuration.expectedRecordTypes.sorted() {
            let typeBadge = app.staticTexts[recordType].firstMatch
            XCTAssertTrue(
                typeBadge.waitForExistence(timeout: 10),
                "The \(recordType) record type did not appear after import."
            )
            XCTAssertEqual(displayedText(of: typeBadge), recordType)
        }
    }

    private func verifyAllRecordTypesInProvider(_ liveRecords: [ProviderCanaryLiveRecord]) {
        let expectedSignatures = configuration.expectedRecords
            .map(\.signature)
            .sorted()
        let actualSignatures = liveRecords
            .map(\.signature)
            .sorted()
        XCTAssertEqual(
            actualSignatures,
            expectedSignatures,
            "\(configuration.definition.displayName) did not persist the expected record matrix."
        )
        XCTAssertTrue(
            liveRecords.allSatisfy {
                !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            "\(configuration.definition.displayName) returned an empty imported record value."
        )

        let recordsBySignature = Dictionary(uniqueKeysWithValues: liveRecords.map { ($0.signature, $0) })
        for fixture in configuration.importedRecords {
            guard let record = recordsBySignature[fixture.signature] else { continue }
            XCTAssertTrue(
                configuration.providerContentMatches(record.content, fixture: fixture),
                "\(configuration.definition.displayName) changed the imported \(fixture.type) value " +
                    "from \(configuration.expectedProviderContent(for: fixture)) to \(record.content)."
            )
            XCTAssertEqual(
                record.ttl,
                fixture.ttl,
                "\(configuration.definition.displayName) changed the imported \(fixture.type) TTL."
            )
            if configuration.definition.supportsComments {
                XCTAssertEqual(record.comment, fixture.comment)
            }
            XCTAssertEqual(
                record.priority,
                configuration.expectedProviderPriority(for: fixture),
                "\(configuration.definition.displayName) changed the imported \(fixture.type) priority."
            )
        }
    }

    private func exerciseSearch() {
        replaceSearchText(with: configuration.primaryRecord.relativeName)
        XCTAssertTrue(recordElement(configuration.primaryRecord).waitForExistence(timeout: 10))
        XCTAssertTrue(recordElement(configuration.secondaryRecord).waitForNonExistence(timeout: 10))

        replaceSearchText(with: configuration.initialContentMarker)
        assertRunRecords(contentState: .initial)

        replaceSearchText(with: "\(configuration.runPrefix)-no-match")
        XCTAssertTrue(element("record.search.empty").waitForExistence(timeout: 10))

        replaceSearchText(with: configuration.runPrefix)
        assertRunRecords(contentState: .initial)
    }

    private func exerciseSingleRecordContextMenu(verifiesClipboard: Bool) {
        let primary = configuration.primaryRecord
        replaceSearchText(with: primary.relativeName)

        if verifiesClipboard {
            let copiedName = ProviderUITestPasteboard.capturedString {
                openContextMenu(for: primary)
                click(contextMenuItem("record.context.copyName", label: "Copy record name"))
            }
            XCTAssertEqual(
                copiedName,
                configuration.recordNamePresentedByApp(primary.fullyQualifiedName)
            )

            let copiedValue = ProviderUITestPasteboard.capturedString {
                openContextMenu(for: primary)
                click(contextMenuItem("record.context.copyValue", label: "Copy record value"))
            }
            XCTAssertEqual(copiedValue, primary.initialContent)
        }

        openContextMenu(for: primary)
        click(contextMenuItem("record.context.edit", label: "Edit"))
        replaceRecordFormContent(with: primary.editedContent)
        clickWhenEnabled(button("record.form.submit"))
    }

    private func verifyContextMenuEditInProvider() async throws {
        let primary = configuration.primaryRecord
        var actualContent: String?
        for attempt in 0 ..< 10 {
            actualContent = try await backend.runRecords()
                .first { $0.signature == primary.expectedRecord.signature }?
                .content
            if actualContent == primary.editedContent {
                return
            }
            guard attempt < 9 else { break }
            try await Task.sleep(for: .seconds(2))
        }
        XCTFail(
            "\(configuration.definition.displayName) did not persist the context-menu edit: " +
                "expected \(primary.editedContent), got \(actualContent ?? "missing record")."
        )
    }

    private func exerciseSelectionAndKeyboardShortcuts() {
        let secondary = configuration.secondaryRecord
        replaceSearchText(with: secondary.relativeName)
        selectRecord(secondary)
        click(button("record.edit"))
        replaceRecordFormContent(with: secondary.editedContent)
        clickWhenEnabled(button("record.form.submit"))
        assertRecord(secondary, content: secondary.editedContent)

        selectRecord(secondary)
        typeKey("e", modifierFlags: .command)
        XCTAssertTrue(button("record.form.submit").waitForExistence(timeout: 10))
        cancelRecordForm()

        selectRecord(secondary)
        typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(button("record.edit").waitForNonExistence(timeout: 10))
        XCTAssertTrue(button("record.delete").waitForNonExistence(timeout: 10))

        typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Add DNS Record"].waitForExistence(timeout: 10))
        cancelRecordForm()
    }

    private func bulkReplaceRecordContent() {
        replaceSearchText(with: configuration.runPrefix)
        click(button("record.bulkReplace"))
        replaceText(in: textField("record.bulkReplace.find"), with: configuration.initialContentMarker)
        replaceText(in: textField("record.bulkReplace.replacement"), with: configuration.updatedContentMarker)
        clickWhenEnabled(button("record.bulkReplace.submit"))

        XCTAssertTrue(button("record.bulkReplace.submit").waitForNonExistence(timeout: 30))
        assertRunRecords(contentState: .updated)
    }

    private func comprehensiveBulkDeleteRunRecords() {
        replaceSearchText(with: configuration.runPrefix)
        selectAllFilteredRecords()
        XCTAssertTrue(button("record.delete").waitForExistence(timeout: 10))

        typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(button("record.delete").waitForNonExistence(timeout: 10))

        selectAllFilteredRecords()
        click(button("record.delete"))
        click(button("record.bulkAction.cancel"), timeout: 30)

        selectAllFilteredRecords()
        openContextMenu(for: configuration.primaryRecord)
        click(contextMenuItem(
            "record.context.bulkDelete",
            label: "Delete \(configuration.expectedRecords.count) Records"
        ))
        submitBulkDeleteAndWait()
        XCTAssertTrue(
            element("record.search.empty").waitForExistence(timeout: 30),
            "Run-owned records remained visible after bulk deletion."
        )
    }

    private func basicBulkDeleteRunRecords() {
        replaceSearchText(with: configuration.runPrefix)
        selectAllFilteredRecords()
        click(button("record.delete"))
        submitBulkDeleteAndWait()
        XCTAssertTrue(
            element("record.search.empty").waitForExistence(timeout: 30),
            "Run-owned records remained visible after deletion."
        )
    }

    private func submitBulkDeleteAndWait() {
        let submitButton = button("record.bulkDelete.submit")
        let cancelButton = button("record.bulkAction.cancel")
        clickWhenEnabled(submitButton)
        XCTAssertTrue(
            cancelButton.waitForNonExistence(timeout: 120),
            "The provider did not finish the bulk deletion within two minutes."
        )
    }

    private func disconnectProvider() {
        XCTAssertTrue(appDriver.disconnect(configuration.definition))
    }

    private func selectRecord(_ record: ProviderCanaryRecordFixture) {
        activateApp()
        clickRecordRow(record)
        typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(button("record.edit").waitForExistence(timeout: 30))
    }

    private func selectAllFilteredRecords() {
        clickRecordRow(configuration.primaryRecord)
        typeKey("a", modifierFlags: .command)
        XCTAssertTrue(button("record.delete").waitForExistence(timeout: 30))
        XCTAssertEqual(
            button("record.delete").label,
            "Delete \(configuration.expectedRecords.count) records",
            "Select All must stay constrained to the filtered run-owned records."
        )
    }

    private func clickRecordRow(_ record: ProviderCanaryRecordFixture) {
        click(typeElement(record), timeout: 30)
    }

    private func assertRunRecords(contentState: RecordContentState) {
        for record in configuration.records {
            assertRecord(
                record,
                content: contentState == .initial ? record.initialContent : record.updatedContent
            )
        }
    }

    private func assertRecord(_ record: ProviderCanaryRecordFixture, content: String) {
        XCTAssertTrue(recordElement(record).waitForExistence(timeout: 30))
        let contentElement = contentElement(record)
        XCTAssertTrue(contentElement.waitForExistence(timeout: 30))
        let contentUpdated = XCTNSPredicateExpectation(
            predicate: NSPredicate { [weak self] object, _ in
                guard let self, let element = object as? XCUIElement else { return false }
                return displayedText(of: element) == content
            },
            object: contentElement
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [contentUpdated], timeout: 30),
            .completed,
            "\(configuration.definition.displayName) did not refresh \(record.relativeName) in the records table."
        )
        XCTAssertEqual(displayedText(of: contentElement), content)
    }

    private func openContextMenu(for record: ProviderCanaryRecordFixture) {
        openContextMenu(for: record.expectedRecord)
    }

    private func openContextMenu(for record: ProviderCanaryExpectedRecordFixture) {
        let recordElement = recordElement(record)
        XCTAssertTrue(recordElement.waitForExistence(timeout: 30))
        recordElement.rightClick()
    }

    private func replaceSearchText(with value: String) {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        replaceText(in: searchField, with: value)
        XCTAssertEqual(searchField.value as? String, value)
    }

    private func recordElement(_ record: ProviderCanaryRecordFixture) -> XCUIElement {
        recordElement(record.expectedRecord)
    }

    private func recordElement(_ record: ProviderCanaryExpectedRecordFixture) -> XCUIElement {
        app.staticTexts
            .matching(
                identifier: "record.name.\(configuration.recordNamePresentedByApp(record.fullyQualifiedName))"
            )
            .firstMatch
    }

    private func contentElement(_ record: ProviderCanaryRecordFixture) -> XCUIElement {
        app.staticTexts
            .matching(
                identifier: "record.content.\(configuration.recordNamePresentedByApp(record.fullyQualifiedName))"
            )
            .firstMatch
    }

    private func displayedText(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private func providerErrorAlertMessage() -> String? {
        let alert = app.alerts["Error"]
        guard alert.waitForExistence(timeout: 0.25) else { return nil }
        let messages = alert.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty && $0 != "Error" }
        return messages.joined(separator: " ")
    }

    private func contextMenuItem(_ identifier: String, label: String) -> XCUIElement {
        let identifiedItem = app.menuItems.matching(identifier: identifier).firstMatch
        if identifiedItem.waitForExistence(timeout: 2) {
            return identifiedItem
        }
        return app.menuItems[label]
    }

    private func button(_ identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).firstMatch
    }

    private func popUpButton(_ identifier: String) -> XCUIElement {
        app.popUpButtons.matching(identifier: identifier).firstMatch
    }

    private func staticText(_ identifier: String) -> XCUIElement {
        app.staticTexts.matching(identifier: identifier).firstMatch
    }

    private func textField(_ identifier: String) -> XCUIElement {
        app.textFields.matching(identifier: identifier).firstMatch
    }

    private func typeElement(_ record: ProviderCanaryRecordFixture) -> XCUIElement {
        app.staticTexts
            .matching(
                identifier: "record.type.\(configuration.recordNamePresentedByApp(record.fullyQualifiedName))"
            )
            .firstMatch
    }

    private func replaceRecordFormContent(with value: String) {
        let contentInput = textField("record.form.content")
        XCTAssertTrue(contentInput.waitForExistence(timeout: 10))
        click(contentInput)
        contentInput.typeKey("a", modifierFlags: .command)
        contentInput.typeText(value)
        XCTAssertEqual(displayedText(of: contentInput), value)
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        click(field)
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
    }

    private func cancelRecordForm() {
        click(button("record.form.cancel"))
        let discardButton = button("record.form.discard")
        if discardButton.waitForExistence(timeout: 2) {
            click(discardButton)
        }
        XCTAssertTrue(
            button("record.form.submit").waitForNonExistence(timeout: 10),
            "The record form remained open after cancellation."
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func click(_ element: XCUIElement, timeout: TimeInterval = 10) {
        activateApp()
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing UI element: \(element)")
        element.click()
    }

    private func clickWhenEnabled(_ element: XCUIElement, timeout: TimeInterval = 10) {
        activateApp()
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing UI element: \(element)")
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: timeout), .completed)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    private func clickCenter(_ element: XCUIElement, timeout: TimeInterval = 10) {
        activateApp()
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing UI element: \(element)")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    private func typeKey(
        _ key: String,
        modifierFlags: XCUIElement.KeyModifierFlags
    ) {
        activateApp()
        app.typeKey(key, modifierFlags: modifierFlags)
    }

    private func typeKey(
        _ key: XCUIKeyboardKey,
        modifierFlags: XCUIElement.KeyModifierFlags
    ) {
        activateApp()
        app.typeKey(key, modifierFlags: modifierFlags)
    }

    private func activateApp() {
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "DNSDeck did not enter the foreground.")
    }

    private func perform<Result>(_ name: String, action: () -> Result) -> Result {
        phaseLogger.notice("Starting \(name, privacy: .public)")
        defer { phaseLogger.notice("Finished \(name, privacy: .public)") }
        return XCTContext.runActivity(named: name) { _ in
            action()
        }
    }

    private nonisolated static func testRecordPrefix(buildID: String?, now: Date) -> String {
        let buildComponent = buildID?
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(10)
        let runComponent = buildComponent.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
            ?? String(UUID().uuidString.lowercased().prefix(10))
        let uniqueComponent = UUID().uuidString.lowercased().prefix(8)
        let timestamp = Int(now.timeIntervalSince1970)
        return "dnsdeck-ui-\(timestamp)-\(runComponent)-\(uniqueComponent)"
    }

    private enum RecordEntryPoint {
        case toolbar
        case zoneMenu
    }

    private enum RecordContentState {
        case initial
        case updated
    }
}
