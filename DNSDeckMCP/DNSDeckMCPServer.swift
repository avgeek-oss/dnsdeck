import Foundation

final class DNSDeckMCPServer {
    private let mcpService: DNSDeckMCPService
    private let auditLog: DNSDeckMCPAuditLog
    private let serverInfo = [
        "name": "dnsdeck",
        "version": "0.1.0",
    ]

    private var clientName: String?

    init(mcpService: DNSDeckMCPService, auditLog: DNSDeckMCPAuditLog) {
        self.mcpService = mcpService
        self.auditLog = auditLog
    }

    func run(input: FileHandle, output: FileHandle) async {
        do {
            for try await line in input.bytes.lines {
                guard let response = await handleLine(line) else { continue }
                output.writeLine(response)
            }
        } catch {
            FileHandle.standardError.writeLine("dnsdeck-mcp stdio read failed: \(error.localizedDescription)")
        }
    }

    func handleLine(_ line: String) async -> String? {
        do {
            let request = try DNSDeckMCPJSON.parseObject(line)
            guard let response = try await handleRequest(request) else {
                return nil
            }
            return try DNSDeckMCPJSON.encodeLine(response)
        } catch let error as DNSDeckMCPProtocolError {
            return errorResponse(id: nil, error: error)
        } catch {
            return errorResponse(
                id: nil,
                error: .internalError(error.localizedDescription)
            )
        }
    }

    private func handleRequest(_ request: [String: Any]) async throws -> [String: Any]? {
        let id = request["id"]
        guard let method = request["method"] as? String else {
            return jsonErrorResponse(
                id: id,
                error: DNSDeckMCPProtocolError.invalidRequest("Missing method.")
            )
        }

        if method.hasPrefix("notifications/") {
            return nil
        }

        do {
            let result: [String: Any] = switch method {
            case "initialize":
                try initialize(params: request["params"] as? [String: Any])
            case "ping":
                [:]
            case "tools/list":
                ["tools": toolDefinitions()]
            case "tools/call":
                try await callTool(params: request["params"] as? [String: Any])
            case "resources/list":
                try resourcesList()
            case "resources/templates/list":
                ["resourceTemplates": resourceTemplates()]
            case "resources/read":
                try await readResource(params: request["params"] as? [String: Any])
            case "prompts/list":
                ["prompts": promptDefinitions()]
            case "prompts/get":
                try getPrompt(params: request["params"] as? [String: Any])
            default:
                throw DNSDeckMCPProtocolError.methodNotFound("Unsupported method: \(method)")
            }

            return successResponse(id: id, result: result)
        } catch let error as DNSDeckMCPProtocolError {
            return jsonErrorResponse(id: id, error: error)
        }
    }

    private func initialize(params: [String: Any]?) throws -> [String: Any] {
        let protocolVersion = params?["protocolVersion"] as? String ?? "2025-11-25"
        if let clientInfo = params?["clientInfo"] as? [String: Any],
           let name = clientInfo["name"] as? String
        {
            // This is informational host-provided metadata, not an authentication boundary.
            clientName = name
        }

        return [
            "protocolVersion": protocolVersion,
            "capabilities": [
                "tools": ["listChanged": false],
                "resources": ["subscribe": false, "listChanged": false],
                "prompts": ["listChanged": false],
            ],
            "serverInfo": serverInfo,
            "instructions": "DNSDeck MCP exposes local DNS environment, zone, and record tools. Zone creation, nameserver updates, and record add, edit, and delete use DNSDeck's configured providers and never return provider credential values.",
        ]
    }

    private func callTool(params: [String: Any]?) async throws -> [String: Any] {
        guard let name = params?["name"] as? String else {
            throw DNSDeckMCPProtocolError.invalidParams("Tool name is required.")
        }
        let arguments = params?["arguments"] as? [String: Any] ?? [:]

        let structuredContent: [String: Any]
        switch name {
        case "dnsdeck_view_environments":
            structuredContent = mcpService.viewEnvironments(
                includeProviderConnections: arguments["includeProviderConnections"] as? Bool ?? true
            )
        case "dnsdeck_view_dns_zones":
            structuredContent = await mcpService.viewDNSZones(arguments: arguments)
        case "dnsdeck_add_dns_zone":
            structuredContent = await mcpService.addDNSZone(arguments: arguments)
        case "dnsdeck_update_dns_zone_nameservers":
            structuredContent = await mcpService.updateDNSZoneNameservers(arguments: arguments)
        case "dnsdeck_read_dns_zone_records":
            structuredContent = await mcpService.readDNSZoneRecords(arguments: arguments)
        case "dnsdeck_add_dns_zone_record":
            structuredContent = await mcpService.addDNSZoneRecord(arguments: arguments)
        case "dnsdeck_edit_dns_zone_record":
            structuredContent = await mcpService.editDNSZoneRecord(arguments: arguments)
        case "dnsdeck_delete_dns_zone_record":
            structuredContent = await mcpService.deleteDNSZoneRecord(arguments: arguments)
        default:
            throw DNSDeckMCPProtocolError.invalidParams("Unknown tool: \(name)")
        }

        auditTool(name: name, arguments: arguments, result: structuredContent)

        return [
            "content": DNSDeckMCPJSON.textContent(DNSDeckMCPJSON.jsonText(structuredContent)),
            "structuredContent": structuredContent,
            "isError": structuredContent["isError"] as? Bool ?? false,
        ]
    }

