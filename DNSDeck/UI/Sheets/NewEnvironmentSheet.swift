
import AvgeekDesignSystem
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct EnvironmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var environmentName = ""
    @FocusState private var isNameFieldFocused: Bool

    let environment: DNSEnvironment?

    init(environment: DNSEnvironment? = nil) {
        self.environment = environment
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Environment Name", text: $environmentName)
                    .focused($isNameFieldFocused)
                    .onSubmit(save)
            }
            .formStyle(.grouped)
            .navigationTitle(environment == nil ? "New Environment" : "Rename Environment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(environment == nil ? "Create" : "Save", action: save)
                        .disabled(environmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        #if os(macOS)
                        .keyboardShortcut(.defaultAction)
                        #endif
                }
            }
            .onAppear {
                environmentName = environment?.name ?? ""
                isNameFieldFocused = true
            }
        }
        #if os(macOS)
        .frame(width: 400)
        #endif
    }

    private func save() {
        let trimmedName = environmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if var environment {
            environment.name = trimmedName
            model.environmentManager.updateEnvironment(environment)
        } else {
            model.selectedEnvironment = model.environmentManager.createEnvironment(name: trimmedName)
        }
        AvgeekFeedback.success()
        dismiss()
    }
}
