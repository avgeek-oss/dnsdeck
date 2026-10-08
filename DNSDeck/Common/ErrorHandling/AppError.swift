import Foundation

enum AppError: Error, LocalizedError {
    case network(NetworkError)
    case keychain(KeychainError)
    case validation(ValidationError)
    case dns(DNSError)
    case csv(CSVError)
    case general(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case let .network(error):
            error.localizedDescription
        case let .keychain(error):
            error.localizedDescription
        case let .validation(error):
            error.localizedDescription
        case let .dns(error):
            error.localizedDescription
        case let .csv(error):
            error.localizedDescription
        case let .general(message):
            message
        case let .unknown(error):
            error.localizedDescription
        }
    }
}

enum NetworkError: Error, LocalizedError {
    case noInternetConnection
    case timeout
    case serverError(Int)
    case invalidResponse
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .noInternetConnection:
            AppLocalization.string("No internet connection available")
        case .timeout:
            AppLocalization.string("Request timed out")
        case let .serverError(code):
            AppLocalization.string("Server error: \(code)")
        case .invalidResponse:
            AppLocalization.string("Invalid response from server")
        case .decodingFailed:
            AppLocalization.string("Failed to decode server response")
        }
    }
}

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case invalidData
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            AppLocalization.string("Credential not found in keychain")
        case .duplicateItem:
            AppLocalization.string("Credential already exists")
        case .invalidData:
            AppLocalization.string("Invalid credential data")
        case .accessDenied:
            AppLocalization.string("Access denied to keychain")
        }
    }
}

enum ValidationError: Error, LocalizedError {
    case invalidDomain(String)
    case invalidIPAddress(String)
    case invalidTTL(Int)
    case missingRequiredField(String)
    case invalidRecordType(String)

    var errorDescription: String? {
        switch self {
        case let .invalidDomain(domain):
            AppLocalization.string("Invalid domain: \(domain)")
        case let .invalidIPAddress(ip):
            AppLocalization.string("Invalid IP address: \(ip)")
        case let .invalidTTL(ttl):
            AppLocalization.string("Invalid TTL: \(ttl). Must be between 60 and 86400 seconds")
        case let .missingRequiredField(field):
            AppLocalization.string("Missing required field: \(field)")
        case let .invalidRecordType(type):
            AppLocalization.string("Invalid record type: \(type)")
        }
    }
}

enum DNSError: Error, LocalizedError {
    case recordNotFound
    case duplicateRecord
    case invalidRecordData
    case providerError(String)
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .recordNotFound:
            AppLocalization.string("DNS record not found")
        case .duplicateRecord:
            AppLocalization.string("DNS record already exists")
        case .invalidRecordData:
            AppLocalization.string("Invalid DNS record data")
        case let .providerError(message):
            AppLocalization.string("Provider error: \(message)")
        case .quotaExceeded:
            AppLocalization.string("DNS record quota exceeded")
        }
    }
}

enum CSVError: Error, LocalizedError {
    case fileNotFound
    case invalidFormat
    case emptyFile
    case missingHeaders([String])
    case invalidData(line: Int, message: String)
    case tooManyRecords(Int)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            AppLocalization.string("CSV file not found")
        case .invalidFormat:
            AppLocalization.string("Invalid CSV file format")
        case .emptyFile:
            AppLocalization.string("CSV file is empty")
        case let .missingHeaders(headers):
            AppLocalization.string("Missing required CSV headers: \(headers.joined(separator: ", "))")
        case let .invalidData(line, message):
            AppLocalization.string("Invalid data on line \(line): \(message)")
        case let .tooManyRecords(count):
            AppLocalization.string("Too many records in CSV file (\(count)). Maximum allowed is 1000.")
        }
    }
}