    private func resourcesList() throws -> [String: Any] {
        var resources: [[String: Any]] = [
            resource(
                "dnsdeck://providers",
                name: "DNSDeck Providers",
                description: "Provider capabilities and schemas."
            ),
            resource(
                "dnsdeck://environments",
                name: "DNSDeck Environments",
                description: "Local DNSDeck environments."
            ),
            resource("dnsdeck://mcp/policy", name: "DNSDeck MCP Policy", description: "MCP record mutation policy."),
            resource(
                "dnsdeck://audit/recent",
                name: "DNSDeck MCP Audit",
                description: "Recent redacted MCP audit events."
            ),
        ]

        for environment in mcpService.listEnvironments() {
            guard let id = environment["id"] as? String,
                  let name = environment["name"] as? String
            else {
                continue
            }
            resources.append(resource(
                "dnsdeck://environments/\(id)/providers",
                name: "\(name) Provider Connections",
                description: "Provider connection status without credential values."
            ))
            resources.append(resource(
                "dnsdeck://environments/\(id)/zones",
                name: "\(name) Zones",
                description: "Connected provider zones."
            ))
        }

        return ["resources": resources]
    }

    private func readResource(params: [String: Any]?) async throws -> [String: Any] {
        guard let uri = params?["uri"] as? String else {
            throw DNSDeckMCPProtocolError.invalidParams("Resource uri is required.")
        }

        let content: [String: Any]
        if uri == "dnsdeck://providers" {
            content = [
                "schemaVersion": "dnsdeck.mcp.providers.v1",
                "providers": mcpService.listProviders(),
            ]
        } else if let provider = providerResourceValue(from: uri) {
            content = [
                "schemaVersion": "dnsdeck.mcp.provider.v1",
                "provider": mcpService.getProvider(provider),
            ]
        } else if uri == "dnsdeck://environments" {
            content = [
                "schemaVersion": "dnsdeck.mcp.environments.v1",
                "environments": mcpService.listEnvironments(),
            ]
        } else if uri == "dnsdeck://mcp/policy" {
            content = mcpService.policy()
        } else if uri == "dnsdeck://audit/recent" {
            content = [
                "schemaVersion": "dnsdeck.mcp.audit.v1",
                "events": auditLog.recent(),
            ]
        } else if let environmentId = environmentId(fromResourceURI: uri, suffix: "/providers") {
            content = [
                "schemaVersion": "dnsdeck.mcp.connections.v1",
                "environmentId": environmentId.uuidString,
                "providers": mcpService.listProviderConnections(environmentId: environmentId),
            ]
        } else if let environmentId = environmentId(fromResourceURI: uri, suffix: "/zones") {
            content = await mcpService.listZones(
                environmentId: environmentId,
                provider: providerQueryValue(from: uri),
                forceRefresh: false
            )
        } else {
            throw DNSDeckMCPProtocolError.invalidParams("Unsupported resource uri: \(uri)")
        }

        return [
            "contents": [
                [
                    "uri": uri,
                    "mimeType": "application/json",
                    "text": DNSDeckMCPJSON.jsonText(content),
                ],
            ],
        ]
    }

