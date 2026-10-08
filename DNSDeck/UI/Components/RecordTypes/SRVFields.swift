import AvgeekLocalizationCore
import AvgeekLocalizationUI
import SwiftUI

struct SRVFields: View {
    @AppLocalized private var localize

    @Binding var srvService: String
    @Binding var srvProto: String
    @Binding var srvDomain: String
    @Binding var srvTarget: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                NativeTextField(placeholder: localize("Service (e.g. _sip)"), text: $srvService)

                Picker("Protocol", selection: $srvProto) {
                    ForEach(["_tcp", "_udp", "_tls"], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            NativeTextField(placeholder: localize("Domain (e.g. example.com)"), text: $srvDomain)

            NativeTextField(
                placeholder: localize("Target host (e.g. sip.example.com.)"),
                text: $srvTarget
            )
        }
    }
}
