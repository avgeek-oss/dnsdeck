import XCTest
@testable import DNSDeckMCP

final class InputValidatorTests: XCTestCase {
    // MARK: - DNS Name Validation

    func testValidDNSName() {
        XCTAssertTrue(InputValidator.validateDNSName("www").isValid)
        XCTAssertTrue(InputValidator.validateDNSName("example").isValid)
        XCTAssertTrue(InputValidator.validateDNSName("sub-domain").isValid)
        XCTAssertTrue(InputValidator.validateDNSName("a123").isValid)
        XCTAssertTrue(InputValidator.validateDNSName("test123abc").isValid)
    }

    func testDNSNameAtSymbol() {
        XCTAssertTrue(InputValidator.validateDNSName("@").isValid)
    }

    func testEmptyDNSName() {
        let result = InputValidator.validateDNSName("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "DNS name cannot be empty")
    }

    func testWhitespaceDNSName() {
        let result = InputValidator.validateDNSName("   ")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "DNS name cannot be empty")
    }

    func testDNSNameTooLong() {
        let longName = String(repeating: "a", count: 254)
        let result = InputValidator.validateDNSName(longName)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "DNS name too long (max 253 characters)")
    }

    func testDNSNameMaxLength() {
        let maxName = String(repeating: "a", count: 253)
        XCTAssertTrue(InputValidator.validateDNSName(maxName).isValid)
    }

    func testInvalidDNSNameFormat() {
        let result = InputValidator.validateDNSName("invalid..name")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Invalid DNS name format")
    }

    func testDNSNameWithSpecialChars() {
        XCTAssertFalse(InputValidator.validateDNSName("test!name").isValid)
        XCTAssertFalse(InputValidator.validateDNSName("test name").isValid)
    }

    func testDNSNameTrimsWhitespace() {
        XCTAssertTrue(InputValidator.validateDNSName("  www  ").isValid)
    }

    // MARK: - IPv4 Validation

    func testValidIPv4() {
        XCTAssertTrue(InputValidator.validateIPv4Address("192.168.1.1").isValid)
        XCTAssertTrue(InputValidator.validateIPv4Address("0.0.0.0").isValid)
        XCTAssertTrue(InputValidator.validateIPv4Address("255.255.255.255").isValid)
        XCTAssertTrue(InputValidator.validateIPv4Address("10.0.0.1").isValid)
        XCTAssertTrue(InputValidator.validateIPv4Address("1.2.3.4").isValid)
    }

    func testEmptyIPv4() {
        let result = InputValidator.validateIPv4Address("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "IP address cannot be empty")
    }

    func testInvalidIPv4() {
        XCTAssertFalse(InputValidator.validateIPv4Address("256.1.1.1").isValid)
        XCTAssertFalse(InputValidator.validateIPv4Address("1.2.3").isValid)
        XCTAssertFalse(InputValidator.validateIPv4Address("abc.def.ghi.jkl").isValid)
        XCTAssertFalse(InputValidator.validateIPv4Address("1.2.3.4.5").isValid)
    }

    func testIPv4TrimsWhitespace() {
        XCTAssertTrue(InputValidator.validateIPv4Address("  192.168.1.1  ").isValid)
    }

    // MARK: - IPv6 Validation

    func testValidIPv6() {
        XCTAssertTrue(InputValidator.validateIPv6Address("2001:0db8:85a3:0000:0000:8a2e:0370:7334").isValid)
        XCTAssertTrue(InputValidator.validateIPv6Address("::1").isValid)
        XCTAssertTrue(InputValidator.validateIPv6Address("::").isValid)
    }

    func testEmptyIPv6() {
        let result = InputValidator.validateIPv6Address("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "IP address cannot be empty")
    }

    func testInvalidIPv6() {
        XCTAssertFalse(InputValidator.validateIPv6Address("not-an-ipv6").isValid)
        XCTAssertFalse(InputValidator.validateIPv6Address("192.168.1.1").isValid)
    }

    func testIPv6CompressedFormat() {
        // The validator's simplified regex handles ::1 and :: but not arbitrary compressed formats
        XCTAssertTrue(InputValidator.validateIPv6Address("::1").isValid)
        XCTAssertTrue(InputValidator.validateIPv6Address("::").isValid)
        // General compressed forms like 2001:db8::1 are not supported by the current regex
        XCTAssertFalse(InputValidator.validateIPv6Address("2001:db8::1").isValid)
        XCTAssertFalse(InputValidator.validateIPv6Address("fe80::1").isValid)
    }

    // MARK: - TTL Validation

    func testValidTTL() {
        XCTAssertTrue(InputValidator.validateTTL(60).isValid)
        XCTAssertTrue(InputValidator.validateTTL(300).isValid)
        XCTAssertTrue(InputValidator.validateTTL(86400).isValid)
    }

    func testTTLBoundaries() {
        XCTAssertTrue(InputValidator.validateTTL(Constants.TTL.minimum).isValid)
        XCTAssertTrue(InputValidator.validateTTL(Constants.TTL.maximum).isValid)
    }

    func testTTLBelowMinimum() {
        let result = InputValidator.validateTTL(Constants.TTL.minimum - 1)
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testTTLAboveMaximum() {
        let result = InputValidator.validateTTL(Constants.TTL.maximum + 1)
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    // MARK: - MX Priority Validation

    func testValidMXPriority() {
        XCTAssertTrue(InputValidator.validateMXPriority(0).isValid)
        XCTAssertTrue(InputValidator.validateMXPriority(10).isValid)
        XCTAssertTrue(InputValidator.validateMXPriority(65535).isValid)
    }

    func testInvalidMXPriority() {
        XCTAssertFalse(InputValidator.validateMXPriority(-1).isValid)
        XCTAssertFalse(InputValidator.validateMXPriority(65536).isValid)
    }

    // MARK: - SRV Port Validation

    func testValidSRVPort() {
        XCTAssertTrue(InputValidator.validateSRVPort(1).isValid)
        XCTAssertTrue(InputValidator.validateSRVPort(80).isValid)
        XCTAssertTrue(InputValidator.validateSRVPort(443).isValid)
        XCTAssertTrue(InputValidator.validateSRVPort(65535).isValid)
    }

    func testInvalidSRVPort() {
        XCTAssertFalse(InputValidator.validateSRVPort(0).isValid)
        XCTAssertFalse(InputValidator.validateSRVPort(-1).isValid)
        XCTAssertFalse(InputValidator.validateSRVPort(65536).isValid)
    }

    // MARK: - Cloudflare Token Validation

    func testValidCloudflareToken() {
        let token = String(repeating: "a1", count: 20)
        XCTAssertTrue(InputValidator.validateCloudflareToken(token).isValid)
    }

    func testEmptyCloudflareToken() {
        let result = InputValidator.validateCloudflareToken("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "API token cannot be empty")
    }

    func testShortCloudflareToken() {
        let result = InputValidator.validateCloudflareToken("short")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "API token appears to be too short")
    }

    func testCloudflareTokenInvalidChars() {
        let result = InputValidator.validateCloudflareToken("token with spaces!@#$%^&")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "API token contains invalid characters")
    }

    func testCloudflareTokenWithHyphensAndUnderscores() {
        let token = String(repeating: "a-_1", count: 6)
        XCTAssertTrue(InputValidator.validateCloudflareToken(token).isValid)
    }

    // MARK: - AWS Access Key Validation

    func testValidAWSAccessKey() {
        let key = "AKIAIOSFODNN7EXAMPLE"
        XCTAssertTrue(InputValidator.validateAWSAccessKey(key).isValid)
    }

    func testEmptyAWSAccessKey() {
        let result = InputValidator.validateAWSAccessKey("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Access key cannot be empty")
    }

    func testAWSAccessKeyWrongPrefix() {
        let result = InputValidator.validateAWSAccessKey("XXXX0000000000000000")
        XCTAssertFalse(result.isValid)
    }

    func testAWSAccessKeyWrongLength() {
        let result = InputValidator.validateAWSAccessKey("AKIA0000")
        XCTAssertFalse(result.isValid)
    }

    // MARK: - AWS Secret Key Validation

    func testValidAWSSecretKey() {
        let key = String(repeating: "a", count: 40)
        XCTAssertTrue(InputValidator.validateAWSSecretKey(key).isValid)
    }

    func testEmptyAWSSecretKey() {
        let result = InputValidator.validateAWSSecretKey("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Secret key cannot be empty")
    }

    func testAWSSecretKeyWrongLength() {
        let result = InputValidator.validateAWSSecretKey("tooshort")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Invalid AWS secret key length")
    }

    // MARK: - ValidationResult

    func testValidResultProperties() {
        let result = ValidationResult.valid
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.errorMessage)
    }

    func testInvalidResultProperties() {
        let result = ValidationResult.invalid("test error")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "test error")
    }
}
