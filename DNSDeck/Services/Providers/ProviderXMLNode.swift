import Foundation

enum ProviderXMLDocumentError: LocalizedError {
    case invalidDocument

    var errorDescription: String? {
        "The provider returned invalid XML."
    }
}

final class ProviderXMLNode: NSObject, XMLParserDelegate {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [ProviderXMLNode] = []
    private var stack: [ProviderXMLNode] = []

    init(name: String = "", attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    static func parse(_ data: Data) throws -> ProviderXMLNode {
        let tree = ProviderXMLNode()
        tree.stack = [tree]
        let parser = XMLParser(data: data)
        parser.delegate = tree
        guard parser.parse(), let root = tree.children.first else {
            throw parser.parserError ?? ProviderXMLDocumentError.invalidDocument
        }
        return root
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = ProviderXMLNode(name: elementName, attributes: attributeDict)
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

    var trimmedText: String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func children(named name: String) -> [ProviderXMLNode] {
        children.filter { $0.name == name }
    }

    func children(caseInsensitiveName name: String) -> [ProviderXMLNode] {
        children.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func child(named name: String) -> ProviderXMLNode? {
        children(named: name).first
    }

    func descendant(named name: String) -> ProviderXMLNode? {
        descendants(named: name).first
    }

    func descendants(named name: String) -> [ProviderXMLNode] {
        children.filter { $0.name == name } + children.flatMap { $0.descendants(named: name) }
    }

    func text(named name: String) -> String? {
        descendant(named: name)?.trimmedText
    }

    func optionalBoolean(named name: String) -> Bool? {
        text(named: name).map { $0.caseInsensitiveCompare("true") == .orderedSame }
    }

    func boolean(named name: String) -> Bool {
        optionalBoolean(named: name) ?? false
    }

    func attribute(_ name: String) -> String? {
        attributes[name]
    }

    func optionalBooleanAttribute(_ name: String) -> Bool? {
        attribute(name).map { $0.caseInsensitiveCompare("true") == .orderedSame }
    }

    func booleanAttribute(_ name: String) -> Bool {
        optionalBooleanAttribute(name) ?? false
    }
}
