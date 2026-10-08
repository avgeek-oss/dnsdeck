import AvgeekLocalizationCore

/// Text consumed by shared presentation without moving product copy out of the
/// application's String Catalog.
public struct DesignSystemText: Equatable, ExpressibleByStringLiteral, Sendable {
    public enum Resolution: Equatable, Sendable {
        case localized
        case verbatim
    }

    public let value: String
    public let resolution: Resolution

    public init(_ value: String, resolution: Resolution = .localized) {
        self.value = value
        self.resolution = resolution
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public static func localized(_ key: String) -> Self {
        Self(key, resolution: .localized)
    }

    public static func verbatim(_ value: String) -> Self {
        Self(value, resolution: .verbatim)
    }

    public func resolve(using resolver: AppLocalizationResolver) -> String {
        switch resolution {
        case .localized:
            resolver(value)
        case .verbatim:
            value
        }
    }
}
