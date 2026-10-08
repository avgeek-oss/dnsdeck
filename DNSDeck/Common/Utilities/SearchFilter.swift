import Foundation

enum SearchFilter {
    static func filterRecords(_ records: [ProviderRecord], searchText: String) -> [ProviderRecord] {
        guard !searchText.isEmpty else { return records }

        let query = searchText.lowercased()

        return records.filter { record in
            record.name.lowercased().contains(query) ||
                record.type.lowercased().contains(query) ||
                recordContentText(for: record).lowercased().contains(query) ||
                (record.comment?.lowercased().contains(query) ?? false)
        }
    }

    private static func recordContentText(for record: ProviderRecord) -> String {
        record.content
    }
}
