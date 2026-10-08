
import Foundation

struct DNSEnvironment: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var isStarred: Bool

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), isStarred: Bool = false) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isStarred = isStarred
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, isStarred
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
    }
}
