import AvgeekLocalizationCore
import AvgeekLocalizationUI
import SwiftUI

struct SRVMetricsFields: View {
    @AppLocalized private var localize

    @Binding var srvPriority: Int
    @Binding var srvWeight: Int
    @Binding var srvPort: Int

    var body: some View {
        HStack(spacing: 12) {
            NativeNumericField(placeholder: localize("Priority"), value: $srvPriority)
            NativeNumericField(placeholder: localize("Weight"), value: $srvWeight)
            NativeNumericField(placeholder: localize("Port"), value: $srvPort)
        }
        .frame(minWidth: 280)
        .onChange(of: srvPriority) { _, newValue in
            srvPriority = min(max(newValue, 0), 65535)
        }
        .onChange(of: srvWeight) { _, newValue in
            srvWeight = min(max(newValue, 0), 65535)
        }
        .onChange(of: srvPort) { _, newValue in
            srvPort = min(max(newValue, 1), 65535)
        }
    }
}
