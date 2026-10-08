import AvgeekLocalizationCore
import AvgeekLocalizationUI
import SwiftUI

struct CommentField: View {
    @AppLocalized private var localize

    let provider: DNSProvider
    @Binding var comment: String

    var body: some View {
        if provider.capabilities.features.contains(.comments) {
            NativeTextField(
                placeholder: localize("Add a comment for this record"),
                text: $comment,
                axis: .vertical,
                lineLimit: 4,
                minHeight: 60,
                accessibilityIdentifier: "record.form.comment"
            )
        }
    }
}
