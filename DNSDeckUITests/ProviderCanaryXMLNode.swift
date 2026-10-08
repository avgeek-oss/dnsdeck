import Foundation

final class ProviderCanaryXMLNode: NSObject, XMLParserDelegate {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [ProviderCanaryXMLNode] = []
    private var stack: [ProviderCanaryXMLNode] = []

    init(name: String = "", attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    static func parse(_ data: Data) throws -> ProviderCanaryXMLNode {
        let tree = ProviderCanaryXMLNode()
        tree.stack = [tree]
        let parser = XMLParser(data: data)
        parser.delegate = tree
        guard parser.parse(), let root = tree.children.first else {
            throw parser.parserError ?? ProviderCanaryBackendError.invalidResponse
        }
        return root
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String] = [:]
    ) {
        let node = ProviderCanaryXMLNode(name: elementName, attributes: attributes)
        stack.last?.children.append(node)
        stack.append(node)
    }

    func parser(
        _: XMLParser,
        didEndElement _: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        stack.removeLast()
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func children(named name: String) -> [ProviderCanaryXMLNode] {
        children.filter { $0.name == name }
    }

    func child(named name: String) -> ProviderCanaryXMLNode? {
        children(named: name).first
    }

    func descendants(named name: String) -> [ProviderCanaryXMLNode] {
        children.filter { $0.name == name } +
            children.flatMap { $0.descendants(named: name) }
    }

    func descendants(caseInsensitiveName name: String) -> [ProviderCanaryXMLNode] {
        children.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame } +
            children.flatMap { $0.descendants(caseInsensitiveName: name) }
    }

    func text(named name: String) -> String? {
        descendants(named: name).first?.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func attribute(_ name: String) -> String? {
        attributes.first {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    func boolean(named name: String) -> Bool {
        text(named: name)?.caseInsensitiveCompare("true") == .orderedSame
    }

    func booleanAttribute(_ name: String) -> Bool {
        attribute(name)?.caseInsensitiveCompare("true") == .orderedSame
    }
}
