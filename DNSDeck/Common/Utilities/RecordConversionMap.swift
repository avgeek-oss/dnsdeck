import Foundation

enum RecordConversionMap {
    /// Curated map of source record type -> valid target types for bulk conversion.
    /// Only includes conversions between simple types with compatible field structures.
    static let conversions: [String: [String]] = [
        "TXT": ["CNAME"],
        "CNAME": ["TXT", "A"],
        "A": ["AAAA", "CNAME"],
        "AAAA": ["A", "CNAME"],
        "MX": ["CNAME", "TXT"],
        "NS": ["CNAME"],
    ]

    /// Returns valid target types for the given source type, or empty array if no conversions available.
    static func targets(for sourceType: String) -> [String] {
        conversions[sourceType] ?? []
    }
}
