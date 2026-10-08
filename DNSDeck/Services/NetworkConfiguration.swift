import AvgeekNetworking
import Foundation

enum NetworkConfiguration {
    static let urlSession: URLSession = {
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif

        return URLSession(configuration: HTTPSessionConfiguration.make(options: HTTPSessionOptions(
            storagePolicy: .standard,
            requestTimeout: 30,
            resourceTimeout: 60,
            cachePolicy: .reloadIgnoringLocalCacheData,
            usesURLCache: false,
            maximumConnectionsPerHost: 4,
            waitsForConnectivity: true,
            additionalHeaders: ["User-Agent": "DNSDeck/1.0 (\(platform))"]
        )))
    }()
}
