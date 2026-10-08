import Foundation

/// Request metadata safe for logs. User info, query values, and fragments are
/// removed while retaining the method, origin, and path needed for diagnostics.
public struct RedactedHTTPRequest: CustomStringConvertible, Equatable, Sendable {
    public let method: HTTPMethod
    public let url: URL?

    public init(request: URLRequest) {
        self.init(method: HTTPMethod(request.httpMethod), url: request.url)
    }

    public init(method: HTTPMethod, url: URL?) {
        self.method = method
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            self.url = url
            return
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        self.url = components.url
    }

    public var description: String {
        "\(method.rawValue) \(url?.absoluteString ?? "<invalid-url>")"
    }
}
