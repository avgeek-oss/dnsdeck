import SwiftUI

/// Centralized motion policy for shared and app-owned views.
public enum AvgeekMotion {
    public static func permitsAnimation(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    public static func animation(
        _ animation: Animation,
        reduceMotion: Bool
    ) -> Animation? {
        permitsAnimation(reduceMotion: reduceMotion) ? animation : nil
    }

    public static func opacityTransition(reduceMotion: Bool) -> AnyTransition {
        permitsAnimation(reduceMotion: reduceMotion) ? .opacity : .identity
    }
}
