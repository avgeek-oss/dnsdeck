import AvgeekDesignSystem
import SwiftUI

public struct DesignSystemCatalogView: View {
    private let fixtures: [DesignSystemCatalogFixture]

    public init(fixtures: [DesignSystemCatalogFixture] = DesignSystemCatalogFixtures.representative) {
        self.fixtures = fixtures
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppleControlMetrics.contentPadding) {
                ForEach(fixtures, id: \.id) { fixture in
                    VStack(alignment: .leading, spacing: AppleControlMetrics.compactSpacing) {
                        Text(fixtureLabel(fixture))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        AvgeekEmptyStateView(
                            configuration: fixture.configuration,
                            onAction: {}
                        )
                        .frame(width: fixture.width, height: 360)
                        .environment(\.locale, Locale(identifier: fixture.localeIdentifier))
                        .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)
                        .background(ApplePlatformColor.secondaryBackground)
                        .clipShape(
                            RoundedRectangle(cornerRadius: AppleControlMetrics.standardCornerRadius)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppleControlMetrics.standardCornerRadius)
                                .stroke(ApplePlatformColor.separator)
                        }
                    }
                }
            }
            .padding(AppleControlMetrics.contentPadding)
        }
        .background(ApplePlatformColor.background)
    }

    private func fixtureLabel(_ fixture: DesignSystemCatalogFixture) -> String {
        var traits = [fixture.dynamicTypeSize.isAccessibilitySize ? "accessibility type" : "standard type"]
        if fixture.colorSchemeContrast == .increased {
            traits.append("increased contrast")
        }
        if fixture.reduceMotion {
            traits.append("reduced motion")
        }
        return "\(fixture.id) [\(fixture.localeIdentifier)] - \(traits.joined(separator: ", "))"
    }
}

#if DEBUG
    #if os(iOS)
        #Preview("iOS Component Catalog") {
            DesignSystemCatalogView()
        }

    #elseif os(macOS)
        #Preview("macOS Component Catalog") {
            DesignSystemCatalogView()
                .frame(width: 720, height: 720)
        }
    #endif
#endif
