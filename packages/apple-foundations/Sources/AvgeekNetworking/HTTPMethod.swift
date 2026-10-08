import Foundation

/// An HTTP method that retains unknown extension methods while exposing the
/// safety and idempotency rules defined by HTTP semantics.
public struct HTTPMethod: RawRepresentable, Hashable, Sendable {
    public static let get = HTTPMethod(rawValue: "GET")
    public static let head = HTTPMethod(rawValue: "HEAD")
    public static let options = HTTPMethod(rawValue: "OPTIONS")
    public static let trace = HTTPMethod(rawValue: "TRACE")
    public static let put = HTTPMethod(rawValue: "PUT")
    public static let delete = HTTPMethod(rawValue: "DELETE")
    public static let post = HTTPMethod(rawValue: "POST")
    public static let patch = HTTPMethod(rawValue: "PATCH")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public init(_ rawValue: String?) {
        self.init(rawValue: rawValue ?? "GET")
    }

    public var isSafe: Bool {
        [.get, .head, .options, .trace].contains(self)
    }

    public var isIdempotent: Bool {
        isSafe || [.put, .delete].contains(self)
    }
}
