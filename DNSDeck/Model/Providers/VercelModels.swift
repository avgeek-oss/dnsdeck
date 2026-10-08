import Foundation

// MARK: - Domain Models

struct VercelDomain: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    var verified: Bool? = nil
    var nameservers: [String]? = nil
    var intendedNameservers: [String]? = nil
    var createdAt: Double? = nil
    var cdnEnabled: Bool? = nil
    var zone: Bool? = nil
    var boughtAt: Double? = nil
    var expiresAt: Double? = nil
    var renew: Bool? = nil
    var serviceType: String? = nil
    var transferredAt: Double? = nil
    var userId: String? = nil
    var teamId: String? = nil
    var configVerifiedAt: Double? = nil
    var txtVerifiedAt: Double? = nil
    var nsVerifiedAt: Double? = nil
    var verificationRecord: String? = nil
    var creator: VercelCreator? = nil
}

extension VercelDomain {
    func snapshot() -> ProviderZoneSnapshot {
        var metadata: [String: String] = [:]
        metadata["serviceType"] = serviceType
        metadata["cdnEnabled"] = cdnEnabled.map(String.init)
        metadata["zone"] = zone.map(String.init)
        metadata["autoRenew"] = renew.map(String.init)
        metadata["intendedNameservers"] = intendedNameservers?.joined(separator: "\n")
        metadata["creatorName"] = creator?.name
        metadata["creatorUsername"] = creator?.username
        metadata["creatorEmail"] = creator?.email
        metadata["verificationRecord"] = verificationRecord
        metadata["configVerifiedAt"] = configVerifiedAt.map { String($0) }
        metadata["txtVerifiedAt"] = txtVerifiedAt.map { String($0) }
        metadata["nsVerifiedAt"] = nsVerifiedAt.map { String($0) }
        metadata["boughtAt"] = boughtAt.map { String($0) }
        metadata["transferredAt"] = transferredAt.map { String($0) }
        metadata["expiresAt"] = expiresAt.map { String($0) }
        metadata["userId"] = userId
        metadata["teamId"] = teamId
        return ProviderZoneSnapshot(
            id: id,
            name: name,
            nameservers: nameservers ?? [],
            status: verified.map { $0 ? "verified" : "unverified" },
            createdOn: createdAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            metadata: metadata,
            providerData: providerSnapshotData
        )
    }
}

struct VercelNameserverUpdateRequest: Codable, Equatable {
    let nameservers: [String]
}

struct VercelCreateDomainRequest: Codable {
    let name: String
}

struct VercelCreateDomainResponse: Decodable {
    let id: String?
    let uid: String?
    let name: String?
    let nameservers: [String]?
}

struct VercelCreator: Codable, Hashable {
    let id: String
    let email: String
    let username: String
    let name: String
}

// MARK: - DNS Record Models

struct VercelDNSRecord: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String
    let value: String?
    let priority: Int?
    let ttl: Int?
    let comment: String?
    let created: Double?
    let updated: Double?
    let mxPriority: Int?
    let mx: Int?
    let verified: Bool?
    let slug: String?

    enum CodingKeys: String, CodingKey {
        case id, type, name, value, slug, priority, ttl, comment
        case created, updated, mxPriority, mx, verified
    }
}

extension VercelDNSRecord {
    func snapshot() -> ProviderRecordSnapshot {
        ProviderRecordSnapshot(
            id: id,
            name: name,
            type: type,
            values: value.map { [$0] } ?? [],
            displayContent: value ?? "",
            ttl: ttl,
            priority: priority ?? mxPriority ?? mx,
            comment: comment,
            createdOn: created.map { Date(timeIntervalSince1970: $0 / 1000) },
            modifiedOn: updated.map { Date(timeIntervalSince1970: $0 / 1000) },
            providerData: providerSnapshotData
        )
    }
}

// MARK: - API Response Envelopes

struct VercelDomainListResponse: Decodable {
    let domains: [VercelDomain]
    let pagination: VercelPagination?
}

struct VercelDNSRecordListResponse: Decodable {
    let records: [VercelDNSRecord]
    let pagination: VercelPagination?
}

struct VercelPagination: Decodable {
    let count: Int
    let prev: Int?
    let next: Int?
}

// MARK: - Create/Update Request Models

struct CreateVercelDNSRecordRequest: Encodable {
    let type: String
    let name: String
    let value: String
    let ttl: Int?
    let comment: String?
    let mxPriority: Int?
}

struct UpdateVercelDNSRecordRequest: Encodable {
    let type: String?
    let name: String?
    let value: String?
    let ttl: Int?
    let comment: String?
    let mxPriority: Int?
}

// MARK: - API Response Models

struct VercelCreateRecordResponse: Decodable {
    let uid: String
    let updatedAt: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        updatedAt = try container.decodeIfPresent(Double.self, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case uid, updatedAt
    }
}

struct VercelDeleteRecordResponse: Decodable {
    let deleted: Bool?
}

// MARK: - Error Models

struct VercelError: Decodable, Error, LocalizedError {
    let code: VercelErrorCode?
    let message: String

    var errorDescription: String? {
        message
    }
}

enum VercelErrorCode: String, Decodable {
    case forbidden = "FORBIDDEN"
    case notFound = "NOT_FOUND"
    case badRequest = "BAD_REQUEST"
    case unauthorized = "UNAUTHORIZED"
    case rateLimit = "RATE_LIMIT_EXCEEDED"
    case invalidToken = "INVALID_TOKEN"
    case missingToken = "MISSING_TOKEN"
    case unknown = "UNKNOWN"

    var localizedDescription: String {
        switch self {
        case .forbidden:
            "Access forbidden - insufficient permissions"
        case .notFound:
            "Resource not found"
        case .badRequest:
            "Invalid request"
        case .unauthorized:
            "Unauthorized - invalid credentials"
        case .rateLimit:
            "Rate limit exceeded"
        case .invalidToken:
            "Invalid API token"
        case .missingToken:
            "Missing API token"
        case .unknown:
            "Unknown error occurred"
        }
    }
}

// MARK: - API Error Wrapper

struct VercelAPIError: Decodable, Error, LocalizedError {
    let error: VercelError

    var errorDescription: String? {
        error.message
    }
}
