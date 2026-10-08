

import AvgeekNetworking
import Foundation
import os.log

enum CFAPIError: Error, LocalizedError {
    case missingToken
    case http(Int)
    case cloudflare([CFError])
    case decoding(Error)
    var errorDescription: String? {
        switch self {
        case .missingToken: "Cloudflare API token is missing."
        case let .http(code): "HTTP error \(code)."
        case let .cloudflare(errs): errs.map(\.message).joined(separator: "\n")
        case let .decoding(e): "Decoding error: \(e.localizedDescription)"
        }
    }
}

final class CloudflareService {
    private let base = URL(string: Configuration.API.cloudflareBase)!
    private let tokenProvider: () -> String?
    private let accountIdProvider: () -> String?
    private let transport: any NetworkTransport

    init(
        tokenProvider: @escaping () -> String?,
        accountIdProvider: @escaping () -> String? = { nil },
        transport: any NetworkTransport = NetworkConfiguration.urlSession
    ) {
        self.tokenProvider = tokenProvider
        self.accountIdProvider = accountIdProvider
        self.transport = transport
    }

    // MARK: - Zones

    func listZones(nameFilter: String? = nil) async throws -> [CFZone] {
        var all: [CFZone] = []
        var page = 1
        repeat {
            guard var comps = URLComponents(url: base.appendingPathComponent("zones"), resolvingAgainstBaseURL: false)
            else {
                throw CFAPIError.http(-1)
            }
            var q: [URLQueryItem] = [
                URLQueryItem(name: "per_page", value: "\(Constants.Pagination.cloudflarePageSize)"),
                URLQueryItem(name: "page", value: "\(page)"),
            ]
            if let name = nameFilter, !name.isEmpty {
                q.append(URLQueryItem(name: "name", value: name))
            }
            comps.queryItems = q
            guard let url = comps.url else {
                throw CFAPIError.http(-1)
            }
            let env: CFEnvelope<[CFZone]> = try await request(url: url, method: "GET")
            if let result = env.result { all += result }
            let next = (env.result_info?.page ?? page) < (env.result_info?.total_pages ?? page)
            if next { page += 1 } else { break }
        } while true
        return all
    }

    func getZone(zoneId: String) async throws -> CFZone {
        let url = base.appendingPathComponent("zones/\(zoneId)")
        let env: CFEnvelope<CFZone> = try await request(url: url, method: "GET")
        guard let zone = env.result else { throw CFAPIError.cloudflare(env.errors) }
        return zone
    }

    func createZone(name: String, type: String = "full", accountId: String? = nil) async throws -> CFZone {
        let resolvedAccountId = (accountId ?? accountIdProvider())?.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload = CFCreateZoneRequest(
            account: CFCreateZoneAccount(id: resolvedAccountId?.isEmpty == false ? resolvedAccountId : nil),
            name: name,
            type: type
        )
        let url = base.appendingPathComponent("zones")
        let env: CFEnvelope<CFZone> = try await request(url: url, method: "POST", body: payload)
        guard let zone = env.result else { throw CFAPIError.cloudflare(env.errors) }
        return zone
    }

    // MARK: - Records

    func listRecords(zoneId: String) async throws -> [CFDNSRecord] {
        var all: [CFDNSRecord] = []
        var page = 1
        repeat {
            guard var comps = URLComponents(
                url: base.appendingPathComponent("zones/\(zoneId)/dns_records"),
                resolvingAgainstBaseURL: false
            ) else {
                throw CFAPIError.http(-1)
            }
            comps.queryItems = [
                URLQueryItem(name: "per_page", value: "\(Constants.Pagination.cloudflareMaxPageSize)"),
                URLQueryItem(name: "page", value: "\(page)"),
            ]
            guard let url = comps.url else {
                throw CFAPIError.http(-1)
            }
            let env: CFEnvelope<[CFDNSRecord]> = try await request(url: url, method: "GET")
            if let result = env.result { all += result }
            let next = (env.result_info?.page ?? page) < (env.result_info?.total_pages ?? page)
            if next { page += 1 } else { break }
        } while true
        return all
    }

    func createRecord(zoneId: String, payload: CreateDNSRecordRequest) async throws -> CFDNSRecord {
        let url = base.appendingPathComponent("zones/\(zoneId)/dns_records")
        let env: CFEnvelope<CFDNSRecord> = try await request(url: url, method: "POST", body: payload)
        guard let record = env.result else { throw CFAPIError.cloudflare(env.errors) }
        return record
    }

    func updateRecord(zoneId: String, recordId: String, payload: UpdateDNSRecordRequest) async throws -> CFDNSRecord {
        let url = base.appendingPathComponent("zones/\(zoneId)/dns_records/\(recordId)")
        let env: CFEnvelope<CFDNSRecord> = try await request(url: url, method: "PATCH", body: payload)
        guard let record = env.result else { throw CFAPIError.cloudflare(env.errors) }
        return record
    }

    func deleteRecord(zoneId: String, recordId: String) async throws {
        let url = base.appendingPathComponent("zones/\(zoneId)/dns_records/\(recordId)")
        let env: CFEnvelope<[String: String]> = try await request(url: url, method: "DELETE")
        if !(env.success) { throw CFAPIError.cloudflare(env.errors) }
    }

    // MARK: - Internal

    private func request<T: Decodable>(url: URL, method: String, body: Encodable? = nil) async throws -> T {
        guard let token = tokenProvider() else { throw CFAPIError.missingToken }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, resp) = try await transport.send(req)
        guard let http = resp as? HTTPURLResponse else { throw CFAPIError.http(-1) }
        guard (200 ..< 300).contains(http.statusCode) else {
            if let env = try? JSONDecoder().decode(CFEnvelope<[String: String]>.self, from: data), !env.success {
                throw CFAPIError.cloudflare(env.errors)
            }
            throw CFAPIError.http(http.statusCode)
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch let decodingError {
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.general.error("Cloudflare JSON decoding failed. Response: \(responseString)")
                Logger.general.error("Decoding error: \(decodingError)")
            }
            throw CFAPIError.decoding(decodingError)
        }
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
