import SwiftUI

struct CloudflareProxyIcon: View {
    let isProxied: Bool

    var body: some View {
        if isProxied {
            Image(systemName: "network")
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityLabel("Traffic is proxied through Cloudflare")
                .help("Traffic is proxied through Cloudflare")
        }
    }
}
