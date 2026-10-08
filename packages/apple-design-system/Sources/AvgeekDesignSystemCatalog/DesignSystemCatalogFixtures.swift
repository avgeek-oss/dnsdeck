import AvgeekDesignSystem
import SwiftUI

public struct DesignSystemCatalogFixture: Identifiable {
    public let id: String
    public let localeIdentifier: String
    public let width: CGFloat
    public let dynamicTypeSize: DynamicTypeSize
    public let colorSchemeContrast: ColorSchemeContrast
    public let reduceMotion: Bool
    public let configuration: EmptyStateConfiguration

    public init(
        id: String,
        localeIdentifier: String,
        width: CGFloat,
        dynamicTypeSize: DynamicTypeSize = .large,
        colorSchemeContrast: ColorSchemeContrast = .standard,
        reduceMotion: Bool = false,
        configuration: EmptyStateConfiguration
    ) {
        self.id = id
        self.localeIdentifier = localeIdentifier
        self.width = width
        self.dynamicTypeSize = dynamicTypeSize
        self.colorSchemeContrast = colorSchemeContrast
        self.reduceMotion = reduceMotion
        self.configuration = configuration
    }
}

public enum DesignSystemCatalogFixtures {
    public static let representative: [DesignSystemCatalogFixture] = [
        DesignSystemCatalogFixture(
            id: "english-standard",
            localeIdentifier: "en",
            width: 320,
            configuration: EmptyStateConfiguration(
                systemImage: "tray",
                title: .verbatim("No items yet"),
                message: .verbatim("Create your first item to get started."),
                action: .init(title: .verbatim("Create Item"), systemImage: "plus")
            )
        ),
        DesignSystemCatalogFixture(
            id: "german-long-text",
            localeIdentifier: "de",
            width: 320,
            configuration: EmptyStateConfiguration(
                systemImage: "network",
                title: .verbatim("Noch keine verbundenen Anbieter"),
                message: .verbatim(
                    "Verbinde einen Anbieter, um deine verfügbaren Zonen und Einstellungen anzuzeigen."
                ),
                action: .init(title: .verbatim("Anbieter verbinden"), systemImage: "plus")
            )
        ),
        DesignSystemCatalogFixture(
            id: "ukrainian-accessibility",
            localeIdentifier: "uk",
            width: 360,
            dynamicTypeSize: .accessibility3,
            colorSchemeContrast: .increased,
            reduceMotion: true,
            configuration: EmptyStateConfiguration(
                systemImage: "photo.on.rectangle.angled",
                title: .verbatim("Ще немає завершених зображень"),
                message: .verbatim(
                    "Згенеровані зображення з'являться тут після завершення обробки."
                )
            )
        ),
        DesignSystemCatalogFixture(
            id: "vietnamese-compact",
            localeIdentifier: "vi",
            width: 280,
            configuration: EmptyStateConfiguration(
                systemImage: "bubble.left.and.text.bubble.right",
                title: .verbatim("Chưa có cuộc trò chuyện nào"),
                message: .verbatim("Tạo cuộc trò chuyện đầu tiên để bắt đầu tạo hình ảnh."),
                action: .init(title: .verbatim("Tạo cuộc trò chuyện"))
            )
        ),
    ]
}
