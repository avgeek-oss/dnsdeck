import AvgeekDesignSystem
import SwiftUI

struct LoadingOverlay: View {
    let text: String
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isVisible {
                ZStack {
                    // Material (not a Color tint) so the backdrop blends adaptively
                    // in light/dark mode without a hard background color shift.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.regular)
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(AppleControlMetrics.contentPadding)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: AppleControlMetrics.cardCornerRadius)
                    )
                    .accessibilityAddTraits(.isModal)
                }
                .transition(AvgeekMotion.opacityTransition(reduceMotion: reduceMotion))
            }
        }
        .animation(
            AvgeekMotion.animation(.easeInOut(duration: 0.2), reduceMotion: reduceMotion),
            value: isVisible
        )
    }
}

extension View {
    func loadingOverlay(
        text: String = Constants.UIText.loading,
        isVisible: Bool = true
    ) -> some View {
        overlay { LoadingOverlay(text: text, isVisible: isVisible) }
    }
}
