import AvgeekLocalizationCore
import AvgeekLocalizationUI
import SwiftUI

struct MXPriorityField: View {
    @AppLocalized private var localize

    @Binding var mxPriority: Int

    var body: some View {
        NativeNumericField(placeholder: localize("Priority"), value: $mxPriority)
            .onChange(of: mxPriority) { _, newValue in
                mxPriority = min(max(newValue, 0), 65535)
            }
    }
}
