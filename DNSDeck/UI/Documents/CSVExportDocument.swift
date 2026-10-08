#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText]
    }

    static var writableContentTypes: [UTType] {
        [.commaSeparatedText]
    }

    let records: [ProviderRecord]

    init(records: [ProviderRecord]) {
        self.records = records
    }

    init(configuration: ReadConfiguration) throws {
        records = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var csvContent = "type,name,value"

        let hasTTL = records.contains { $0.ttl != nil }
        let hasPriority = records.contains { $0.priority != nil }
        let hasProxied = records.contains { $0.proxied != nil }
        let hasComment = records.contains { $0.comment != nil && !$0.comment!.isEmpty }

        if hasTTL {
            csvContent += ",ttl"
        }
        if hasPriority {
            csvContent += ",priority"
        }
        if hasProxied {
            csvContent += ",proxied"
        }
        if hasComment {
            csvContent += ",comment"
        }
        csvContent += "\n"

        for record in records {
            csvContent += escapeCSVField(record.type) + ","
            csvContent += escapeCSVField(record.name) + ","
            csvContent += escapeCSVField(record.content)

            if hasTTL {
                csvContent += ","
                if let ttl = record.ttl {
                    csvContent += "\(ttl)"
                }
            }
            if hasPriority {
                csvContent += ","
                if let priority = record.priority {
                    csvContent += "\(priority)"
                }
            }
            if hasProxied {
                csvContent += ","
                if let proxied = record.proxied {
                    csvContent += proxied ? "true" : "false"
                }
            }
            if hasComment {
                csvContent += ","
                if let comment = record.comment, !comment.isEmpty {
                    csvContent += escapeCSVField(comment)
                }
            }
            csvContent += "\n"
        }

        guard let data = csvContent.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }

        return FileWrapper(regularFileWithContents: data)
    }

    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\n") || field.contains("\"") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}

#endif
