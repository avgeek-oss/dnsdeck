import Foundation

public enum HTTPSessionStoragePolicy: Sendable {
    case standard
    case ephemeral
}

/// Declarative URLSession settings shared by Avgeek Apple apps. Product names,
/// user agents, timeouts, and cache policy remain caller configuration.
public struct HTTPSessionOptions: Sendable {
    public var storagePolicy: HTTPSessionStoragePolicy
    public var requestTimeout: TimeInterval?
    public var resourceTimeout: TimeInterval?
    public var cachePolicy: URLRequest.CachePolicy?
    public var usesURLCache: Bool?
    public var maximumConnectionsPerHost: Int?
    public var waitsForConnectivity: Bool?
    public var additionalHeaders: [String: String]

    public init(
        storagePolicy: HTTPSessionStoragePolicy = .standard,
        requestTimeout: TimeInterval? = nil,
        resourceTimeout: TimeInterval? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil,
        usesURLCache: Bool? = nil,
        maximumConnectionsPerHost: Int? = nil,
        waitsForConnectivity: Bool? = nil,
        additionalHeaders: [String: String] = [:]
    ) {
        self.storagePolicy = storagePolicy
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.cachePolicy = cachePolicy
        self.usesURLCache = usesURLCache
        self.maximumConnectionsPerHost = maximumConnectionsPerHost
        self.waitsForConnectivity = waitsForConnectivity
        self.additionalHeaders = additionalHeaders
    }
}

public enum HTTPSessionConfiguration {
    public static func make(options: HTTPSessionOptions = HTTPSessionOptions()) -> URLSessionConfiguration {
        let configuration: URLSessionConfiguration = switch options.storagePolicy {
        case .standard: .default
        case .ephemeral: .ephemeral
        }
        if let requestTimeout = options.requestTimeout {
            configuration.timeoutIntervalForRequest = requestTimeout
        }
        if let resourceTimeout = options.resourceTimeout {
            configuration.timeoutIntervalForResource = resourceTimeout
        }
        if let cachePolicy = options.cachePolicy {
            configuration.requestCachePolicy = cachePolicy
        }
        if options.usesURLCache == false {
            configuration.urlCache = nil
        }
        if let maximumConnectionsPerHost = options.maximumConnectionsPerHost {
            configuration.httpMaximumConnectionsPerHost = maximumConnectionsPerHost
        }
        if let waitsForConnectivity = options.waitsForConnectivity {
            configuration.waitsForConnectivity = waitsForConnectivity
        }
        if !options.additionalHeaders.isEmpty {
            configuration.httpAdditionalHeaders = options.additionalHeaders
        }
        return configuration
    }
}
