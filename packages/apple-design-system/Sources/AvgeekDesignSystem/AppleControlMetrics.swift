import Foundation

/// Stable metrics shared by general-purpose controls. Product layouts should
/// continue to define their own feature-specific dimensions.
public enum AppleControlMetrics {
    public static let minimumInteractiveDimension: CGFloat = 44
    public static let compactCornerRadius: CGFloat = 6
    public static let standardCornerRadius: CGFloat = 8
    public static let cardCornerRadius: CGFloat = 12
    public static let compactSpacing: CGFloat = 6
    public static let regularSpacing: CGFloat = 12
    public static let contentPadding: CGFloat = 16
    public static let emptyStateIconSize: CGFloat = 24
}
