import AvgeekLocalizationCore

public struct EmptyStateConfiguration: Equatable, Sendable {
    public struct Action: Equatable, Sendable {
        public let title: DesignSystemText
        public let systemImage: String?
        public let accessibilityLabel: DesignSystemText?

        public init(
            title: DesignSystemText,
            systemImage: String? = nil,
            accessibilityLabel: DesignSystemText? = nil
        ) {
            self.title = title
            self.systemImage = systemImage
            self.accessibilityLabel = accessibilityLabel
        }

        public func resolvedAccessibilityLabel(using resolver: AppLocalizationResolver) -> String {
            (accessibilityLabel ?? title).resolve(using: resolver)
        }
    }

    public let systemImage: String
    public let title: DesignSystemText
    public let message: DesignSystemText?
    public let action: Action?
    public let accessibilityLabel: DesignSystemText?

    public init(
        systemImage: String,
        title: DesignSystemText,
        message: DesignSystemText? = nil,
        action: Action? = nil,
        accessibilityLabel: DesignSystemText? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.action = action
        self.accessibilityLabel = accessibilityLabel
    }

    public func resolvedAccessibilityLabel(using resolver: AppLocalizationResolver) -> String {
        if let accessibilityLabel {
            return accessibilityLabel.resolve(using: resolver)
        }

        return [title, message]
            .compactMap { $0?.resolve(using: resolver) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
