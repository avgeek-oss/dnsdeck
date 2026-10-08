import AvgeekLocalizationCore
import AvgeekLocalizationUI
import SwiftUI

struct ContentField: View {
    @AppLocalized private var localize

    let type: String
    @Binding var content: String
    @Binding var ptrHostname: String
    @Binding var caaValue: String
    @Binding var srvService: String
    @Binding var srvProto: String
    @Binding var srvDomain: String
    @Binding var srvTarget: String

    var body: some View {
        Group {
            switch type {
            case "TXT":
                NativeTextField(
                    placeholder: localize("TXT value"),
                    text: $content,
                    axis: .vertical,
                    lineLimit: 4,
                    minHeight: 80,
                    accessibilityIdentifier: "record.form.content.input"
                )
            case "MX":
                NativeTextField(
                    placeholder: localize("Mail server (e.g. mx1.example.com.)"),
                    text: $content
                )
            case "A":
                NativeTextField(placeholder: localize("IPv4 address (e.g. 8.8.8.8)"), text: $content)
            case "AAAA":
                NativeTextField(
                    placeholder: localize("IPv6 address (e.g. 2001:4860:4860::8888)"),
                    text: $content
                )
            case "CNAME":
                NativeTextField(
                    placeholder: localize("Target hostname (e.g. app.example.com.)"),
                    text: $content
                )
            case "NS":
                NativeTextField(
                    placeholder: localize("Authoritative nameserver (e.g. ns1.example.com.)"),
                    text: $content
                )
            case "SRV":
                SRVFields(
                    srvService: $srvService,
                    srvProto: $srvProto,
                    srvDomain: $srvDomain,
                    srvTarget: $srvTarget
                )
            case "PTR":
                NativeTextField(
                    placeholder: localize("Host target (e.g. mail.example.com.)"),
                    text: $ptrHostname
                )
            case "CAA":
                NativeTextField(
                    placeholder: localize("Issuer domain (e.g. letsencrypt.org)"),
                    text: $caaValue
                )
            default:
                NativeTextField(placeholder: localize("Value"), text: $content)
            }
        }
    }
}
