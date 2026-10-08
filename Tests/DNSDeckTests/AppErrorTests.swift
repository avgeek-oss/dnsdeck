import XCTest
@testable import DNSDeckMCP

final class AppErrorTests: XCTestCase {
    // MARK: - NetworkError

    func testNetworkErrorDescriptions() {
        XCTAssertEqual(
            NetworkError.noInternetConnection.errorDescription,
            "No internet connection available"
        )
        XCTAssertEqual(
            NetworkError.timeout.errorDescription,
            "Request timed out"
        )
        XCTAssertEqual(
            NetworkError.serverError(500).errorDescription,
            "Server error: 500"
        )
        XCTAssertEqual(
            NetworkError.invalidResponse.errorDescription,
            "Invalid response from server"
        )
        XCTAssertEqual(
            NetworkError.decodingFailed.errorDescription,
            "Failed to decode server response"
        )
    }

    // MARK: - KeychainError

    func testKeychainErrorDescriptions() {
        XCTAssertEqual(
            KeychainError.itemNotFound.errorDescription,
            "Credential not found in keychain"
        )
        XCTAssertEqual(
            KeychainError.duplicateItem.errorDescription,
            "Credential already exists"
        )
        XCTAssertEqual(
            KeychainError.invalidData.errorDescription,
            "Invalid credential data"
        )
        XCTAssertEqual(
            KeychainError.accessDenied.errorDescription,
            "Access denied to keychain"
        )
    }

    // MARK: - ValidationError

    func testValidationErrorDescriptions() {
        XCTAssertEqual(
            ValidationError.invalidDomain("bad.").errorDescription,
            "Invalid domain: bad."
        )
        XCTAssertEqual(
            ValidationError.invalidIPAddress("999.999.999.999").errorDescription,
            "Invalid IP address: 999.999.999.999"
        )
        XCTAssertEqual(
            ValidationError.invalidTTL(0).errorDescription,
            "Invalid TTL: 0. Must be between 60 and 86400 seconds"
        )
        XCTAssertEqual(
            ValidationError.missingRequiredField("name").errorDescription,
            "Missing required field: name"
        )
        XCTAssertEqual(
            ValidationError.invalidRecordType("INVALID").errorDescription,
            "Invalid record type: INVALID"
        )
    }

    // MARK: - DNSError

    func testDNSErrorDescriptions() {
        XCTAssertEqual(
            DNSError.recordNotFound.errorDescription,
            "DNS record not found"
        )
        XCTAssertEqual(
            DNSError.duplicateRecord.errorDescription,
            "DNS record already exists"
        )
        XCTAssertEqual(
            DNSError.invalidRecordData.errorDescription,
            "Invalid DNS record data"
        )
        XCTAssertEqual(
            DNSError.providerError("API limit").errorDescription,
            "Provider error: API limit"
        )
        XCTAssertEqual(
            DNSError.quotaExceeded.errorDescription,
            "DNS record quota exceeded"
        )
    }

    // MARK: - CSVError

    func testCSVErrorDescriptions() {
        XCTAssertEqual(
            CSVError.fileNotFound.errorDescription,
            "CSV file not found"
        )
        XCTAssertEqual(
            CSVError.invalidFormat.errorDescription,
            "Invalid CSV file format"
        )
        XCTAssertEqual(
            CSVError.emptyFile.errorDescription,
            "CSV file is empty"
        )
        XCTAssertEqual(
            CSVError.missingHeaders(["type", "name"]).errorDescription,
            "Missing required CSV headers: type, name"
        )
        XCTAssertEqual(
            CSVError.invalidData(line: 5, message: "bad field").errorDescription,
            "Invalid data on line 5: bad field"
        )
        XCTAssertEqual(
            CSVError.tooManyRecords(1500).errorDescription,
            "Too many records in CSV file (1,500). Maximum allowed is 1000."
        )
    }

    // MARK: - AppError Wrapping

    func testAppErrorNetworkDescription() {
        let error = AppError.network(.timeout)
        XCTAssertEqual(error.errorDescription, "Request timed out")
    }

    func testAppErrorKeychainDescription() {
        let error = AppError.keychain(.itemNotFound)
        XCTAssertEqual(error.errorDescription, "Credential not found in keychain")
    }

    func testAppErrorValidationDescription() {
        let error = AppError.validation(.invalidDomain("test"))
        XCTAssertEqual(error.errorDescription, "Invalid domain: test")
    }

    func testAppErrorDNSDescription() {
        let error = AppError.dns(.recordNotFound)
        XCTAssertEqual(error.errorDescription, "DNS record not found")
    }

    func testAppErrorCSVDescription() {
        let error = AppError.csv(.emptyFile)
        XCTAssertEqual(error.errorDescription, "CSV file is empty")
    }

    func testAppErrorGeneralDescription() {
        let error = AppError.general("Something went wrong")
        XCTAssertEqual(error.errorDescription, "Something went wrong")
    }

    func testAppErrorUnknownDescription() {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? {
                "Test error"
            }
        }
        let error = AppError.unknown(TestError())
        XCTAssertEqual(error.errorDescription, "Test error")
    }

    // MARK: - Vercel Error Codes

    func testVercelErrorCodeDescriptions() {
        XCTAssertEqual(VercelErrorCode.forbidden.localizedDescription, "Access forbidden - insufficient permissions")
        XCTAssertEqual(VercelErrorCode.notFound.localizedDescription, "Resource not found")
        XCTAssertEqual(VercelErrorCode.badRequest.localizedDescription, "Invalid request")
        XCTAssertEqual(VercelErrorCode.unauthorized.localizedDescription, "Unauthorized - invalid credentials")
        XCTAssertEqual(VercelErrorCode.rateLimit.localizedDescription, "Rate limit exceeded")
        XCTAssertEqual(VercelErrorCode.invalidToken.localizedDescription, "Invalid API token")
        XCTAssertEqual(VercelErrorCode.missingToken.localizedDescription, "Missing API token")
        XCTAssertEqual(VercelErrorCode.unknown.localizedDescription, "Unknown error occurred")
    }
}
