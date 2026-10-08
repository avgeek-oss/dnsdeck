import CoreFoundation
import CryptoKit
import Foundation
import Security

struct OCIRequestSigner {
    typealias SignatureProvider = (_ signingString: String, _ privateKeyPEM: String) throws -> Data

    let tenancyId: String
    let userId: String
    let fingerprint: String
    let privateKeyPEM: String

    private let signatureProvider: SignatureProvider

    init(
        tenancyId: String,
        userId: String,
        fingerprint: String,
        privateKeyPEM: String,
        signatureProvider: SignatureProvider? = nil
    ) {
        self.tenancyId = tenancyId
        self.userId = userId
        self.fingerprint = fingerprint
        self.privateKeyPEM = privateKeyPEM
        self.signatureProvider = signatureProvider ?? Self.sign
    }

    func headers(method: String, url: URL, body: Data?, date: Date) throws -> [String: String] {
        let method = method.uppercased()
        let includesBody = ["PATCH", "POST", "PUT"].contains(method)
        let host = try Self.host(for: url)
        let dateValue = Self.httpDateFormatter.string(from: date)
        let target = try Self.requestTarget(for: url)
        var headerNames = ["date", "(request-target)", "host"]
        var values: [String: String] = [
            "date": dateValue,
            "(request-target)": "\(method.lowercased()) \(target)",
            "host": host,
        ]
        var headers: [String: String] = [
            "Date": dateValue,
            "Host": host,
        ]

        if includesBody {
            let body = body ?? Data()
            headerNames.append(contentsOf: ["content-length", "content-type", "x-content-sha256"])
            values["content-length"] = String(body.count)
            values["content-type"] = "application/json"
            values["x-content-sha256"] = Data(SHA256.hash(data: body)).base64EncodedString()
            headers["Content-Length"] = String(body.count)
            headers["Content-Type"] = "application/json"
            headers["x-content-sha256"] = values["x-content-sha256"]
        }

        let signingString = headerNames.map { "\($0): \(values[$0] ?? "")" }.joined(separator: "\n")
        let signature = try signatureProvider(signingString, privateKeyPEM).base64EncodedString()
        let keyId = "\(tenancyId)/\(userId)/\(fingerprint)"
        headers["Authorization"] = [
            "Signature version=\"1\"",
            "headers=\"\(headerNames.joined(separator: " "))\"",
            "keyId=\"\(keyId)\"",
            "algorithm=\"rsa-sha256\"",
            "signature=\"\(signature)\"",
        ].joined(separator: ",")
        return headers
    }

    private static func host(for url: URL) throws -> String {
        guard let host = url.host, url.user == nil, url.password == nil else {
            throw signingError("the request URL has no trusted host")
        }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    private static func requestTarget(for url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw signingError("the request URL cannot be canonicalized")
        }
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        return components.percentEncodedQuery.map { "\(path)?\($0)" } ?? path
    }

    private nonisolated static func sign(_ signingString: String, privateKeyPEM: String) throws -> Data {
        let keyData = try rsaKeyData(from: privateKeyPEM)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        var keyError: Unmanaged<CoreFoundation.CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &keyError) else {
            throw signingError(
                keyError?.takeRetainedValue().localizedDescription ?? "the RSA private key could not be loaded"
            )
        }
        var signatureError: Unmanaged<CoreFoundation.CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingString.utf8) as CFData,
            &signatureError
        ) else {
            throw signingError(
                signatureError?.takeRetainedValue().localizedDescription ?? "the RSA signature could not be created"
            )
        }
        return signature as Data
    }

    private nonisolated static func rsaKeyData(from pem: String) throws -> Data {
        if pem.contains("BEGIN ENCRYPTED PRIVATE KEY") {
            throw signingError("encrypted private keys are not supported; provide an unencrypted OCI API key")
        }
        let isPKCS1 = pem.contains("BEGIN RSA PRIVATE KEY")
        let isPKCS8 = pem.contains("BEGIN PRIVATE KEY")
        guard isPKCS1 || isPKCS8 else {
            throw signingError("expected a PKCS#1 or PKCS#8 PEM private key")
        }
        let base64 = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            throw signingError("the PEM private key is not valid Base64")
        }
        return isPKCS1 ? data : try extractPKCS1(fromPKCS8: data)
    }

    private nonisolated static func extractPKCS1(fromPKCS8 data: Data) throws -> Data {
        var outer = DERReader(data: data)
        let sequence = try outer.read(tag: 0x30)
        var fields = DERReader(data: sequence)
        _ = try fields.read(tag: 0x02)
        _ = try fields.read(tag: 0x30)
        return try fields.read(tag: 0x04)
    }

    private nonisolated static func signingError(_ message: String) -> ProviderAPIError {
        ProviderAPIError.operationFailed(
            provider: .oracleCloud,
            operation: "request signing",
            message: message
        )
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()
}

private struct DERReader {
    let data: Data
    private(set) var index = 0

    nonisolated mutating func read(tag expectedTag: UInt8) throws -> Data {
        guard index < data.count, data[index] == expectedTag else {
            throw ProviderAPIError.operationFailed(
                provider: .oracleCloud,
                operation: "request signing",
                message: "the private key has an invalid DER structure"
            )
        }
        index += 1
        let length = try readLength()
        guard length >= 0, index + length <= data.count else {
            throw ProviderAPIError.operationFailed(
                provider: .oracleCloud,
                operation: "request signing",
                message: "the private key DER value is truncated"
            )
        }
        let value = data[index ..< index + length]
        index += length
        return Data(value)
    }

    private nonisolated mutating func readLength() throws -> Int {
        guard index < data.count else { throw invalidLength() }
        let first = data[index]
        index += 1
        if first & 0x80 == 0 { return Int(first) }
        let byteCount = Int(first & 0x7F)
        guard byteCount > 0, byteCount <= 4, index + byteCount <= data.count else {
            throw invalidLength()
        }
        var length = 0
        for _ in 0 ..< byteCount {
            length = (length << 8) | Int(data[index])
            index += 1
        }
        return length
    }

    private nonisolated func invalidLength() -> ProviderAPIError {
        ProviderAPIError.operationFailed(
            provider: .oracleCloud,
            operation: "request signing",
            message: "the private key has an invalid DER length"
        )
    }
}
