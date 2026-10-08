import AvgeekNetworking
import Foundation
import os.log

enum VercelServiceError: Error, LocalizedError {
    case missingToken
    case http(Int, String? = nil)
    case vercel(VercelAPIError)
    case decoding(Error)
    var errorDescription: String? {
        switch self {
        case .missingToken: "Vercel API token is missing."
        case let .http(code, body):
            if let body, !body.isEmpty {
                "HTTP error \(code): \(body)"
            } else {
                "HTTP error \(code)."
            }
        case let .vercel(err): err.errorDescription
        case let .decoding(e): "Decoding error: \(e.localizedDescription)"
        }
    }
}

final class VercelService {
    private let base = URL(string: Configuration.API.vercelBase)!
    private let tokenProvider: () -> String?
    private let teamIdProvider: () -> String?
    private let transport: any NetworkTransport

    init(
        tokenProvider: @escaping () -> String?,
        teamIdProvider: @escaping () -> String? = { nil },
        transport: any NetworkTransport = NetworkConfiguration.urlSession
    ) {
        self.tokenProvider = tokenProvider
        self.teamIdProvider = teamIdProvider
        self.transport = transport
    }

    // MARK: - Domains

    func listDomains(nameFilter: String? = nil) async throws -> [VercelDomain] {
        var allDomains: [VercelDomain] = []
        var until: Int?

        repeat {
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "\(Constants.Pagination.vercelPageSize)"),
            ]

            if let name = nameFilter, !name.isEmpty {
                queryItems.append(URLQueryItem(name: "name", value: name))
            }

            if let until {
                queryItems.append(URLQueryItem(name: "until", value: "\(until)"))
            }

            let url = try url(path: "v5/domains", queryItems: queryItems)
            let response: VercelDomainListResponse = try await request(url: url, method: "GET")
            allDomains.append(contentsOf: response.domains)

            guard let nextCursor = response.pagination?.next else { break }
            until = nextCursor
        } while true

        return allDomains
    }

    func createDomain(name: String) async throws -> VercelDomain {
        let response: VercelCreateDomainResponse = try await request(
            url: url(path: "v4/domains"),
            method: "POST",
            body: VercelCreateDomainRequest(name: name)
        )
        return VercelDomain(
            id: response.id ?? response.uid ?? name,
            name: response.name ?? name,
            nameservers: response.nameservers
        )
    }

    func updateNameservers(domain: String, nameservers: [String]) async throws {
        _ = try await performRequest(
            url: url(path: "v1/registrar/domains/\(domain)/nameservers"),
            method: "PATCH",
            body: VercelNameserverUpdateRequest(nameservers: nameservers)
        )
    }

    // MARK: - DNS Records

    func listDNSRecords(domain: String) async throws -> [VercelDNSRecord] {
        var allRecords: [VercelDNSRecord] = []
        var until: Int?

        repeat {
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "\(Constants.Pagination.vercelMaxPageSize)"),
            ]

            if let until {
                queryItems.append(URLQueryItem(name: "until", value: "\(until)"))
            }

            let url = try url(path: "v4/domains/\(domain)/records", queryItems: queryItems)
            let response: VercelDNSRecordListResponse = try await request(url: url, method: "GET")
            allRecords.append(contentsOf: response.records)

            guard let nextCursor = response.pagination?.next else { break }
            until = nextCursor
        } while true

        return allRecords
    }

    func createDNSRecord(
        domain: String,
        payload: CreateVercelDNSRecordRequest
    ) async throws -> VercelCreateRecordResponse {
        try await request(url: url(path: "v2/domains/\(domain)/records"), method: "POST", body: payload)
    }

    func updateDNSRecord(recordId: String, payload: UpdateVercelDNSRecordRequest) async throws -> VercelDNSRecord {
        try await request(url: url(path: "v1/domains/records/\(recordId)"), method: "PATCH", body: payload)
    }

    func deleteDNSRecord(domain: String, recordId: String) async throws -> VercelDeleteRecordResponse {
        try await request(url: url(path: "v2/domains/\(domain)/records/\(recordId)"), method: "DELETE")
    }

    // MARK: - Internal

    private func url(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw VercelServiceError.http(-1, nil)
        }
        components.queryItems = queryItems
        if let teamId = teamIdProvider(), !teamId.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "teamId", value: teamId))
        }
        guard let url = components.url else { throw VercelServiceError.http(-1, nil) }
        return url
    }

    private func request<T: Decodable>(url: URL, method: String, body: Encodable? = nil) async throws -> T {
        let data = try await performRequest(url: url, method: method, body: body)

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch let decodingError {
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.general.error("Vercel JSON decoding failed. Response: \(responseString)")
                Logger.general.error("Decoding error: \(decodingError)")
            }
            throw VercelServiceError.decoding(decodingError)
        }
    }

    private func performRequest(url: URL, method: String, body: Encodable? = nil) async throws -> Data {
        guard let token = tokenProvider() else { throw VercelServiceError.missingToken }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, resp) = try await transport.send(req)
        guard let http = resp as? HTTPURLResponse else { throw VercelServiceError.http(-1, nil) }
        guard (200 ..< 300).contains(http.statusCode) else {
            // Try to decode as VercelAPIError first
            if let vercelError = try? JSONDecoder().decode(VercelAPIError.self, from: data) {
                throw VercelServiceError.vercel(vercelError)
            }
            // If decoding fails, capture the raw response body
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
            throw VercelServiceError.http(http.statusCode, responseBody)
        }

        return data
    }
}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
