import SwiftUI

struct TypePicker: View {
    @Binding var type: String
    let provider: DNSProvider

    var body: some View {
        Picker("Record Type", selection: $type) {
            ForEach(provider.capabilities.editableRecordTypes, id: \.self) { type in
                Text(DNSRecordHelpers.typeLabel(for: type))
                    .tag(type)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("record.form.type")
        .accessibilityHint("Changes the record type and available form fields")
    }
}
