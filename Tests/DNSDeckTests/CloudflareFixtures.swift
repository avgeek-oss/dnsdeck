import Foundation
@testable import DNSDeckMCP

extension CFDNSRecord {
    static func makeForTesting(
        id: String = "rec-test",
        type: String = "A",
        name: String = "test.example.com",
        content: String = "192.168.1.1",
        ttl: Int? = 300,
        proxied: Bool? = nil,
        priority: Int? = nil,
        comment: String? = nil,
        data: RecordData? = nil
    ) -> CFDNSRecord {
        let json: [String: Any?] = [
            "id": id,
            "type": type,
            "name": name,
            "content": content,
            "ttl": ttl,
            "proxied": proxied,
            "priority": priority,
            "comment": comment,
        ]

        // Filter out nil values for proper JSON encoding
        var filteredJSON: [String: Any] = [:]
        for (key, value) in json {
            if let value {
                filteredJSON[key] = value
            }
        }

        let jsonData = try! JSONSerialization.data(withJSONObject: filteredJSON)
        var record = try! JSONDecoder().decode(CFDNSRecord.self, from: jsonData)

        // If data is needed, we need to re-encode with data
        if let data {
            var fullJSON = filteredJSON
            let dataJSON = try! JSONEncoder().encode(data)
            fullJSON["data"] = try! JSONSerialization.jsonObject(with: dataJSON)
            let fullData = try! JSONSerialization.data(withJSONObject: fullJSON)
            record = try! JSONDecoder().decode(CFDNSRecord.self, from: fullData)
        }

        return record
    }
}
