import Foundation

enum Configuration {
    @dynamicMemberLookup
    struct Section {
        let name: String

        subscript(dynamicMember key: String) -> String {
            Configuration.stringValue(forKeyPath: "\(name).\(key)")
        }
    }

    private static let configuration: [String: Any] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        guard let url = bundle.url(forResource: "Configuration", withExtension: "plist") else {
            fatalError("Configuration.plist is missing from the main bundle.")
        }

        guard let data = try? Data(contentsOf: url) else {
            fatalError("Could not load Configuration.plist data.")
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any]
        else {
            fatalError("Configuration.plist has an invalid format.")
        }

        return dictionary
    }()

    private static func stringValue(forKeyPath keyPath: String) -> String {
        let components = keyPath.split(separator: ".").map(String.init)
        var current: Any = configuration

        for component in components {
            guard let dict = current as? [String: Any],
                  let next = dict[component]
            else {
                fatalError("Missing configuration key: \(keyPath)")
            }
            current = next
        }

        guard let value = current as? String else {
            fatalError("Configuration value for key \(keyPath) is not a String.")
        }

        return value
    }

    static let API = Section(name: "API")
    static let Route53 = Section(name: "Route53")
    static let OAuth = Section(name: "OAuth")
    static let Support = Section(name: "Support")
    static let ProviderDocumentation = Section(name: "ProviderDocumentation")
}