    private func getPrompt(params: [String: Any]?) throws -> [String: Any] {
        guard let name = params?["name"] as? String else {
            throw DNSDeckMCPProtocolError.invalidParams("Prompt name is required.")
        }
        let arguments = params?["arguments"] as? [String: Any] ?? [:]

        let text: String = switch name {
        case "dnsdeck_prepare_record_change":
            """
            Prepare a DNSDeck record-change plan for provider \(arguments["provider"] ?? "<provider>") \
            in environment \(arguments["environmentId"] ?? "<environmentId>"). First inspect the zone and records, \
            validate the proposed payload, and call the DNSDeck add/edit/delete tool only after the user confirms the exact record change.
            """
        case "dnsdeck_audit_zone":
            """
            Audit the DNSDeck zone \(arguments["zoneName"] ??
                "<zoneName>") for risky, duplicate, stale, or unsupported records. \
            Use DNSDeck view/read tools only and cite record ids for every finding.
            """
        case "dnsdeck_explain_provider_limits":
            """
            Explain DNSDeck provider limits for \(arguments["provider"] ?? "<provider>"), including credential fields, \
            supported record types, TTL policy, zone capabilities, and record mutation mode.
            """
        default:
            throw DNSDeckMCPProtocolError.invalidParams("Unknown prompt: \(name)")
        }

        return [
            "description": "DNSDeck prompt.",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        "type": "text",
                        "text": text,
                    ],
                ],
            ],
        ]
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            tool(
                name: "dnsdeck_view_environments",
                title: "View DNSDeck Environments",
                description: "List local DNSDeck environments and connected provider metadata without credential values.",
                inputSchema: objectSchema(
                    properties: [
                        "includeProviderConnections": booleanSchema(
                            description: "Include connected provider metadata. Defaults to true."
                        ),
                    ]
                )
            ),
            tool(
                name: "dnsdeck_view_dns_zones",
                title: "View DNS Zones",
                description: "List DNS zones from DNSDeck's connected providers. environmentId is optional only when one environment exists.",
                inputSchema: zoneListSchema()
            ),
            tool(
                name: "dnsdeck_add_dns_zone",
                title: "Add DNS Zone",
                description: "Create one DNS zone through DNSDeck's configured provider credentials, then return the created zone and refreshed zone list.",
                inputSchema: zoneAddSchema(),
                readOnly: false,
                idempotent: false
            ),
            tool(
                name: "dnsdeck_update_dns_zone_nameservers",
                title: "Update DNS Zone Nameservers",
                description: "Replace registrar nameservers for one zone through DNSDeck's configured provider credentials. Requires confirm=true.",
                inputSchema: zoneNameserverUpdateSchema(),
                readOnly: false,
                destructive: true,
                idempotent: false
            ),
            tool(
                name: "dnsdeck_read_dns_zone_records",
                title: "Read DNS Zone Records",
                description: "Read records for one zone using zoneId or zoneName. provider can be omitted when the zone resolves unambiguously.",
                inputSchema: recordReadSchema()
            ),
            tool(
                name: "dnsdeck_add_dns_zone_record",
                title: "Add DNS Zone Record",
                description: "Add one DNS record through DNSDeck's configured provider credentials, then return the refreshed zone records.",
                inputSchema: recordAddSchema(),
                readOnly: false,
                idempotent: false
            ),
            tool(
                name: "dnsdeck_edit_dns_zone_record",
                title: "Edit DNS Zone Record",
                description: "Edit one DNS record by recordId or recordName/recordType, then return the refreshed zone records.",
                inputSchema: recordEditSchema(),
                readOnly: false,
                idempotent: false
            ),
            tool(
                name: "dnsdeck_delete_dns_zone_record",
                title: "Delete DNS Zone Record",
                description: "Delete one DNS record by recordId or recordName/recordType. Requires confirm=true.",
                inputSchema: recordDeleteSchema(),
                readOnly: false,
                destructive: true,
                idempotent: false
            ),
        ]
    }

    private func resourceTemplates() -> [[String: Any]] {
        [
            [
                "uriTemplate": "dnsdeck://providers/{provider}",
                "name": "Provider Detail",
                "description": "DNSDeck provider capability detail.",
                "mimeType": "application/json",
            ],
            [
                "uriTemplate": "dnsdeck://environments/{environmentId}/providers",
                "name": "Environment Provider Connections",
                "description": "Provider connection status for one environment.",
                "mimeType": "application/json",
            ],
            [
                "uriTemplate": "dnsdeck://environments/{environmentId}/zones{?provider}",
                "name": "Environment Zones",
                "description": "Zones for connected providers in one environment.",
                "mimeType": "application/json",
            ],
        ]
    }

    private func promptDefinitions() -> [[String: Any]] {
        [
            prompt(
                name: "dnsdeck_prepare_record_change",
                description: "Prepare a safe record-change plan without mutating DNS.",
                arguments: ["environmentId", "provider", "zoneName"]
            ),
            prompt(
                name: "dnsdeck_audit_zone",
                description: "Audit a DNS zone using DNSDeck record data.",
                arguments: ["environmentId", "provider", "zoneName"]
            ),
            prompt(
                name: "dnsdeck_explain_provider_limits",
                description: "Explain provider capabilities and limits.",
                arguments: ["provider"]
            ),
        ]
    }

    private func environmentId(fromResourceURI uri: String, suffix: String) -> UUID? {
        guard let components = URLComponents(string: uri),
              components.scheme == "dnsdeck",
              components.host == "environments",
              components.path.hasSuffix(suffix)
        else {
            return nil
        }

        let path = components.path
        let environmentId = path
            .replacingOccurrences(of: suffix, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: environmentId)
    }

    private func providerResourceValue(from uri: String) -> DNSProvider? {
        guard let components = URLComponents(string: uri),
              components.scheme == "dnsdeck",
              components.host == "providers"
        else {
            return nil
        }

        let rawValue = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rawValue.isEmpty else { return nil }
        return DNSProvider(rawValue: rawValue)
    }

    private func providerQueryValue(from uri: String) -> DNSProvider? {
        guard let components = URLComponents(string: uri),
              let rawValue = components.queryItems?.first(where: { $0.name == "provider" })?.value
        else {
            return nil
        }
        return DNSProvider(rawValue: rawValue)
    }

    private func auditTool(name: String, arguments: [String: Any], result: [String: Any]) {
        let resultZone = result["zone"] as? [String: Any]
        auditLog.append(event: DNSDeckMCPAuditEvent(
            operation: name,
            clientName: clientName,
            environmentId: arguments["environmentId"] as? String ?? result["environmentId"] as? String,
            provider: arguments["provider"] as? String ?? result["provider"] as? String,
            zoneId: arguments["zoneId"] as? String ?? resultZone?["id"] as? String,
            recordId: arguments["recordId"] as? String,
            result: (result["isError"] as? Bool ?? false) ? "error" : "success",
            errorCode: result["code"] as? String
        ))
    }

    private func successResponse(id: Any?, result: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result,
        ]
    }

    private func jsonErrorResponse(id: Any?, error: DNSDeckMCPProtocolError) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": error.code,
                "message": error.message,
            ],
        ]
    }

    private func errorResponse(id: Any?, error: DNSDeckMCPProtocolError) -> String {
        let response = jsonErrorResponse(id: id, error: error)
        return (try? DNSDeckMCPJSON.encodeLine(
            response
        )) ?? #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
    }

    private func tool(
        name: String,
        title: String,
        description: String,
        inputSchema: [String: Any],
        readOnly: Bool = true,
        destructive: Bool = false,
        idempotent: Bool = true
    ) -> [String: Any] {
        [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": inputSchema,
            "annotations": [
                "readOnlyHint": readOnly,
                "destructiveHint": destructive,
                "idempotentHint": idempotent,
            ],
        ]
    }

    private func prompt(name: String, description: String, arguments: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "arguments": arguments.map {
                [
                    "name": $0,
                    "required": false,
                ]
            },
        ]
    }

    private func resource(_ uri: String, name: String, description: String) -> [String: Any] {
        [
            "uri": uri,
            "name": name,
            "description": description,
            "mimeType": "application/json",
        ]
    }

    private func zoneListSchema() -> [String: Any] {
        objectSchema(properties: environmentProviderProperties(
            providerDescription: "Optional DNSDeck provider filter."
        ))
    }

    private func zoneAddSchema() -> [String: Any] {
        objectSchema(
            properties: [
                "environmentId": stringSchema(
                    description: "DNSDeck environment UUID. Optional only when one environment exists."
                ),
                "provider": stringSchema(description: "DNSDeck provider id. Required for zone creation."),
                "zoneName": stringSchema(description: "DNS zone name to create, such as example.com."),
            ],
            required: ["provider", "zoneName"]
        )
    }

    private func zoneNameserverUpdateSchema() -> [String: Any] {
        var schema = objectSchema(
            properties: zoneLookupProperties().merging([
                "nameservers": arraySchema(
                    items: stringSchema(),
                    description: "Replacement nameserver hostnames. DNSDeck accepts 2 to 12 unique hostnames."
                ),
                "confirm": booleanSchema(
                    description: "Must be true to update registrar nameservers."
                ),
            ]) { _, new in new },
            required: ["nameservers", "confirm"]
        )
        schema["anyOf"] = zoneIdentifierRequirements()
        return schema
    }

    private func recordReadSchema() -> [String: Any] {
        var schema = objectSchema(properties: zoneLookupProperties())
        schema["anyOf"] = zoneIdentifierRequirements()
        return schema
    }

    private func recordAddSchema() -> [String: Any] {
        var schema = objectSchema(
            properties: zoneLookupProperties().merging(recordPayloadProperties()) { _, new in new },
            required: ["name", "type"]
        )
        schema["allOf"] = [
            ["anyOf": zoneIdentifierRequirements()],
            ["anyOf": [["required": ["content"]], ["required": ["values"]]]],
        ]
        return schema
    }

    private func recordEditSchema() -> [String: Any] {
        var schema = objectSchema(
            properties: zoneLookupProperties()
                .merging(recordSelectorProperties()) { _, new in new }
                .merging(recordPayloadProperties()) { _, new in new }
        )
        schema["allOf"] = [
            ["anyOf": zoneIdentifierRequirements()],
            ["anyOf": recordIdentifierRequirements()],
        ]
        return schema
    }

    private func recordDeleteSchema() -> [String: Any] {
        var schema = objectSchema(
            properties: zoneLookupProperties()
                .merging(recordSelectorProperties()) { _, new in new }
                .merging([
                    "confirm": booleanSchema(description: "Must be true to delete a record."),
                ]) { _, new in new },
            required: ["confirm"]
        )
        schema["allOf"] = [
            ["anyOf": zoneIdentifierRequirements()],
            ["anyOf": recordIdentifierRequirements()],
        ]
        return schema
    }

    private func environmentProviderProperties(
        providerDescription: String =
            "DNSDeck provider id. Optional when zoneId includes the provider or zoneName is unambiguous."
    ) -> [String: Any] {
        [
            "environmentId": stringSchema(
                description: "DNSDeck environment UUID. Optional only when one environment exists."
            ),
            "provider": stringSchema(description: providerDescription),
            "forceRefresh": booleanSchema(description: "Bypass the short-lived MCP cache."),
        ]
    }

    private func zoneLookupProperties() -> [String: Any] {
        environmentProviderProperties().merging([
            "zoneId": stringSchema(
                description: "DNSDeck zone id, such as provider|native-zone-id, or a native zone id."
            ),
            "zoneName": stringSchema(description: "DNS zone name."),
        ]) { _, new in new }
    }

    private func recordSelectorProperties() -> [String: Any] {
        [
            "recordId": stringSchema(
                description: "DNSDeck record id, such as provider|native-record-id, or a native record id."
            ),
            "recordName": stringSchema(description: "Record name."),
            "recordType": stringSchema(description: "Record type used with recordName when names are ambiguous."),
        ]
    }

    private func recordPayloadProperties() -> [String: Any] {
        [
            "name": stringSchema(description: "Record name, such as @, www, or a fully qualified name."),
            "type": stringSchema(description: "Record type, such as A, AAAA, CNAME, MX, TXT, SRV, or CAA."),
            "content": stringSchema(description: "Single record value."),
            "values": arraySchema(
                items: stringSchema(),
                description: "Multiple record values where the provider supports them."
            ),
            "ttl": integerSchema(description: "Record TTL in seconds. DNSDeck may normalize this to provider limits."),
            "proxied": booleanSchema(description: "Provider proxy flag, where supported."),
            "priority": integerSchema(description: "Record priority for MX/SRV/CAA-like records, where supported."),
            "comment": stringSchema(description: "Provider record comment, where supported."),
            "aliasTarget": stringSchema(description: "Alias target, where supported."),
        ]
    }

    private func zoneIdentifierRequirements() -> [[String: [String]]] {
        [
            ["required": ["zoneId"]],
            ["required": ["zoneName"]],
        ]
    }

    private func recordIdentifierRequirements() -> [[String: [String]]] {
        [
            ["required": ["recordId"]],
            ["required": ["recordName"]],
        ]
    }

    private func objectSchema(
        properties: [String: Any] = [:],
        required: [String] = []
    ) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false,
        ]
    }

    private func stringSchema(description: String? = nil) -> [String: Any] {
        [
            "type": "string",
            "description": description as Any,
        ].removingNilValues()
    }

    private func booleanSchema(description: String? = nil) -> [String: Any] {
        [
            "type": "boolean",
            "description": description as Any,
        ].removingNilValues()
    }

    private func integerSchema(description: String? = nil) -> [String: Any] {
        [
            "type": "integer",
            "description": description as Any,
        ].removingNilValues()
    }

    private func arraySchema(items: [String: Any], description: String? = nil) -> [String: Any] {
        [
            "type": "array",
            "items": items,
            "description": description as Any,
        ].removingNilValues()
    }
}
