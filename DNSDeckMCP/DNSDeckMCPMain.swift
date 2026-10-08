import Foundation

@main
struct DNSDeckMCPMain {
    static func main() async {
        let server = DNSDeckMCPServer(
            mcpService: DNSDeckMCPService(),
            auditLog: DNSDeckMCPAuditLog()
        )
        await server.run(input: .standardInput, output: .standardOutput)
    }
}
