import AvgeekLocalizationCore
import AvgeekLocalizationUI
import SwiftUI

/// A localized, cross-platform empty-state presentation. Product copy and
/// actions remain supplied by the consuming application.
public struct AvgeekEmptyStateView: View {
    public let configuration: EmptyStateConfiguration
    public let onAction: (() -> Void)?

    @AppLocalized private var localize
    @ScaledMetric(relativeTo: .title2) private var iconSize = AppleControlMetrics.emptyStateIconSize

    public init(
        configuration: EmptyStateConfiguration,
        onAction: (() -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onAction = onAction
    }

    public init(
        icon: String,
        title: String,
        message: String,
        buttonTitle: String? = nil,
        buttonIcon: String? = nil,
        onButtonTap: (() -> Void)? = nil
    ) {
        configuration = EmptyStateConfiguration(
            systemImage: icon,
            title: .localized(title),
            message: message.isEmpty ? nil : .localized(message),
            action: buttonTitle.map {
                EmptyStateConfiguration.Action(
                    title: .localized($0),
                    systemImage: buttonIcon
                )
            }
        )
        onAction = onButtonTap
    }

    public var body: some View {
        VStack(spacing: AppleControlMetrics.regularSpacing) {
            Spacer(minLength: 0)

            Image(systemName: configuration.systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: AppleControlMetrics.compactSpacing) {
                Text(configuration.title.resolve(using: localize))
                    .font(.headline)
                    .fontWeight(.semibold)

                if let message = configuration.message {
                    Text(message.resolve(using: localize))
                        .font(.body)
                }
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(configuration.resolvedAccessibilityLabel(using: localize))

            if let action = configuration.action, let onAction {
                Button(action: onAction) {
                    if let systemImage = action.systemImage {
                        Label(action.title.resolve(using: localize), systemImage: systemImage)
                    } else {
                        Text(action.title.resolve(using: localize))
                    }
                }
                .buttonStyle(.borderedProminent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(action.resolvedAccessibilityLabel(using: localize))
                .padding(.top, AppleControlMetrics.regularSpacing)
            }

            Spacer(minLength: 0)
        }
        .padding(AppleControlMetrics.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
