import AvgeekDesignSystem
import SwiftUI

struct CloudflareProxyToggle: View {
    let recordType: String
    let provider: DNSProvider
    @Binding var proxied: Bool

    var body: some View {
        if shouldShowToggle {
            Toggle("Proxy via Cloudflare", isOn: $proxied)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: proxied) { _, _ in AvgeekFeedback.selection() }
                .help("Only A/AAAA/CNAME can be proxied through Cloudflare.")
        }
    }

    private var shouldShowToggle: Bool {
        Constants.DNSRecordTypes.proxyableTypes.contains(recordType) && provider == .cloudflare
    }
}
