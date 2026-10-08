import SwiftUI

struct NativeTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var lineLimit: Int?
    var minHeight: CGFloat?
    var accessibilityIdentifier: String?
    var onSubmit: (() -> Void)?
    var submitLabel: SubmitLabel = .done

    var body: some View {
        if let accessibilityIdentifier {
            field.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            field
        }
    }

    private var field: some View {
        TextField(placeholder, text: $text, axis: axis)
            .lineLimit(lineLimit)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .frame(minHeight: minHeight, alignment: .top)
    }
}

struct NativeSecureField: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat?

    var body: some View {
        SecureField(placeholder, text: $text)
            .frame(minHeight: minHeight, alignment: .top)
    }
}

struct NativeNumericField: View {
    let placeholder: String
    @Binding var value: Int
    var width: CGFloat?

    var body: some View {
        TextField(placeholder, value: $value, format: .number)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .frame(width: width)
    }
}

#Preview {
    VStack(spacing: 16) {
        NativeTextField(placeholder: "Enter text", text: .constant(""))

        NativeTextField(
            placeholder: "Multi-line text",
            text: .constant(""),
            axis: .vertical,
            lineLimit: 4,
            minHeight: 80
        )

        NativeSecureField(placeholder: "Password", text: .constant(""))

        NativeNumericField(
            placeholder: "Number",
            value: .constant(42),
            width: 120
        )
    }
    .padding()
}
