import Foundation

struct DNSDeckMCPAuditLog {
    private static let defaultMaxFileSizeBytes = 1_048_576
    private static let defaultMaxRetainedEvents = 1000

    private let fileURL: URL?
    private let maxFileSizeBytes: Int
    private let maxRetainedEvents: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "dev.dnsdeck.mcp.audit")

    init(
        fileURL: URL? = DNSDeckMCPAuditLog.defaultFileURL,
        maxFileSizeBytes: Int = DNSDeckMCPAuditLog.defaultMaxFileSizeBytes,
        maxRetainedEvents: Int = DNSDeckMCPAuditLog.defaultMaxRetainedEvents
    ) {
        self.fileURL = fileURL
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxRetainedEvents = maxRetainedEvents
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    static var disabled: DNSDeckMCPAuditLog {
        DNSDeckMCPAuditLog(fileURL: nil)
    }

    func append(event: DNSDeckMCPAuditEvent) {
        guard let fileURL else { return }

        queue.async {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try encoder.encode(event)
                let line = data + Data([0x0A])

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                    try handle.close()
                } else {
                    try line.write(to: fileURL, options: .atomic)
                }
                try pruneIfNeeded(fileURL)
            } catch {
                FileHandle.standardError.writeLine("dnsdeck-mcp audit write failed: \(error.localizedDescription)")
            }
        }
    }

    func recent(limit: Int = 50) -> [[String: Any]] {
        guard let fileURL else { return [] }

        return queue.sync {
            do {
                return try tailLines(at: fileURL, limit: limit)
                    .compactMap { line in
                        guard let data = line.data(using: .utf8),
                              let event = try? decoder.decode(DNSDeckMCPAuditEvent.self, from: data)
                        else {
                            return nil
                        }
                        return event.json
                    }
            } catch {
                return []
            }
        }
    }

    private func pruneIfNeeded(_ fileURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        let retainedLines = try tailLines(at: fileURL, limit: maxRetainedEvents + 1)
        guard fileSize > maxFileSizeBytes || retainedLines.count > maxRetainedEvents else { return }

        var lines = Array(retainedLines.suffix(maxRetainedEvents))
        var data = encodedJSONLines(lines)
        while data.count > maxFileSizeBytes, lines.count > 1 {
            lines.removeFirst()
            data = encodedJSONLines(lines)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    private func tailLines(at fileURL: URL, limit: Int) throws -> [String] {
        guard limit > 0,
              FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return []
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        var offset = fileSize
        var buffer = Data()
        let chunkSize: UInt64 = 4096
        var newlineCount = 0

        while offset > 0, newlineCount <= limit {
            let readSize = min(chunkSize, offset)
            offset -= readSize
            try handle.seek(toOffset: offset)
            let chunk = try handle.read(upToCount: Int(readSize)) ?? Data()
            buffer.insert(contentsOf: chunk, at: 0)
            newlineCount = buffer.reduce(0) { count, byte in
                byte == 0x0A ? count + 1 : count
            }
        }

        guard let content = String(data: buffer, encoding: .utf8) else {
            return []
        }

        return content
            .split(separator: "\n")
            .suffix(limit)
            .map(String.init)
    }

    private func encodedJSONLines(_ lines: [String]) -> Data {
        guard !lines.isEmpty else { return Data() }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static var defaultFileURL: URL? {
        guard let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return logs
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("DNSDeck", isDirectory: true)
            .appendingPathComponent("mcp-audit.jsonl")
    }
}

struct DNSDeckMCPAuditEvent: Codable {
    let timestamp: Date
    let operation: String
    let clientName: String?
    let environmentId: String?
    let provider: String?
    let zoneId: String?
    let recordId: String?
    let result: String
    let errorCode: String?

    init(
        operation: String,
        clientName: String?,
        environmentId: String? = nil,
        provider: String? = nil,
        zoneId: String? = nil,
        recordId: String? = nil,
        result: String,
        errorCode: String? = nil
    ) {
        timestamp = Date()
        self.operation = operation
        self.clientName = clientName
        self.environmentId = environmentId
        self.provider = provider
        self.zoneId = zoneId
        self.recordId = recordId
        self.result = result
        self.errorCode = errorCode
    }

    var json: [String: Any] {
        [
            "timestamp": DNSDeckMCPJSON.iso8601.string(from: timestamp),
            "operation": operation,
            "clientName": clientName as Any,
            "environmentId": environmentId as Any,
            "provider": provider as Any,
            "zoneId": zoneId as Any,
            "recordId": recordId as Any,
            "result": result,
            "errorCode": errorCode as Any,
        ].removingNilValues()
    }
}
