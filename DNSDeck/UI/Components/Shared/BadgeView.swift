import SwiftUI
#if os(macOS)
import AppKit
#endif

struct BadgeView: View {
    let text: String
    let color: Color
    let helpText: String
    let filled: Bool
    @AppStorage(UITestConfiguration.storageKey("dnsdeck.dimTypeBadges")) private var dimTypeBadges = false
    @Environment(\.colorScheme) private var colorScheme

    /// Filled style (light tinted background, no border) is the default on all
    /// platforms. Pass an explicit `filled` value to override.
    private static var defaultFilled: Bool {
        true
    }

    init(_ text: String, color: Color = .indigo, helpText: String = "", filled: Bool? = nil) {
        self.text = text
        self.color = color
        self.helpText = helpText
        self.filled = filled ?? Self.defaultFilled
    }

    private var effectiveColor: Color {
        dimTypeBadges ? .secondary : color
    }

    /// In light mode, filled badges use a solid color background with contrasting
    /// text. Dimmed and outlined badges are never inverted.
    private var inverted: Bool {
        filled && !dimTypeBadges && colorScheme == .light
    }

    /// Legible text color on top of the solid badge fill, chosen by relative
    /// luminance so light hues (orange/yellow/mint) keep WCAG contrast.
    private var invertedTextColor: Color {
        Color.isLight(color) ? Color.black : Color.white
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold).monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(inverted ? invertedTextColor : effectiveColor)
            .background(backgroundShape)
            .fixedSize(horizontal: true, vertical: false)
            .help(helpText)
            .accessibilityLabel(helpText.isEmpty ? text : helpText)
            .accessibilityValue(dimTypeBadges ? "Monotone" : "Color coded")
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if inverted {
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadiusBadge, style: .continuous)
                .fill(effectiveColor)
        } else if filled {
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadiusBadge, style: .continuous)
                .fill(effectiveColor.opacity(0.16))
        } else {
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadiusBadge, style: .continuous)
                .stroke(effectiveColor, lineWidth: 1)
        }
    }
}

// MARK: - Convenience Initializers for Common Types

extension BadgeView {
    init(recordType type: String, filled: Bool? = nil) {
        let color: Color = switch type.uppercased() {
        case "A", "AAAA": .orange
        case "CNAME": .teal
        case "TXT": .purple
        case "MX": .blue
        case "NS": .mint
        case "SRV": .cyan
        case "CAA": .orange
        default: .gray
        }

        self.init(
            type,
            color: color,
            helpText: type,
            filled: filled
        )
    }

    init(priority: Int?) {
        self.init(
            priority.map(String.init) ?? "—",
            color: .secondary,
            helpText: "MX record priority (lower = higher priority)"
        )
    }

    static let dmarc = BadgeView(
        "DMARC",
        color: .blue,
        helpText: "DMARC records are used to verify the authenticity of email messages"
    )

    static let dkim = BadgeView(
        "DKIM",
        color: .blue,
        helpText: "DKIM records are used to verify the authenticity of email messages"
    )

    static let spf = BadgeView(
        "SPF",
        color: .blue,
        helpText: "SPF records are used to verify the authenticity of email messages"
    )

    static let tlsrpt = BadgeView(
        "TLSRPT",
        color: .indigo,
        helpText: "TLSRPT records are used to report TLS connection issues for email domains"
    )

    static let sts = BadgeView(
        "STS",
        color: .indigo,
        helpText: "STS records are used to enforce TLS connections for email delivery"
    )

    static let bimi = BadgeView(
        "BIMI",
        color: .indigo,
        helpText: "BIMI records are used to display brand logos in authenticated email messages"
    )

    static let wildcard = BadgeView(
        "WILDCARD",
        color: .green,
        helpText: "Wildcard domains are used to match all subdomains"
    )

    static let apex = BadgeView(
        "APEX",
        color: .gray,
        helpText: "Apex domains are the root domain of the zone"
    )
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 8) {
            BadgeView(recordType: "A")
            BadgeView(recordType: "AAAA")
            BadgeView(recordType: "CNAME")
            BadgeView(recordType: "TXT")
        }

        HStack(spacing: 8) {
            BadgeView(recordType: "MX")
            BadgeView(recordType: "NS")
            BadgeView(recordType: "SRV")
            BadgeView(recordType: "CAA")
        }

        HStack(spacing: 8) {
            BadgeView.dmarc
            BadgeView.dkim
            BadgeView.spf
            BadgeView.tlsrpt
        }

        HStack(spacing: 8) {
            BadgeView.wildcard
            BadgeView.apex
        }

        BadgeView("CUSTOM", color: .purple, helpText: "Custom badge example")
    }
    .padding()
}

private extension Color {
    /// Returns true when the color is light enough that dark text reads better
    /// on a solid fill (perceived luminance above 0.6). Used to keep inverted
    /// badges WCAG-legible on light hues like orange/mint/yellow.
    static func isLight(_ color: Color) -> Bool {
        #if os(macOS)
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return false }
        let r = rgb.redComponent
        let g = rgb.greenComponent
        let b = rgb.blueComponent
        #else
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        #endif
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6
    }
}
