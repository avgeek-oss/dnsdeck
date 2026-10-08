import Foundation
import SwiftUI

extension Date {
    /// Returns a detailed date string for display in UI (e.g., "Jan 15, 2023 10:00 AM")
    func detailedDisplayString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Returns a date string formatted according to the user's preferences
    func formattedString(format: DateTimeFormat) -> String {
        switch format {
        case .relative:
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: self, relativeTo: Date())
        case .automatic:
            return detailedDisplayString()
        default:
            return format.dateFormatter.string(from: self)
        }
    }
}

extension DateFormatter {
    /// Shared ISO8601 formatter for API responses
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Shared formatter for display dates
    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Shared formatter for compact display
    static let compact: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}
