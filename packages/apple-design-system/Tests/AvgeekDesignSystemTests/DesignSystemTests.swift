import AvgeekDesignSystem
import AvgeekDesignSystemCatalog
import AvgeekLocalizationCore
import SwiftUI
import XCTest

#if os(macOS)
    import AppKit
#endif

final class DesignSystemTextTests: XCTestCase {
    private var catalog: LocalizationCatalog {
        LocalizationCatalog(bundle: .module)
    }

    func testLocalizedTextUsesRequestedLanguageAndEnglishFallback() {
        let text = DesignSystemText.localized("Empty title")

        XCTAssertEqual(text.resolve(using: catalog.resolver(for: .german)), "Noch keine Einträge")
        XCTAssertEqual(text.resolve(using: catalog.resolver(for: .ukrainian)), "No items yet")
    }

    func testVerbatimTextBypassesLocalization() {
        let text = DesignSystemText.verbatim("Provider model-v1")

        XCTAssertEqual(text.resolve(using: catalog.resolver(for: .german)), "Provider model-v1")
    }

    func testConfigurationResolvesDefaultAndExplicitAccessibilityLabels() {
        let resolver = catalog.resolver(for: .german)
        let configuration = EmptyStateConfiguration(
            systemImage: "tray",
            title: .localized("Empty title"),
            message: .localized("Empty message"),
            action: .init(
                title: .localized("Create"),
                accessibilityLabel: .verbatim("Create the first item")
            )
        )

        XCTAssertEqual(
            configuration.resolvedAccessibilityLabel(using: resolver),
            "Noch keine Einträge, Erstelle deinen ersten Eintrag."
        )
        XCTAssertEqual(
            configuration.action?.resolvedAccessibilityLabel(using: resolver),
            "Create the first item"
        )
    }
}

final class FeedbackTests: XCTestCase {
    func testConvenienceMethodsRouteTypedEvents() {
        let recorder = FeedbackRecorder()

        AvgeekFeedback.success(using: recorder)
        AvgeekFeedback.warning(using: recorder)
        AvgeekFeedback.error(using: recorder)
        AvgeekFeedback.selection(using: recorder)
        AvgeekFeedback.impact(.heavy, using: recorder)

        XCTAssertEqual(
            recorder.events,
            [
                .notification(.success),
                .notification(.warning),
                .notification(.error),
                .selection,
                .impact(.heavy),
            ]
        )
    }
}

private final class FeedbackRecorder: FeedbackPerforming {
    private(set) var events: [AvgeekFeedback.Event] = []

    func perform(_ event: AvgeekFeedback.Event) {
        events.append(event)
    }
}

final class AccessibilityPolicyTests: XCTestCase {
    func testReducedMotionDisablesAnimation() {
        XCTAssertFalse(AvgeekMotion.permitsAnimation(reduceMotion: true))
        XCTAssertNil(AvgeekMotion.animation(.easeInOut, reduceMotion: true))
        XCTAssertNotNil(AvgeekMotion.animation(.easeInOut, reduceMotion: false))
    }

    func testMinimumInteractiveDimensionMeetsAppleGuidance() {
        XCTAssertGreaterThanOrEqual(AppleControlMetrics.minimumInteractiveDimension, 44)
    }

    func testCatalogCoversLongTextAndAccessibilityVariants() {
        let fixtures = DesignSystemCatalogFixtures.representative

        XCTAssertTrue(fixtures.contains { $0.localeIdentifier == "de" })
        XCTAssertTrue(fixtures.contains { $0.localeIdentifier == "uk" && $0.reduceMotion })
        XCTAssertTrue(fixtures.contains { $0.localeIdentifier == "vi" })
        XCTAssertTrue(fixtures.contains { $0.dynamicTypeSize.isAccessibilitySize })
        XCTAssertTrue(fixtures.contains { $0.colorSchemeContrast == .increased })
        XCTAssertTrue(fixtures.allSatisfy { $0.width >= 280 })
    }

    #if os(macOS)
        @MainActor
        func testCatalogFixturesRenderAtDeclaredDynamicTypeAndWidth() throws {
            for fixture in DesignSystemCatalogFixtures.representative {
                let content = AvgeekEmptyStateView(
                    configuration: fixture.configuration,
                    onAction: {}
                )
                .frame(width: fixture.width, height: 360)
                .environment(\.locale, Locale(identifier: fixture.localeIdentifier))
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)
                .environment(\.colorScheme, .light)
                .background(ApplePlatformColor.background)

                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage, fixture.id)

                XCTAssertGreaterThan(image.size.width, 0, fixture.id)
                XCTAssertGreaterThan(image.size.height, 0, fixture.id)
                XCTAssertFalse(try XCTUnwrap(image.tiffRepresentation, fixture.id).isEmpty, fixture.id)

                try writeCatalogSnapshot(image, named: fixture.id)
            }
        }

        private func writeCatalogSnapshot(_ image: NSImage, named name: String) throws {
            guard let outputPath = ProcessInfo.processInfo.environment["DESIGN_SYSTEM_SNAPSHOT_OUTPUT"] else {
                return
            }

            let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            let tiffData = try XCTUnwrap(image.tiffRepresentation, name)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData), name)
            let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]), name)

            try pngData.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        }
    #endif
}
