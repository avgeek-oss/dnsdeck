import XCTest
@testable import DNSDeckMCP

final class StringExtensionsTests: XCTestCase {
    // MARK: - Trimmed

    func testTrimmedRemovesWhitespace() {
        XCTAssertEqual("  hello  ".trimmed, "hello")
        XCTAssertEqual("\thello\t".trimmed, "hello")
        XCTAssertEqual("\nhello\n".trimmed, "hello")
    }

    func testTrimmedEmptyString() {
        XCTAssertEqual("".trimmed, "")
        XCTAssertEqual("   ".trimmed, "")
    }

    func testTrimmedNoWhitespace() {
        XCTAssertEqual("hello".trimmed, "hello")
    }

    // MARK: - IsNotEmpty

    func testIsNotEmptyWithContent() {
        XCTAssertTrue("hello".isNotEmpty)
    }

    func testIsNotEmptyWithWhitespace() {
        XCTAssertFalse("   ".isNotEmpty)
        XCTAssertFalse("".isNotEmpty)
        XCTAssertFalse("\n".isNotEmpty)
    }

    // MARK: - CapitalizedWords

    func testCapitalizedWords() {
        XCTAssertEqual("hello world".capitalizedWords, "Hello World")
        XCTAssertEqual("dns deck".capitalizedWords, "Dns Deck")
    }

    // MARK: - IsValidDomain

    func testValidDomains() {
        XCTAssertTrue("example.com".isValidDomain)
        XCTAssertTrue("sub.example.com".isValidDomain)
        XCTAssertTrue("my-site.example.com".isValidDomain)
        XCTAssertTrue("a.b.c.d.example.com".isValidDomain)
        XCTAssertTrue("example123.com".isValidDomain)
    }

    func testInvalidDomains() {
        XCTAssertFalse("".isValidDomain)
        XCTAssertFalse("-example.com".isValidDomain)
        XCTAssertFalse("example-.com".isValidDomain)
        XCTAssertFalse(".example.com".isValidDomain)
    }

    // MARK: - IsValidIPv4

    func testValidIPv4Addresses() {
        XCTAssertTrue("192.168.1.1".isValidIPv4)
        XCTAssertTrue("0.0.0.0".isValidIPv4)
        XCTAssertTrue("255.255.255.255".isValidIPv4)
        XCTAssertTrue("10.0.0.1".isValidIPv4)
        XCTAssertTrue("127.0.0.1".isValidIPv4)
    }

    func testInvalidIPv4Addresses() {
        XCTAssertFalse("".isValidIPv4)
        XCTAssertFalse("256.0.0.1".isValidIPv4)
        XCTAssertFalse("1.2.3".isValidIPv4)
        XCTAssertFalse("abc.def.ghi.jkl".isValidIPv4)
        XCTAssertFalse("1.2.3.4.5".isValidIPv4)
    }

    // MARK: - IsValidIPv6

    func testValidIPv6Addresses() {
        XCTAssertTrue("::1".isValidIPv6)
        XCTAssertTrue("::".isValidIPv6)
        XCTAssertTrue("2001:0db8:85a3:0000:0000:8a2e:0370:7334".isValidIPv6)
        XCTAssertTrue("2001:db8::1".isValidIPv6)
        XCTAssertTrue("fe80::1".isValidIPv6)
    }

    func testInvalidIPv6Addresses() {
        XCTAssertFalse("".isValidIPv6)
        XCTAssertFalse("not-an-ipv6".isValidIPv6)
        XCTAssertFalse("192.168.1.1".isValidIPv6)
    }
}
