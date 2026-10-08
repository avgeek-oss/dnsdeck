#if os(iOS)
    import UIKit
#endif

public enum AvgeekFeedback {
    public enum Notification: Equatable, Sendable {
        case success
        case warning
        case error
    }

    public enum ImpactStyle: Equatable, Sendable {
        case light
        case medium
        case heavy
    }

    public enum Event: Equatable, Sendable {
        case notification(Notification)
        case selection
        case impact(ImpactStyle)
    }

    public static func perform(
        _ event: Event,
        using performer: some FeedbackPerforming = SystemFeedbackPerformer()
    ) {
        performer.perform(event)
    }

    public static func success(using performer: some FeedbackPerforming = SystemFeedbackPerformer()) {
        perform(.notification(.success), using: performer)
    }

    public static func warning(using performer: some FeedbackPerforming = SystemFeedbackPerformer()) {
        perform(.notification(.warning), using: performer)
    }

    public static func error(using performer: some FeedbackPerforming = SystemFeedbackPerformer()) {
        perform(.notification(.error), using: performer)
    }

    public static func selection(using performer: some FeedbackPerforming = SystemFeedbackPerformer()) {
        perform(.selection, using: performer)
    }

    public static func impact(
        _ style: ImpactStyle = .medium,
        using performer: some FeedbackPerforming = SystemFeedbackPerformer()
    ) {
        perform(.impact(style), using: performer)
    }
}

public protocol FeedbackPerforming {
    func perform(_ event: AvgeekFeedback.Event)
}

/// Native feedback used by production applications. macOS intentionally does
/// nothing because standard controls provide their own interaction feedback.
public struct SystemFeedbackPerformer: FeedbackPerforming {
    public init() {}

    public func perform(_ event: AvgeekFeedback.Event) {
        #if os(iOS)
            switch event {
            case let .notification(notification):
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(notification.uiType)
            case .selection:
                let generator = UISelectionFeedbackGenerator()
                generator.selectionChanged()
            case let .impact(style):
                let generator = UIImpactFeedbackGenerator(style: style.uiStyle)
                generator.impactOccurred()
            }
        #endif
    }
}

#if os(iOS)
    private extension AvgeekFeedback.Notification {
        var uiType: UINotificationFeedbackGenerator.FeedbackType {
            switch self {
            case .success: .success
            case .warning: .warning
            case .error: .error
            }
        }
    }

    private extension AvgeekFeedback.ImpactStyle {
        var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light: .light
            case .medium: .medium
            case .heavy: .heavy
            }
        }
    }
#endif
