import SwiftUI

struct LockOverlayView: View {
    @EnvironmentObject private var lockController: AppLockController
    @State private var isAuthenticating = false
    @State private var didFailAuthentication = false
    @State private var hasAttemptedAutoUnlock = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                )

            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                VStack(spacing: 6) {
                    Text("DNSDeck Locked")
                        .font(.title3.weight(.semibold))
                    Text(lockController.supportsBiometrics
                        ? "Authenticate with your biometrics to continue."
                        : "Authenticate with your device password to continue.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                if didFailAuthentication {
                    Text("Unable to authenticate. Please try again.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Button {
                    attemptUnlock()
                } label: {
                    if isAuthenticating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.64)
                    } else {
                        Label("Unlock", systemImage: lockController.supportsBiometrics ? "faceid" : "key.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAuthenticating)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 400)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onAppear {
            guard !hasAttemptedAutoUnlock, !lockController.wasManuallyLocked else { return }
            hasAttemptedAutoUnlock = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                attemptUnlock()
            }
        }
    }

    private func attemptUnlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        didFailAuthentication = false

        Task {
            let success = await lockController.requestUnlock()
            await MainActor.run {
                isAuthenticating = false
                didFailAuthentication = !success
            }
        }
    }
}
