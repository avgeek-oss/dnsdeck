import AvgeekDesignSystem
import AvgeekLocalizationCore
import AvgeekLocalizationUI
import SwiftUI

struct TTLField: View {
    @AppLocalized private var localize

    @Binding var ttlAuto: Bool
    @Binding var ttlValue: Int
    let provider: DNSProvider

    init(ttlAuto: Binding<Bool>, ttlValue: Binding<Int>, provider: DNSProvider) {
        _ttlAuto = ttlAuto
        _ttlValue = ttlValue
        self.provider = provider
    }

    var body: some View {
        Group {
            Toggle("Automatic TTL", isOn: $ttlAuto)
                .disabled(!provider.supportsAutoTTL)
                .onChange(of: ttlAuto) { _, _ in AvgeekFeedback.selection() }

            if showValueField {
                NativeNumericField(
                    placeholder: localize("Seconds"),
                    value: $ttlValue
                )
            }
        }
        .help(Text(helpText))
        .onChange(of: ttlValue) { _, newValue in
            ttlValue = min(max(newValue, provider.minTTL), provider.maxTTL)
        }
        .onAppear {
            if !provider.supportsAutoTTL {
                ttlAuto = false
            }
            if ttlValue == 0 {
                ttlValue = provider.defaultTTL == 1 ? 300 : provider.defaultTTL
            }
        }
    }

    /// Hide the value field while Automatic TTL is active.
    private var showValueField: Bool {
        !(ttlAuto && provider.supportsAutoTTL)
    }

    private var helpText: LocalizedStringResource {
        provider.ttlHelpText
    }
}
