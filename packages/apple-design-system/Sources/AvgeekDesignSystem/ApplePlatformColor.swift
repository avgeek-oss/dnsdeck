import SwiftUI

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

/// Adaptive Apple platform colors with the same semantic meaning on iOS and
/// macOS. Brand and feature colors do not belong in this namespace.
public enum ApplePlatformColor {
    public static var label: Color {
        #if os(macOS)
            Color(nsColor: .labelColor)
        #else
            Color(uiColor: .label)
        #endif
    }

    public static var secondaryLabel: Color {
        #if os(macOS)
            Color(nsColor: .secondaryLabelColor)
        #else
            Color(uiColor: .secondaryLabel)
        #endif
    }

    public static var background: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #else
            Color(uiColor: .systemBackground)
        #endif
    }

    public static var secondaryBackground: Color {
        #if os(macOS)
            let color = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .underPageBackgroundColor
                    : .windowBackgroundColor
            }
            return Color(nsColor: color)
        #else
            return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    public static var fill: Color {
        #if os(macOS)
            Color(nsColor: .systemFill)
        #else
            Color(uiColor: .systemFill)
        #endif
    }

    public static var secondaryFill: Color {
        #if os(macOS)
            Color(nsColor: .secondarySystemFill)
        #else
            Color(uiColor: .secondarySystemFill)
        #endif
    }

    public static var tertiaryFill: Color {
        #if os(macOS)
            Color(nsColor: .tertiarySystemFill)
        #else
            Color(uiColor: .tertiarySystemFill)
        #endif
    }

    public static var quaternaryFill: Color {
        #if os(macOS)
            Color(nsColor: .quaternarySystemFill)
        #else
            Color(uiColor: .quaternarySystemFill)
        #endif
    }

    public static var separator: Color {
        #if os(macOS)
            Color(nsColor: .separatorColor)
        #else
            Color(uiColor: .separator)
        #endif
    }
}
